# hyprslots design

Status: slices 1 to 6 implemented and integrated on `feature/engine` (§11);
next is the cutover. Targets Hyprland 0.56.2
(Lua config) on Omarchy 4.5.

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
  `[Tag]` and `[Tag]/Profile` (grammar in §7a).
- **Accordion**: a container whose children stack in one Hyprland group.
  Leaves only (no nested splits inside a group).
- **Overflow leaf**: where windows matched to the desk but to no free slot go.
- **Pinned screen**: a screen excluded from desk switching; it keeps showing
  whatever desk it is on.

## 4. Configuration

Two files under `$XDG_CONFIG_HOME/hyprslots/` (default `~/.config/hyprslots/`):

- `config.lua` — hand-written by the user. Real Lua: may branch on hostname,
  compute `title_matching` (§7a), and so on. Loaded with `loadfile` into a
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
  title_matching = { ... },           -- per-class title extraction (§7a)
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

### Tree syntax

A branch is tree text (`tree.lua`):

```
node      := slot | '*' | split | accordion
split     := ('h' | 'v') '[' child (',' child)* ']'     -- side by side / stacked
accordion := 'a' '[' slot (',' slot)* ']'               -- one Hyprland group
child     := node (':' weight)?                         -- weight: integer >= 1, default 1
```

`h`, `v` and `a` open a container only when `[` follows; otherwise they are
plain slot names. The root takes no weight. A slot appears at most once per
tree. An accordion holds slots only: a split, accordion, `*` or weight inside
it is rejected with its position, under the branch's config path. `*` is the
**overflow leaf** (`h[main:2, v[right, *]]`): it takes a weight like any
leaf and appears at most once per tree. `serialize.tree` writes the same
syntax back (weights of 1 left out), which is what `save` and `state` use.

### Placement

`recalculate(ctx)` is pure arithmetic: look up the active arrangement and the
workspace's desk and screen role, take the tree in force for that branch
(the configured one, or a keyboard-resized override, see below), divide
`ctx.area` by integer weights (remainder pixels go to the last child, so
sizes are exact and deterministic), and `place` each target whose window is
assigned to a slot of the branch.

