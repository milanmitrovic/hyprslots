# hyprslots design

Status: settled design, pre-implementation. Targets Hyprland 0.56.2 (Lua
config) on Omarchy 4.5.

## 1. Purpose

hyprslots gives Hyprland deterministic, named window layouts that span every
connected screen. A layout is a tree of exact integer-weighted splits whose
leaves are **slots**; each slot names the window that belongs there (a
**spec** such as `kitty/deltaf`). Opening an app routes it into its slot;
switching desks switches every screen at once; plugging or unplugging a
monitor re-selects the **arrangement** that matches the screens now present.

It is a port of the macOS tool aerolayout (private repo
`milanmitrovic/aerolayout`), which does the same on AeroSpace. The Hyprland
port drops aerolayout's external planner process entirely: everything runs as
Lua inside Hyprland's own config VM.

### Non-goals

- No daemon, no IPC server of our own, no YAML, no profiles, no hooks.
- No mouse-driven resize (parked, see §11).
- No windows spanning two screens.

## 2. Platform constraints

| Constraint | Consequence |
|---|---|
| Hyprland 0.56.2 links Lua 5.5 | Code stays portable to Lua 5.4 and 5.5 (unit tests run under 5.4 busted; no 5.5-only syntax such as `global` declarations). |
| Lua state is discarded on config reload | No state survives a reload. On every load hyprslots rebuilds from config + live windows (`hl.get_windows`, `hl.get_monitors`). |
| Callback budgets: 50 ms for layout and event callbacks, 100 ms for binds, 250 ms for `hyprctl repl` | Hot paths are pure arithmetic over small tables; no I/O in `recalculate`; config is parsed once per load. |
| No dispatching inside `recalculate` | `recalculate` only places targets. Anything that must move windows or workspaces is queued and run from an event callback or a oneshot timer. |
| `hyprctl eval` returns only `ok` | Anything that must return data goes through `hyprctl repl 'return …'`. |
| `CLuaTiledAlgorithm::resizeTarget` discards the mouse delta | Resize is keyboard-only via `layout_msg`. |
| `HL.Monitor` exposes `description`, `serial`, `name` (connector) but no make/model; `eDP-1` reports an empty description | Screens are matched by description, serial, or connector; the laptop panel is matched by connector. |

## 3. Vocabulary

- **Screen role**: a name an arrangement gives one monitor (`big`, `side`,
  `laptop`).
- **Arrangement**: a named set of screen roles plus one tree per desk. Exactly
  one arrangement is active at a time, chosen by which monitors are connected.
- **Desk N**: workspace N in each monitor's Omarchy block (§5). One desk spans
  all non-pinned screens.
- **Tree**: per desk per arrangement, a root with one branch per screen role.
  Inner nodes are `h` or `v` splits with exact integer weights
  (`h[main:2, right:1]`); leaves are slots, accordion containers, or the
  overflow leaf.
- **Slot**: a named leaf. Slots belong to the **desk** (desk 3 always has a
  `main` slot holding the same window), trees belong to the **arrangement**
  (where `main` sits and how big it is depends on which screens exist).
- **Spec**: the window matcher a slot carries: `class`, `class/title-pattern`,
  `[Tag]/Profile` and similar forms (full grammar arrives in slice 3).
- **Accordion**: a container whose children stack in one Hyprland group.
  Leaves only (no nested splits inside a group).
- **Overflow leaf**: where windows matched to the desk but to no free slot go.
- **Pinned screen**: a screen excluded from desk switching; it keeps showing
  whatever desk it is on.

## 4. Configuration

Two files under `$XDG_CONFIG_HOME/hyprslots/` (default `~/.config/hyprslots/`):

- `config.lua` — hand-written by the user. Real Lua: may branch on hostname,
  define title rules as functions, and so on. Loaded with `loadfile` into a
  sandboxed environment (no `os.execute`, `io.popen`, or `hl` dispatchers).
  It returns a table and normally loads `slots.lua`.
