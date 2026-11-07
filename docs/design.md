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

Rejected alternative: driving dwindle with dispatched splits. Dwindle's
result depends on window open order and focus at the moment each split
happens, and the dispatches race with window mapping. Arithmetic placement
has neither problem.

## 7. Routing

- `window.open` and `window.title` events: match the window against the specs
  of the active desk set, assign it to a slot (assignment is sticky; a late
  title change re-routes only within a short debounce window after open), and
  move it to the slot's workspace when it opened elsewhere. Moves happen in
  the event callback, never in `recalculate`.
- Class-only specs additionally generate `hl.window_rule`s so the window maps
  directly on the right workspace without a visible jump.

## 8. Arrangement selection and hotplug

Each arrangement declares `screens = { role = "<description|serial|connector>" }`.
On load and on `monitor.added` / `monitor.removed`, hyprslots picks the
arrangement whose screen set equals the connected monitor set (exact match:
every role matched by a distinct monitor and no monitor left over). The
recomputation is deferred with a oneshot timer, as Omarchy does for
`monitor.removed`, because Hyprland reports removal from inside the monitor's
teardown. Afterwards each desk's windows are re-placed under the new trees.

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
`lua/?.lua;lua/?/init.lua` to `package.path` and requires `hyprslots`. It is
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

- **S1 — e2e** (`e2e/`): a headless Hyprland instance driven only through
  `hyprctl -i <its signature>`, with headless outputs created per test and
  `foot --app-id <class>` clients. Modeled on upstream `hyprtester/`
  (`layout_custom.cpp`). Never touches the live session.
- **S2 — engine**: `hyprslots.setup()` and `api.call` run against a stubbed
  `hl` (`spec/helpers/hl_stub.lua`) under busted.
- **S3 — pure modules**: busted specs; aerolayout's unittest cases are ported
  where the logic carries over (tree parsing, weights, assignment, record).

### Completion test

`e2e/desk_across_screens_test`: outputs `big` (HEADLESS-2) and `side`
(HEADLESS-3); arrangements `dual` and `single` as in §4; slots `left`, `main`,
`right` matched to classes `t-left`, `t-main`, `t-right`.

1. The three windows open on workspace 1 in shuffled order; desk 3 is
   activated with `hyprslots.api.call("desk", '{"desk":3}')`.
2. Both outputs show their desk-3 workspace; `t-left` fills `side`;
   `t-main` and `t-right` split `big` horizontally 2:1 (±1 px).
3. `side` is removed (`hyprctl output remove HEADLESS-3`): arrangement
   `single` applies and all three tile 1:1:1 on big's desk-3 workspace.

### e2e host requirement

Hyprland 0.56.2 always requests the headless backend *plus* DRM (if
available) and Wayland (fallback); aquamarine 0.15.1's headless backend has
no DRM fd of its own, so it needs one of the other two to provide a GPU
allocator. `HYPRLAND_HEADLESS_ONLY` is not read by this Hyprland version.
Inside a running Hyprland session the DRM backend cannot open the seat
(logind: "Could not take control of session: Device or resource busy"), so
the e2e harness needs either a free seat/TTY, a VM, or a separate headless
host compositor for the Wayland backend to connect to.