Targets with no slot in the branch (unmatched windows, extra windows of a
class, windows whose slot is on another screen's branch) stack in equal rows
in the overflow leaf. A tree without `*` gets one appended as
`h[tree:3, *:1]`, a column at the right.

Slots with no window close up: the tree is pruned to the slots present and
the survivors keep their configured ratio (three slots at 1:2:1 with two
windows present tile 1:2), as aerolayout does; an empty overflow leaf closes
up the same way. A workspace that is no desk of the active arrangement, or
a desk workspace where no target has a slot, tiles its targets in equal
columns.

Workspace rules apply when a workspace is created, so `setup()` gives
`lua:slots` to desk N's workspace in every Omarchy block (N, 10+N, ... 90+N)
for each desk that has a tree, rather than tracking which blocks are
connected.

Rejected alternative: driving dwindle with dispatched splits. Dwindle's
result depends on window open order and focus at the moment each split
happens, and the dispatches race with window mapping. Arithmetic placement
has neither problem.

### Accordions

Every present member of an accordion gets the accordion's box. Realized as a
Hyprland group, the group is one layout target (`target.window` is its
current window) and so fills that box; members not yet grouped overlap in it
meanwhile. A group showing a window that is no member still gets the box.

Group membership (`groups.lua`) changes only in a deferred pass (20 ms
timer), never in `recalculate`. The pass runs after `window.open`,
`window.close` / `window.destroy`, `window.move_to_workspace` and start; after every
`router.reroute_all` (hotplug, editor edits, reload), which asks for it
once it has moved the windows, so it never races hotplug's timer hops
(§8); and when a layout pass sees an accordion split over several targets
or a stranger in its group (a drag-out fires no event, so this is what
catches it). It plans pure moves per desk workspace with an accordion: a group
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

### Keyboard resize

The provider's `layout_msg(ctx, msg)` (`resize.lua`) takes:

- `nudge <l|r|u|d> <amount>`: grow the focused window's slot toward that
  side. The nearest ancestor split in that axis with a neighbour on that
  side is adjusted, and only that neighbour gives up space (a negative
  amount shrinks the slot instead). The amount is a fraction of that
  split (`0.1`) or exact pixels (`100px`). Neither side drops below 5% of
  the split.
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

A nudge acts on the tree as the layout shows it: `layout.present` reports
the slots the layout pass would place (plus `*` when windows overflow), and
`tree.nudge` finds the hinge and measures on the pruned tree with the
overflow column appended. So the neighbour is the nearest slot that is
present, `100px` is exact with empty slots closed up or the overflow
column showing, and the appended column never gives up space (an explicit
`*` is a neighbour like any leaf). The two weights change on the matching
children of the configured split; absent siblings keep their share. An
accordion member resizes its container: a Hyprland group is one target
standing for one member, so every member of a present accordion counts as
present, whichever is focused.

Hyprland sends a layout message to the focused workspace's algorithm only,
so resize always acts on the focused window (`hl.dsp.layout("…")` from a
bind or `hyprctl dispatch`); Hyprland recalculates afterwards. A string
reply (why nothing changed) surfaces as the dispatch's error. A nudged
tree overrides the branch per arrangement, desk and screen role, in memory
(`engine.resized["<arrangement>/<desk>/<role>"]`): it survives hotplug back
to the same arrangement but not a config reload. `resize.effective_branch`
is the one lookup for the tree in force; the layout and the api (§9) both
use it. The api's `save` writes overrides to `slots.lua` and clears them,
its `reload` drops them, and `set_tree` / `set_ratio` / `record` replace
the one they edit. A nudge or reset emits the editor's change event.

`hyprslots.bind_resize_keys()` rebinds Omarchy's twelve resize keys
(`SUPER [+ SHIFT] [+ ALT|CTRL] + code:20/21`, from
`default/hypr/bindings/tiling.lua`) through `o.rebind`: on a workspace whose
tiled layout is `lua:slots` they send `resize <dx> <dy>`, elsewhere they
keep Omarchy's window resize. Each action is registered for the
keybindings menu as `hyprslots.resize_key(dx, dy)`. `setup()` does not call
it; the cutover's `bindings.lua` does, after Omarchy's bindings.

### Super+L: slots in the layout cycle (applied at cutover)

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
  of the active desk set, assign it to a slot (assignment is sticky), and
  move it to the slot's workspace when it opened elsewhere. Moves happen in
  the event callback, never in `recalculate`. `window.close` frees the slot:
  Hyprland 0.56.2 passes `window.destroy` a window whose address is already
  gone.
- **Sticky.** An assignment is kept until the window closes. When the engine
  re-solves every assignment (config reload, an api edit, hotplug), a
  window keeps its slot while the slot exists and its spec still admits the
  window's class, whatever its title says now.
- **Overflow.** A window that matches a spec while every slot it matches is
  taken goes to the desk workspace of the first of those slots (precedence
  below), where the layout stacks it in that branch's overflow leaf (§6).
  It follows that desk on hotplug and edits, and the oldest such window
  takes a matching slot as soon as one is freed. Overflowing windows count
  as having no slot, so a late title can still win them a title slot. A
  window that matches no spec at all stays where it opened.
- **Late titles.** Many apps set their real title after mapping (a terminal
  starting zellij, a browser loading its profile). On `window.title` a window
  with **no slot** is matched again once its title has been quiet for 150 ms
  (one `hl.timer` oneshot per window, replaced on every change), against the
  title it has then; on a match it is routed and placed exactly as on
  `window.open`. A window that already holds a slot is never moved because
  its title changed.
- Class-only specs additionally generate `hl.window_rule`s so the window maps
  directly on the right workspace without a visible jump (§7b).
- **Precedence.** A window takes the first free slot whose spec matches it,
  trying desks in ascending order and, within a desk, slots by name. So when
  two desks list the same spec, the lower desk wins until its slot is taken,
  then the next one (aerolayout: "first workspace in config order").
- Hyprland creates a workspace that does not exist yet on the **focused**
  monitor, and cannot create one elsewhere without showing it. So the router
  moves the window first and then, when the target workspace is on another
  monitor than its screen role's, moves the (hidden) workspace there with
  `hl.dsp.workspace.move`. Neither screen's view nor focus changes.

### 7a. Spec grammar and title matching

| Form | Matches |
|---|---|
| `App` | class (Wayland app-id) equal to `App` |
| `App/pat` | class `App` and `pat` in the window's extracted title: a case-insensitive **plain substring**; everything after the first `/` is `pat` |
| `[Tag]` | a window of a `browser_apps` class whose title contains `[Tag]` |
| `[Tag]/Profile` | ... and `(Profile)` after it: Chromium's profile title `[Tag] - Page - Person (Profile)` |

Title extraction is configured per class under `title_matching` in
`config.lua` (ported from aerolayout):

```lua
title_matching = {
  extractors = { MyEditor = " — " },          -- keep the part before (plain text)
  strip_patterns = { ssh = "%[SSH:.-%]" },     -- then delete this LUA PATTERN
  browser_apps = { "chromium" },               -- classes [Tag] specs may match
}
```

- `extractors` and `strip_patterns` extend the defaults (`kitty`,
  `Alacritty`, `foot` extract on `" | "`, the session name a zellij/tmux
  title puts first; no strip rules). `browser_apps` replaces its default
  (`google-chrome`, `chromium`, `brave-browser`, `microsoft-edge`), since it
  is a whitelist; an empty list means the default.
- `strip_patterns` are **Lua patterns, not regexes** (aerolayout used Python
  `re`): `%` escapes (`%[`, `%(`, `%d`), `.-` is the lazy `.*?`, and there is
  no alternation (`a|b`) or `{n}` counts. A malformed pattern is a config
  error at load.
- Config errors are loud (unknown key, a non-string separator, a non-list
  `browser_apps`), where aerolayout silently dropped bad YAML values.

### 7b. Generated window rules

For every class some class-only spec names, hyprslots registers one rule,
`hyprslots-<class>`, matching `^(<class>)$` (regex-escaped) with
`workspace = "<id> silent"`: the workspace of the first free slot, in the
precedence order above, that could take a window of that class, or, when
every such slot is taken, of the first of them (the desk whose overflow
leaf the router sends an extra window to). The rule is **disabled** when
that candidate is a title or tag spec (only the title can decide, so the
router does) or when its slot is on no screen of the active arrangement.

Hyprland cannot remove a window rule at runtime; registering one under an
existing `name` replaces it, and `{ name = ..., enabled = false }` turns it
off (Omarchy's workspace-modes does the same). So rules are re-registered,
only when their target changed, after every arrangement selection, every
slot taken and every slot freed, and after every api edit or reload (which
can move a slot to another screen). A Hyprland config reload starts from
scratch on both sides.

The rule is only an optimisation. The router does the same placement with or
without it; when a rule opened the window on its workspace already, the
router still moves that workspace to its screen when Hyprland created it on
the focused one.

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
due, so it always sees the workspaces as Omarchy left them. When the
re-route is done it asks for the accordion group pass (§6), so groups are
formed on the workspaces the windows now sit on. Keyboard-resized trees are
kept per arrangement, so returning to an arrangement brings its nudges
back. Hotplug never
changes a connected screen's view, so pinned screens are never refocused; a
pinned role that disappears only changes the selection. One exception: a
**non-pinned screen that is plugged (back) in shows the active desk**, the
one last switched to with `hyprslots.desk(n)` / `api.call("desk")`, after
the re-route, and focus returns to the screen that had it. Before the first
desk switch a new screen keeps whatever Omarchy shows on it.

## 9. Editor

An Omarchy shell plugin, `milan.hyprslots` (QML), with full aerolayout TUI
parity (Assignment, Layout, Slots, Arrangements views; record). It talks to
the running engine only through Hyprland:

- read: `hyprctl repl 'return hyprslots.api.state()'` (JSON string),
- write: `hyprctl repl 'return hyprslots.api.call(name, json)'`,
- push: the engine emits `hl.dsp.event("hyprslots changed <seq>")`, which the
  shell sees as a `custom>>` event on socket2 and answers with a fresh
  `state()` read.

### Api contract

`hyprslots.api.call(name, json)` returns a JSON object string, never `""`:
`{"ok": true, ...}` or `{"ok": false, "error": "..."}`. Every change bumps
`seq` and emits `hl.dsp.event("hyprslots changed <seq>")` (socket2:
`custom>>hyprslots changed <seq>`): api edits, save, reload, window open /
close, a keyboard nudge or reset, and an arrangement change on hotplug. `seq` restarts at 0 when
Hyprland reloads its config (Lua state is discarded), so the editor treats
any event as "re-read state", not as an ordering.

| Call | Arguments | Reply (besides `ok`) |
|---|---|---|
| `state` | — | see below |
| `desk` | `desk` | `desk` |
| `set_tree` | `arrangement?` (default active), `desk`, `role`, `tree` | `arrangement, desk, role, tree, ratio, seq` |
| `set_ratio` | `arrangement?`, `desk`, `role`, `ratio` (grammar below) | same as `set_tree` |
| `record` | `workspace?` (default focused), `apply?` | `arrangement, desk, role, workspace, tree, ratio, missing[], applied, seq` |
| `save` | — | `path, seq` |
| `reload` | — | `arrangement, seq` |

`state`: `seq`, `dirty` (unsaved edits, keyboard-resized trees included),
`arrangement` (active name), `screens` (role -> connector), `workspaces`
(id -> desk, role, monitor), `assignments` (address -> desk, slot),
`arrangements` (name -> `screens`, `roles[]`, `desks` ("3" -> role ->
`{tree, ratio, slots[], resized?}`), `active`, `read_only`), `resized`
(`"<arrangement>/<desk>/<role>"` -> `arrangement, desk, role, tree, ratio`
for every unsaved keyboard-resized tree), `groups[]` (one per accordion on a
desk workspace: `workspace, desk, role, slots[], members` (slot -> window
address), `group[]` (the live Hyprland group holding a member, in group
order), `formed`), `slots` ("3" -> slot -> spec text), `desks[]`,
`pinned[]`, `windows[]` (`address, class, title, workspace, floating,
box{x,y,w,h}, desk?, slot?`), `config` (`dir, data_file, editable,
read_only[]`), `refused`, `config_error`, `log_seq`.

**The tree in force** for a branch is `api.effective_branch`, which is
`resize.effective_branch`: a keyboard-resized override (§6) if there is
one, else the config's. `state` reports it, `set_ratio` starts from it,
`record` compares against it, `save` writes it.

Edits never write files: they re-run `config.lua` over the edited
`slots.lua` data in memory and take effect only when the result validates.
The new config is then applied like a hotplug: re-select, re-assign,
re-route every assigned window to its slot's workspace (a slot moved to
another screen role takes its open window along), group pass, relayout.
An edit to a branch replaces that branch's keyboard-resized override.
`save` writes `slots.lua` through `serialize` (temp file + rename), then
runs the saved data as the config and clears the overrides it wrote;
`reload` / `hyprslots.reload_config()` re-reads both files in place,
dropping unsaved edits and every override.

**Read-only fields.** A config field is the editor's only when `config.lua`
passes the data file's own table through (identity check, at the top level
and one level down). Anything built in code is listed in
`config.read_only` (`"pinned"`, `"arrangements.work"`, `"slots.4"`) and
refused by the edit calls.