- `slots.lua` — data only, owned by the editor (§9). The editor rewrites it
  through the serializer; the user does not hand-edit it. Loaded in an empty
  environment, so it can only be a table literal.

Sketch:

```lua
-- config.lua
local data = load_data("slots.lua")   -- sandbox helper
return {
  slots = data.slots,                 -- desk -> slot name -> spec
  arrangements = data.arrangements,   -- name -> { screens = {...}, desks = {...} }
  pinned = { "laptop" },              -- screen roles excluded from desk switching
  title_rules = { ... },              -- code: functions over window titles
}
```

```lua
-- slots.lua (data only)
return {
  slots = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = {
        [3] = { side = "left", big = "h[main:2, right:1]" },
      },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = {
        [3] = { big = "h[left, main, right]" },
      },
    },
  },
}
```

Each `screens` value is a monitor description, serial, or connector name,
tried in that order of precedence against each connected monitor.

## 5. Desks on top of Omarchy's per-monitor workspaces

Omarchy (`/usr/share/omarchy/default/hypr/monitor-workspaces.lua`) gives each
physical monitor its own block of ten workspaces: block 0 is 1–10, block 1 is
11–20, and so on, assigned per monitor identity and persisted in
`$XDG_STATE_HOME/omarchy/monitor-workspaces`. It exposes `o.workspaces`:

- `o.workspaces.workspace_id(monitor, slot)` — workspace id of slot N on that
  monitor.
- `o.workspaces.focus(slot, monitor_name)` — returns an action (a function for
  `hl.dispatch` / `hl.bind`) that focuses slot N on that monitor.

hyprslots does not renumber workspaces; desk N on a screen is exactly
`o.workspaces.workspace_id(monitor, N)`.

**Desk switch** (the Super+N path). Public entry points:

- `hyprslots.desk(n)` — returns an action, bound to `SUPER + N` in place of
  Omarchy's `o.workspaces.focus(n)`.
- `hyprslots.api.call("desk", '{"desk": n}')` — the same operation through the
  api (used by the editor and by the e2e tests).

Both run the same function: remember the focused monitor (the origin), run
`o.workspaces.focus(n, name)` for every connected, non-pinned screen, then
refocus the origin monitor.

The screens are the active arrangement's roles minus the `pinned` ones, in
role order with the origin last, so the origin's view changes last; the
origin is refocused even when it is pinned and so did not switch. With no
active arrangement only the origin switches, as Omarchy's Super+N does.

`setup()` leaves Omarchy's Super+1..0 alone. `hyprslots.bind_desk_keys()`
rebinds `SUPER + code:10..19` to `hyprslots.desk(1..10)` through `o.rebind`
(so the keybindings menu keeps a description); the cutover calls it from the
user's config.

**hyprmoncfg.** hyprmoncfg keeps owning monitor modes and positions, but its
workspace planner must be Off. Its generated `hyprmoncfg-monitors.lua`, when
the planner is on, sets `o.workspaces.enabled = false` and replaces
`o.workspaces.focus` with global-number focus, which breaks the desk model.
hyprslots therefore refuses to start, with an `hl.notification`, while
`o.workspaces.enabled == false`. Because the hyprmoncfg file loads last in
`hyprland.lua` (after hyprslots), the check runs deferred on
`hyprland.start` / `config.reloaded`, not at require time.

## 6. Layout engine

hyprslots registers a custom layout:

```lua
hl.layout.register("slots", {
  recalculate = function(ctx) ... end,       -- place ctx.targets in ctx.area
  layout_msg  = function(ctx, msg) ... end,  -- keyboard resize, debug
})
```

and workspaces use it as `lua:slots` (see `/usr/share/hypr/stubs/hl.meta.lua`
for `HL.LayoutContext` / `HL.LayoutTarget`, upstream `example/layouts/manual.lua`,
and the wiki's custom-layouts page).

`recalculate(ctx)` is pure arithmetic: look up the active arrangement and the
workspace's desk and screen role, take that branch of the tree, divide
`ctx.area` by integer weights (remainder pixels go to the last child, so
sizes are exact and deterministic), and `place` each target whose window is
assigned to a slot. Targets with no slot go to the overflow leaf.

Slots with no window close up: the tree is pruned to the slots present and
the survivors keep their configured ratio (three slots at 1:2:1 with two
windows present tile 1:2), as aerolayout does. Until slice 4 brings the
overflow leaf, unslotted targets share a column at the right (tree 3 :
overflow 1, one row each), and a workspace that is no desk of the active
arrangement tiles its targets in equal columns.

Workspace rules apply when a workspace is created, so `setup()` gives
`lua:slots` to desk N's workspace in every Omarchy block (N, 10+N, ... 90+N)
for each desk that has a tree, rather than tracking which blocks are
connected.

Rejected alternative: driving dwindle with dispatched splits. Dwindle's
result depends on window open order and focus at the moment each split
happens, and the dispatches race with window mapping. Arithmetic placement
has neither problem.

### Accordions and the overflow leaf (slice 4)

Tree syntax: an accordion is `a[left, main, right]` (a letter opening a
container, like `h` and `v`; `a` is still a plain slot name when no `[`
follows). It holds slots only; a split, accordion, `*` or weight inside it
is rejected with its position, under the branch's config path. The overflow
leaf is `*` (`h[main:2, v[right, *]]`), takes a weight like any leaf, and
appears at most once per tree. This supersedes the interim column above: a
tree without `*` gets one appended as `h[tree:3, *:1]`, the same geometry,
now as a real leaf. Unmatched windows stack in it in equal rows; an empty
overflow leaf closes up like an empty slot.

Every present member of an accordion gets the accordion's box. Realized as a
Hyprland group, the group is one layout target (`target.window` is its
current window) and so fills that box; members not yet grouped overlap in it
meanwhile. A group showing a window that is no member still gets the box.

Group membership (`groups.lua`) changes only in a deferred pass (20 ms
timer), never in `recalculate`. The pass runs after `window.open`,
`window.destroy`, `window.move_to_workspace`, start and monitor events, and
when a layout pass sees an accordion split over several targets or a
stranger in its group (a drag-out fires no event, so this is what catches
it). It plans pure moves per desk workspace with an accordion: a group
holding a member is the accordion's (first wins), strangers are taken out
(`hl.dsp.window.move{out_of_group}`), a missing group is made with
`hl.dsp.group.toggle`, and members join with `HL.Group:add`: Hyprland has no
dispatcher that adds a named window to a named group (`into_group` takes a
direction). Members are put back after a drag-out: the tree is the truth. A
lone member stays ungrouped; groups with no accordion slot and groups on
workspaces that are no desk are left alone; floating windows are ignored.
Layout-triggered passes stop after three in a row that still had moves to
make (an error is logged), so a refused move cannot loop; any window event
re-arms them.

### Keyboard resize (slice 5)

The provider's `layout_msg(ctx, msg)` (`resize.lua`) takes:

- `nudge <l|r|u|d> <amount>`: grow the focused window's slot toward that
  side. The nearest ancestor split in that axis with a neighbour on that
  side is adjusted, and only that neighbour gives up space (a negative
  amount shrinks the slot instead). The amount is a fraction of that
  split (`0.1`) or exact pixels (`100px`, measured over `ctx.area` with
  the full branch; with empty slots or the interim overflow column the
  pixel count is approximate). Neither side drops below 5% of the split.
- `resize <dx> <dy>`: pixels, the shape of Omarchy's
  `hl.dsp.window.resize({ x, y, relative = true })` binds, with dwindle's
  feel: the slot's right (bottom) edge moves by dx (dy), or its left (top)
  edge when nothing is to its right (below).
- `reset`: back to the configured branch.

Weights stay exact integers (`tree.nudge`): the split's weights are scaled
so the nudge is a whole number of units (fractions are quantised to
1/10000 of the split; pixels scale the total to a multiple of the split's
extent, so the edge moves by exactly that many pixels), then divided by
their gcd: `h[a, b]` nudged by 0.1 becomes `h[a:3, b:2]`. `boxes` is
unchanged, so placement stays exact-pixel.

Hyprland sends a layout message to the focused workspace's algorithm only,
so resize always acts on the focused window (`hl.dsp.layout("…")` from a
bind or `hyprctl dispatch`); Hyprland recalculates afterwards. A string
reply (why nothing changed) surfaces as the dispatch's error. A nudged
tree overrides the branch per arrangement, desk and screen role in memory
only: it survives hotplug back to the same arrangement but not a config
reload. Persisting it comes with slice 6's record and serializer.

`hyprslots.bind_resize_keys()` rebinds Omarchy's twelve resize keys
(`SUPER [+ SHIFT] [+ ALT|CTRL] + code:20/21`, from
`default/hypr/bindings/tiling.lua`) through `o.rebind`: on a workspace whose
tiled layout is `lua:slots` they send `resize <dx> <dy>`, elsewhere they
keep Omarchy's window resize. Each action is registered for the
keybindings menu as `hyprslots.resize_key(dx, dy)`. `setup()` does not call
it; the cutover's `bindings.lua` does, after Omarchy's bindings.

### Super+L: slots in the layout cycle (slice 5, applied at cutover)

`contrib/super-l/` holds patches (`patch -d ~ -p1 < …`) for the user's
`~/.local/bin/workspace-layout-cycle`, `~/.local/bin/workspace-layout-current`
and `~/.config/omarchy/plugins/milan.layout/Layout.qml`. They are not applied
before the cutover.

- The cycle acts on the focused workspace only. On a hyprslots desk
  workspace (one in `hyprslots.api.call("state").workspaces`) it gains a
  slots stop between floating and tiling:
  slots → tiling → side-by-side → full-width → floating → slots
  (`back` reverses). Elsewhere it is unchanged.
- Omarchy's mode files know nothing of `lua:slots`, so "slots" is read from
  the workspace's `tiledLayout` unless the mode file says floating (floating
  keeps the tiled layout underneath).