**Ratio grammar** (`ratio.lua`, from aerolayout): `ratio := term (':'
term)*`, `term := (number | '*') ('[' ratio ']')?`. `2[1:2]:1` sets a
split and its first cell's split in one string; spaces separate like `:`;
decimals become the smallest integer ratio (1.5:1 -> 3:2); `*` is an
accordion pane (accordion cells take `*` or `1` and write nothing; a `*`
among tiles is refused). The `ratio` in `state` is always in this grammar
and can be sent back unchanged. This `*` is the ratio grammar's own and is
unrelated to the overflow leaf `*` of tree text.

**Record** (`record.lua`, from aerolayout's record.py): guillotine cuts
over the windows' boxes (3 px epsilon), weights snapped to integers (8%
snap, else a small integer multiple within 2%, else hundredths). A tree
holding an accordion cannot be recorded (its windows overlap), as in
aerolayout. A record that would drop a slot with no window, or the
overflow leaf, is returned with `missing` and not applied unless
`apply: true`.

**Relayout.** After an edit the engine sends a zero `hl.dsp.window.resize`
to one tiled window per desk workspace: a lua layout recalculates on any
resize request.

## 10. Modules

Under `lua/hyprslots/`:

| Kind | Module | Role |
|---|---|---|
| pure | `spec` | parse and match window specs |
| pure | `tree` | parse tree text (§6), split boxes by integer weights, nudge |
| pure | `ratio` | ratio grammar for the editor's `set_ratio` and `state` |
| pure | `record` | rebuild a tree from live window frames |
| pure | `config` | load and validate `config.lua` / `slots.lua` (sandboxed) |
| pure | `edit` | edits to the `slots.lua` data; which fields code owns |
| pure | `arrangement` | pick the arrangement matching the monitor set |
| pure | `assign` | windows → slots |
| pure | `serialize` | write `slots.lua` and tree text deterministically |
| pure | `dkjson` | vendored JSON |
| adapter | `init` | `setup()`, wrapped in `pcall`, never takes Hyprland down |
| adapter | `hl_adapter` | the only module that touches `hl` |
| adapter | `layout` | `hl.layout.register("slots", …)` |
| adapter | `router` | window events → assignment and moves |
| adapter | `desks` | desk switching on top of `o.workspaces` |
| adapter | `hotplug` | monitor events → arrangement selection, then re-route |
| adapter | `groups` | accordions as Hyprland groups (pure `plan`, deferred reconcile) |
| adapter | `resize` | keyboard resize via `layout_msg`; the tree in force |
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