- Entering slots from floating first applies `dwindle` through
  `o.workspace_mode` to tile the windows again, then sets the
  `lua:slots` workspace rule and removes the workspace's mode file, so the
  rule hyprslots sets at load brings slots back after a reload. Leaving slots
  applies and saves the mode the way Omarchy's toggle does.
- The bar widget shows a grid glyph (nf-md-view_grid) and "Slots".

To verify at cutover: whether a saved mode file for a desk workspace (from
leaving slots for a non-default mode) or Omarchy's default-layout command
(`omarchy-hyprland-workspace-layout-default`, which saves busy workspaces'
current mode) wins over hyprslots' load-time rule, which depends on the
order `hyprland.lua` loads them in.

## 7. Routing

- `window.open` and `window.title` events: match the window against the specs
  of the active desk set, assign it to a slot (assignment is sticky; a late
  title change re-routes only within a short debounce window after open), and
  move it to the slot's workspace when it opened elsewhere. Moves happen in
  the event callback, never in `recalculate`.
- Class-only specs additionally generate `hl.window_rule`s so the window maps
  directly on the right workspace without a visible jump.
- Hyprland creates a workspace that does not exist yet on the **focused**
  monitor, and cannot create one elsewhere without showing it. So the router
  moves the window first and then, when the target workspace is on another
  monitor than its screen role's, moves the (hidden) workspace there with
  `hl.dsp.workspace.move`. Neither screen's view nor focus changes.

## 8. Arrangement selection and hotplug

Each arrangement declares `screens = { role = "<description|serial|connector>" }`.
On load and on `monitor.added` / `monitor.removed`, hyprslots picks the
arrangement whose screen set equals the connected monitor set (exact match:
every role matched by a distinct monitor and no monitor left over). The
recomputation is deferred with a oneshot timer, as Omarchy does for
`monitor.removed`, because Hyprland reports removal from inside the monitor's
teardown. Afterwards each desk's windows are re-placed under the new trees.

Order (module `hotplug`): the event itself does nothing; a oneshot hop
re-selects the arrangement, and a second hop, created inside the first,
re-routes every assigned window (assignments are kept by window address) to
its slot's workspace under the new arrangement, the same way the router
places a new window. Omarchy reconciles on `monitor.added` inside the event
and on `monitor.removed` from a oneshot timer created in the same event, which
merges an unplugged screen's workspaces into the block of the screen they
landed on (13 becomes 4). The second hop is created after that timer has come
due, so it always sees the workspaces as Omarchy left them. Hotplug never
focuses a monitor or changes a screen's view, so pinned screens are never
refocused; a pinned role that disappears only changes the selection.

## 9. Editor

An Omarchy shell plugin, `milan.hyprslots` (QML), with full aerolayout TUI
parity (Assignment, Layout, Slots, Arrangements views; record). It talks to
the running engine only through Hyprland:

- read: `hyprctl repl 'return hyprslots.api.state()'` (JSON string),
- write: `hyprctl repl 'return hyprslots.api.call(name, json)'`,
- push: the engine emits `hl.dsp.event("hyprslots changed <seq>")`, which the
  shell sees as a `custom>>` event on socket2 and answers with a fresh
  `state()` read.

## 10. Modules

Under `lua/hyprslots/`:

| Kind | Module | Role |
|---|---|---|
| pure | `spec` | parse and match window specs |
| pure | `tree` | parse `h[main:2, right:1]`, split boxes by integer weights |
| pure | `ratio` | ratio grammar for resize and record |
| pure | `record` | rebuild a tree from live window frames |
| pure | `config` | load and validate `config.lua` / `slots.lua` (sandboxed) |
| pure | `arrangement` | pick the arrangement matching the monitor set |
| pure | `assign` | windows → slots |
| pure | `plan` | the moves needed to reach the target state |
| pure | `serialize` | write `slots.lua` deterministically |
| pure | `dkjson` | vendored JSON |
| adapter | `init` | `setup()`, wrapped in `pcall`, never takes Hyprland down |
| adapter | `hl_adapter` | the only module that touches `hl` |
| adapter | `layout` | `hl.layout.register("slots", …)` |
| adapter | `router` | window events → assignment and moves |
| adapter | `desks` | desk switching on top of `o.workspaces` |
| adapter | `hotplug` | monitor events → arrangement selection |
| adapter | `resize` | keyboard resize via `layout_msg` |
| adapter | `api` | `state()` / `call(name, json)` for the editor |
| adapter | `log` | ring buffer; `hyprslots.dump()` prints it with the state |

Other top-level directories: `editor/` (QML plugin), `spec/` (busted specs and
`spec/helpers/hl_stub.lua`), `e2e/` (headless Hyprland harness).

**Loading.** A shim `~/.config/hypr/hyprslots.lua` prepends the repo's
`lua/?.lua;lua/?/init.lua` to `package.path`, then runs
`hyprslots = require("hyprslots")` and `hyprslots.setup()`; the `hyprslots`
global is what `hyprctl repl` and the editor address. It is
required from `hyprland.lua` right after `require("hypr.autostart")`; it
cannot go after hyprmoncfg's `dofile`, which stays last.

## 11. Roadmap

| Slice | Content |
|---|---|
| 1 Tracer | one screen, one desk tree via `lua:slots`; config, arrangement, tree, spec-by-class, layout, route, dump |
| 2 Desks | desks across screens, synced Super+N, pinned screens, hotplug; turns the completion test green |
| 3 Specs | full spec grammar, late titles, generated window rules |
| 4 Containers | accordion (groups) and overflow |
| 5 Resize | keyboard resize via `layout_msg`; `lua:slots` in the Super+L layout cycle, focused screen only |
| 6 Protocol | record, api protocol, serializer, ratio grammar |
| 7 Cutover | install on the user's machine, retire the old setup |
| Editor | skeleton + Assignment view; Layout view; Slots + Arrangements views |

Parked: mouse-resize workaround, upstream Hyprland PR for a resize hook,
spanning windows, public release / AUR package, QML tests.

## 12. Test seams