| Slice | Content | Status |
|---|---|---|
| 1 Tracer | one screen, one desk tree via `lua:slots`; config, arrangement, tree, spec-by-class, layout, route, dump | done |
| 2 Desks | desks across screens, synced Super+N, pinned screens, hotplug; turns the completion test green | done |
| 3 Specs | full spec grammar, late titles, generated window rules | done |
| 4 Containers | accordion (groups) and overflow | done |
| 5 Resize | keyboard resize via `layout_msg`; `lua:slots` in the Super+L layout cycle, focused screen only | done (Super+L patches applied at cutover) |
| 6 Protocol | record, api protocol, serializer, ratio grammar | done |
| 7 Cutover | install on the user's machine, retire the old setup | next |
| Editor | skeleton + Assignment view; Layout view; Slots + Arrangements views | not started |

Slices 2 to 6 were built in parallel on top of slices 1 and 2 and
integrated on `feature/engine`; the cross-slice behaviour (keyboard-resized
trees as the api's tree in force, nudges on the laid-out tree, re-routing
and window-rule sync after edits, the group pass after hotplug's re-route,
matched extras in their desk's overflow, sticky re-solves) is described in
the sections above and covered by `e2e/accordion_replug_test.sh` and
`e2e/resize_save_test.sh`.

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