- **S1 — e2e** (`e2e/`, `make e2e`): a nested Hyprland instance per test
  (see "e2e host" below) driven only through `hyprctl -i <its signature>`,
  with headless outputs created per test (`hyprctl output create headless
  HEADLESS-2`) and `foot --app-id <class>` clients. Modeled on upstream
  `hyprtester/` (`layout_custom.cpp`). Tests are `e2e/*_test.sh` defining
  `test_setup` (config written before Hyprland starts) and `test_body`,
  asserting on `hyprctl -j` output with jq via `e2e/lib.sh`. Never touches
  the live session.
- **S2 — engine**: `hyprslots.setup()` and `api.call` run against a stubbed
  `hl` (`spec/helpers/hl_stub.lua`) under busted.
- **S3 — pure modules**: busted specs; aerolayout's unittest cases are ported
  where the logic carries over (tree parsing, weights, assignment, record).

### Completion test

`e2e/desk_across_screens_test.sh`: outputs `big` (HEADLESS-2, 2400x1350 at
0,0, Omarchy block 0) and `side` (HEADLESS-3, 1920x1080 at 2400,0, block 1),
matched by connector; arrangements `dual` and `single` as in §4; slots
`left`, `main`, `right` matched to classes `t-left`, `t-main`, `t-right`.

1. The three windows open on workspace 1 in shuffled order; desk 3 is
   activated with `hyprslots.api.call("desk", '{"desk":3}')`.
2. Both outputs show their desk-3 workspace (3 on big, 13 on side);
   `t-left` fills `side`; `t-main` and `t-right` split `big` horizontally
   2:1 (1600 + 800 px, ±1 px).
3. `side` is removed (`hyprctl output remove HEADLESS-3`): arrangement
   `single` applies and all three tile 1:1:1 (800 px each) on workspace 3.

### e2e host

Hyprland 0.56.2 cannot run headless-only inside a live session. It always
requests the headless backend plus DRM (if available) and Wayland
(fallback), and ignores `HYPRLAND_HEADLESS_ONLY`; aquamarine 0.15.1's
headless backend has no GPU device of its own, so DRM or Wayland must
provide the allocator. Inside a running session the DRM backend cannot take
the seat (logind: "Could not take control of session: Device or resource
busy"). Upstream's hyprtester avoids this by running in a VM on a free TTY.

`e2e/run.sh` therefore runs, per test:

1. a headless **sway** host (`WLR_BACKENDS=headless`, `WLR_RENDERER=gles2`
   on `/dev/dri/renderD128`, `WLR_LIBINPUT_NO_DEVICES=1`, `e2e/sway.conf`:
   no bar, no binds), whose linux-dmabuf feedback hands Hyprland's Wayland
   backend the render node for its GBM allocator;
2. **Hyprland** on that socket with `-c e2e/hyprland-test.lua`. Its own
   window on the host (`WAYLAND-1`) is disabled; tests create headless
   outputs, which can be removed again to simulate hotplug.

Isolation: temp `XDG_CONFIG_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME` under
the ignored `.e2e-tmp/`, and a private `XDG_RUNTIME_DIR`
(`$XDG_RUNTIME_DIR/hs.XXXXXX`, short because of the 108-byte socket path
limit), so neither the nested Hyprland nor the harness's `hyprctl` can see
the live session's sockets. `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`,
`DISPLAY`, `DBUS_SESSION_BUS_ADDRESS` and `NOTIFY_SOCKET` are unset;
`HYPRLAND_NO_SD_VARS` / `HYPRLAND_NO_SD_NOTIFY` are set. A trap exits
Hyprland with `hl.dsp.exit()` (killing it on timeout), stops sway and the
clients, and removes the runtime dir; logs are kept under `.e2e-tmp/` when a
test fails.

One shim is needed: aquamarine binds `xdg_wm_base` at version 6
unconditionally while sway 1.12 advertises 5, and the host drops the
connection. `e2e/shim/clamp-xdg-wm-base.c`, built by `run.sh` and
`LD_PRELOAD`ed into the nested Hyprland only, clamps that one bind to 5
(version 6 only adds the `suspended` toplevel state).
