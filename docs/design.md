# hyprslots design

Status: engine slices 1 to 6 and editor slices D1 to D3 done and
integrated on `feature/editor` (§11), slots made global logical names with
specs per workspace; slice 7, the cutover, done on the user's machine from
that branch; the accordion replaced by the scroll branch (§6); then
**desks and layouts** replaced arrangements (§3, §4, §8): a desk is a
monitor setup, a layout a logical arrangement of screens that several desks
can share, and workspaces 1 to 10 are called workspaces, not desks; then
**shared trees**: a layout's default trees are the one tree per screen its
workspaces share ("All workspaces" in the editor), a workspace's own trees
an override for a real difference (§3, §9); then **one set of slots**:
every tree holds every global slot (an empty one closes up, so a slot is
used by filling it, never by placing it), a scroll branch says its own
column width (`scroll:0.5[...]` half the screen, `scroll[...]` full), and
pinned screens are gone (§3, §4, §6, §9); then **first run**: a fresh
install starts on a starter config and zero slots, and the editor guides a
newcomer from there (§4, §9); then **desk maps**: the engine records each
desk's monitor geometry in slots.lua and the Desk tab draws every desk's
monitors (§4, §8, §9).
Targets Hyprland 0.56.2 (Lua config) on Omarchy 4.5.

## 1. Purpose

hyprslots gives Hyprland deterministic, named window layouts that span every
connected screen. A layout is a tree of exact integer-weighted splits whose
leaves are **slots**; each slot names the window that belongs there (a
**spec** such as `kitty/deltaf`). Opening an app routes it into its slot;
switching workspaces switches every screen at once; plugging or unplugging
a monitor selects the **desk** (the monitor setup) now present and the
**layout** it uses.

It is a port of the macOS tool aerolayout (private repo
`milanmitrovic/aerolayout`), which does the same on AeroSpace. The Hyprland
port drops aerolayout's external planner process entirely: everything runs as
Lua inside Hyprland's own config VM. (aerolayout's own history: modes, then
desks, then arrangements; a desk was always the physical setup you sit at.)

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

- **Workspace N** (1 to 10): workspace N in each screen's block (§5):
  workspace id N on screen 1, 10+N on screen 2, and so on. One workspace
  spans all screens; Super+N switches it on all of them.
- **Desk**: a monitor setup, the set of monitors you have when you sit at
  one place (`laptop`, `docked`, `office`): each monitor named by its
  description, serial or connector. Exactly one desk is active at a time,
  the one whose monitors are the connected ones. A desk says which
  **layout** it uses.
- **Screen N**: the N-th monitor of the active desk from the left (by x,
  then y, then connector name). Layouts address screens by number, so the
  same layout fits any desk with as many monitors.
- **Layout**: a logical arrangement for exactly N screens: **default
  trees** (the **shared trees**, the editor's "All workspaces"), one per
  screen, for every workspace with none of its own, plus a workspace's own
  trees where it needs another arrangement (an **override**: a workspace's
  own trees replace the shared ones whole). Empty slots close up, so one
  shared tree serves workspaces that fill different slots of it; an
  override is for a real difference (another order, share or shape), and
  `fold_trees` drops the ones that lay out the same as the shared tree. A
  desk with N monitors may use any N-screen
  layout, and several desks may use the same one: an edit to it changes it
  for all of them (the editor says so, and can **fork** it).
- **Tree**: per workspace per layout, one per screen. Inner nodes are `h`
  or `v` splits with exact integer weights (`h[main:2, right:1]`); leaves
  are slots or the overflow leaf. A whole branch may instead be a scroll
  branch. **Every tree set holds every global slot** (a layout's shared
  trees, each workspace's own: one screen or another, §4), or leaves out
  one that another set of the same layout places and no workspace on it
  fills, so which slots a workspace uses is only which ones it fills.
- **Slot**: a named leaf, a **global logical name** (`left`, `main`,
  `right`) defined once with an optional description, aerolayout's logical
  slots. Every tree holds every slot, and one nothing fills takes no room;
  trees belong to the **layout** (where `main` sits and how big it is
  depends on the screens).
- **Spec**: the window matcher that fills a slot **on one workspace**
  (workspace 3's `main` is `kitty/deltaf`, workspace 9's `main` is
  `kitty/tako`): `class`, `class/title-pattern`, `[Tag]` and
  `[Tag]/Profile` (grammar in §7a). A slot a workspace has no spec for takes
  a window only by hand.
- **Scroll branch**: a screen's whole tree written `scroll[a, b, c]`: its
  slots are columns of Hyprland's own scrolling layout, in that order
  (aerolayout's accordion: full-screen windows side by side, scrolled
  through), full width, or another width the branch says
  (`scroll:0.5[a, b, c]`: half the screen each, two to a screen). Slots
  only, and at most the overflow leaf as the column windows with no slot
  take (`scroll[a, b, *, c]`).
- **Overflow leaf**: where windows matched to the workspace but to no free
  slot go.

## 4. Configuration

Two files under `$XDG_CONFIG_HOME/hyprslots/` (default `~/.config/hyprslots/`):

- `config.lua` — hand-written by the user. Real Lua: may branch on hostname,
  compute `title_matching` (§7a), and so on. Loaded with `loadfile` into a
  sandboxed environment (no `os.execute`, `io.popen`, or `hl` dispatchers).
  It returns a table and normally loads `slots.lua`.
- `slots.lua` — data only, owned by the editor (§9). The editor rewrites it
  through the serializer; the user does not hand-edit it. Loaded in an empty
  environment, so it can only be a table literal.

**First run.** With no `config.lua` (a fresh install) the engine writes a
starter one (`starter.lua`): commented for someone who has never seen
hyprslots (what slots are, that `slots.lua` is the editor's and rewritten on
save, that `config.lua` is real Lua and theirs, with examples), and passing
every field of `slots.lua` through (`slots`, `specs`, `desks`, `layouts`,
`monitor_names`, `workspaces`), so the editor can edit all of it; and an
empty `slots.lua` (`return {}`) where there is none. The config dir is made
when it is not there. A file that is there is never written over: the
starter is written only where `config.lua` is missing (a `config.lua` with
no `slots.lua` beside it stays a config error), and `slots.lua` only where it
is missing too. This is logged, with no notification; a starter that cannot
be written is a config error, notified. The engine then runs with **zero
slots**: the connected monitors get a desk and a layout of their own a second
later (§8), saved into `slots.lua` at once and silently (nothing on first
contact reads as unsaved), a layout with no trees (nothing to place), so no workspace is
laid out by hyprslots until the first slot is made; that slot goes into the
layout's tree at once (no layout is treeless, below), and `save` writes it
beside the starter. The editor guides the rest (§9, "First run and empty
states").

Sketch:

```lua
-- config.lua
local data = load_data("slots.lua")   -- sandbox helper
return {
  slots = data.slots,                 -- slot name -> { key?, description? }
  specs = data.specs,                 -- workspace -> slot name -> spec
  desks = data.desks,                 -- name -> { monitors, layout, geometry? }
  layouts = data.layouts,             -- name -> { screens, default?, workspaces? }
  title_matching = { ... },           -- per-class title extraction (§7a)
  workspaces = 10,                    -- optional: manage workspaces 1 to 10 (default 9)
}
```

```lua
-- slots.lua (data only)
return {
  slots = { left = { key = "l" }, main = { key = "m", description = "the editor" }, right = { key = "r" } },
  specs = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
    office = { monitors = { "Dell Inc. DELL U2720Q 1ABC" }, layout = "single" },
  },
  layouts = {
    dual = {
      screens = 2,
      workspaces = {
        [3] = { [1] = "h[main:2, right:1]", [2] = "left" },   -- every slot, on one screen or the other
      },
    },
    single = {
      screens = 1,
      default = { [1] = "h[left, main, right]" },
    },
  },
}
```

A desk's `monitors` are each a monitor description, serial, or connector
name, tried in that order of precedence against each connected monitor; the
order they are listed in does not matter (screens are numbered by
position, §3). Its `layout` must be one for as many screens as it has
monitors. Its `geometry` (optional; absent is none, as in every slots.lua of
before) is the engine's record of how its monitors sat when it was last
active (§8): monitor selector -> `{ x = 0, y = 360, w = 1440, h = 900 }`,
each a logical box (the mode divided by the scale, width and height swapped
for a monitor turned 90 or 270 degrees, whole pixels), the desk's top-left at
0, 0; a box per monitor of the desk at most, `w` and `h` above 0, else a
config error (`desks.docked.geometry[DP-9]: 'DP-9' is none of the desk's
monitors`). The serializer writes each box on one line, after the desk's
`layout`. The editor never edits it. A layout's `screens` is its screen
count; `workspaces[n][i]` is workspace n's tree on screen i, and
`default[i]` screen i's tree for every workspace with no entry of its own
(an entry replaces the default trees whole, so `workspaces = { [5] = {} }`
leaves workspace 5 empty). Desk and layout names hold no `/`.

**Monitor names.** The editor shows each monitor by a short display name
(`monitor_name.lua`), never used to match: desks keep selecting monitors by
description, serial or connector. The automatic name is `Built-in` for a
laptop's own panel (connector `eDP*`, `LVDS*`, `DSI*`), else the model,
else the make, else the connector. `HL.Monitor` has no make or model
(§2), only the description `<make> <model> <serial>`, so the model is the
description less its serial and the longest PNP vendor name that starts it
(hwdata's `pnp.ids`, the table libdisplay-info names makes from; a short
built-in list where it cannot be read): "Samsung Electric Company Odyssey
G95NC HNTW700044" is `Odyssey G95NC`. A monitor a desk lists that is not
connected is named from its selector, less a last word that looks like a
serial (six or more capitals and digits, or hex): `Odyssey G95NC` again. The user's label comes first: slots.lua's `monitor_names`
(selector -> name, keyed by any selector a desk could use; absent = none),
set by the Desk tab's `m`. config.lua need not pass it on: where it
returns no `monitor_names`, the data file's are used.

`workspaces` (top level, optional, an integer 1 to 10, default 9: workspace
10, Super+0, stays Omarchy's unless it says 10) is how
many workspaces hyprslots manages: 1 to N. Specs and trees for a workspace
past it are config errors (`specs[10]: a workspace must be an integer from
1 to 9 (workspaces = 9)`); `bind_workspace_keys()` rebinds only Super+1..N
(with 9, the default, Super+0 stays Omarchy's own switch); the api refuses a workspace
past it (`workspace`, `assign`; the edits through config.lua's validation);
the workspace rules cover only 1 to N; `state` says `workspace_count`, and
the editor's workspace strips, digit keys (`0` is no key with fewer than
ten) and `[` / `]` wrapping follow it. It is config.lua's (a value there, or
`data.workspaces` passed through from slots.lua); the editor never changes
it.

A spec may only name a slot defined under `slots`; anything else is a
config error with its path (`specs[3].mian: no slot 'mian' (define it
under slots)`). **Every tree set holds every global slot**
(`migrate.normalize`, on load and on every edit, which re-runs config.lua
over the edited data): the global slots a tree set leaves out are
appended, by name, to its left-most screen that has a tree (new children
of a tiled tree's root split, a bare leaf becoming `h[leaf, slot]`; columns
at the end of a scroll branch, before its `*` when that is its last
column: `tree.append`), except one
that another tree set of the same layout places (any screen) while no
workspace using this set fills it (a spec for it on a workspace with no
trees of its own, for the shared set; on the workspace itself, for its
own): that slot is in the layout already, so data like `default = { [1]
= "h[main, right]", [2] = "side" }` beside workspace 3's own `[2] =
"v[side, chat]"` is valid as written, loads clean (no `● unsaved` on
opening) and keeps `chat` off the shared tree's screen 1, and a slot that is not global is dropped from the
tree. **No layout is treeless**: one with no default tree (none given,
`default = {}`, or every one dropped as above; a new layout the Desk tab's
`n` makes empty) gets the default trees a new desk's layout gets (§8):
every global slot on screen 1, `left`, `main` and `right` first, as a
full-width scroll branch (`scroll[...]`) when screen 1 is a laptop panel
(connector `eDP*`, `LVDS*`, `DSI*`), else side by side (`h[...]`). Screen 1
is the left-most monitor of the first desk using the layout whose monitors
are all connected, else the first monitor the first desk using it lists (a
laptop panel is selected by its connector), else, when no desk uses it and
as many monitors as it has screens are connected, the left-most of those;
nothing known, it is side by side. A workspace with no trees of its own
(`[5] = {}`) stays without any. So a new slot is in every tree at once, a removed one
in none, and the editor never places or takes out a slot: an empty slot
closes up (§6), so a workspace uses the slots it fills. The editor's edits
(`set_tree`) still refuse a slot that is not global. A table config.lua
builds in code is normalized each time it loads, without counting as a
shape of before. A slot placed on two screens of one workspace is an
error. A slot's `description` is the editor's note (aerolayout's logical
slot description); the engine does not use it.

**Slot keys.** Each global slot has a `key`, one lower-case letter a to z
(`slot_key.lua`), no two slots the same (a config error otherwise:
`slots.main.key: 'm' is slot 'mail''s key already`): the letter that picks
it in every slot-choice prompt of the editor (§9), so a slot is picked by
the same key from prompt to prompt, whatever other slots there are. Letters
only, never digits (the digits jump workspaces). A slot made in the editor
gets its name's first letter no other slot has, else the next unused
letter of its name, else the first unused letter a to z (`slot_key.pick`;
none once all 26 are taken: the arrows pick it); `set_slot_key` changes it.
A slot with no key (slots.lua from before there were keys, a table
config.lua builds in code) gets one on load (`migrate.normalize`,
`slot_key.fill`): in slot name order, around the keys other slots have, by
the same rule, so `left`, `main` and `right` are `l`, `m` and `r`; for a
data file that counts as a shape of before (`dirty` until saved). Any
letter is free to be one, the panel's own keys (`a`, `q`, `s`...)
included: a prompt owns every key while it is open (§9).

**Shapes of before** are still read (`migrate.lua`, pure), both in a data
file `load_data` hands config.lua and in the table config.lua returns; the
engine runs the result as an unsaved edit (`dirty`, the editor's Ctrl+S
writes the new shape):

- The per-workspace slots (`slots = { [3] = { main = "kitty/deltaf" } }`,
  `descriptions = { [3] = { main = "..." } }`): every slot name some
  workspace had becomes a global slot, each workspace's entries move under
  `specs` unchanged, and a slot's descriptions move onto it (every different
  one, in workspace order, joined with "; "; one for a slot no workspace has
  is dropped).
- The arrangements (`arrangements = { docked = { screens = { laptop =
  "eDP-1", wide = "..." }, desks = { [3] = { wide = "h[...]" } } } }`, and
  `pinned = { "laptop" }`, a list of screen roles): each arrangement becomes
  a desk of the same name (its selectors) and a layout of its trees, by
  screen number. The screens are put in order of the monitors' positions
  when every monitor of the arrangement is connected at load, else in the
  roles' sort order (the order slots.lua wrote them in). Arrangements whose
  layouts come out the same share one, named after the first. Pinned roles
  are dropped. The migration keeps the arrangement's
  name for its layout (it knows nothing better to call it, and a name it
  made up would hide where the trees came from), so a migrated
  `laptop` desk uses layout `laptop`: rename the layout for what it
  arranges in the editor's Desk tab (`r`; desks follow).
- Pinned screens (a desk's `pinned`): dropped without a word
  (`migrate.unpin`); a workspace switch shows the workspace on every screen.
- Trees that leave a global slot out, or name one that is not: filled and
  trimmed as above (`migrate.normalize`).
- Slots with no `key`: keyed as above (`migrate.normalize`).
- config.lua's `scroll = { width = w }` (one column width for every scroll
  branch): written into every scroll tree that says no width of its own
  (`scroll[a, b]` becomes `scroll:w[a, b]`, slots.lua's data included, so
  save keeps it: `migrate.scroll_width`); a full width (0.99, its default,
  or more) changes nothing. The key is still checked and used for nothing
  else; take it out of config.lua once saved, or a full-width tree written
  `scroll[...]` takes it again on the next load.

A `config.lua` written for an older shape passes `slots = data.slots` and
nothing more, or `arrangements = data.arrangements`, which would lose the
specs or the desks and layouts; it is refused at load with what to add
(`specs = data.specs`; `desks = data.desks, layouts = data.layouts`). An
`arrangements` beside desks and layouts is a config error.

## 5. Workspaces on top of Omarchy's per-monitor workspaces

Omarchy (`/usr/share/omarchy/default/hypr/monitor-workspaces.lua`) gives each
physical monitor its own block of ten workspaces: block 0 is 1–10, block 1 is
11–20, and so on, assigned per monitor identity and persisted in
`$XDG_STATE_HOME/omarchy/monitor-workspaces`. It exposes `o.workspaces`:

- `o.workspaces.workspace_id(monitor, slot)` — workspace id of slot N on that
  monitor.
- `o.workspaces.focus(slot, monitor_name)` — returns an action (a function for
  `hl.dispatch` / `hl.bind`) that focuses slot N on that monitor.
- `o.workspaces.reconcile(added, gone)` — puts every workspace on the monitor
  owning its block and every monitor on a workspace of its own; its handlers
  run it on `hyprland.start`, `config.reloaded`, `monitor.added` (inside the
  event) and `monitor.removed` (from a oneshot timer). A workspace whose
  monitor is gone joins the block of the one it landed on, appended after
  that monitor's own (13 becomes 4), and remembers where it came from.

Workspace N on a screen is exactly `o.workspaces.workspace_id(monitor, N)`.

**Blocks follow the desk** (module `blocks`). Omarchy's assignment is for
good: the monitor seen first keeps block 0 even while it is turned off. On
the laptop with hyprmoncfg's Odyssey profile, which disables the panel
(eDP-1), the Odyssey alone sat on 11–20 and the bar showed 11–19; worse, when
the panel was turned off while it was the only monitor on, Hyprland had no
monitor to move its workspaces to, so they stayed on the disabled panel, out
of sight. hyprslots therefore owns the assignment while a desk is active:
**screen i of the active desk holds block i-1**, so screen 1 always shows
1–10, screen 2 11–20; a monitor that is off or unplugged holds no block.

It drives Omarchy's module rather than replacing it:

- **The block table.** `monitor-workspaces.lua` keeps its blocks (identity →
  block) in a local table; `hl_adapter.set_omarchy_blocks` reaches it through
  the upvalues of `o.workspaces.workspace_id` (`assign`, and `assign`'s
  `blocks`, `identities_of`, `save`), rewrites it to the desk's screens and
  writes the state file with Omarchy's own `save`. So Omarchy's Super+N,
  move-workspace-to-monitor and reconcile, and the bar (which maps its
  connector to a block from the state file and watches it), all see the
  desk's blocks. Should a later Omarchy change that shape, the numbering
  stays Omarchy's and hyprslots logs why once.
- **Renumbering** (`blocks.plan`, pure). Every workspace holding windows goes
  into its screen's block under its own number: 13 becomes 3 on screen 1,
  a workspace whose number is taken there has its windows moved into the
  one that has it, and a workspace on a monitor that is no screen (turned
  off, unplugged) goes to the screen of its block (screen 1 when that block
  has none). Renumbering (`hl.dsp.workspace.change_id`) keeps the workspace,
  so what a screen shows stays in view; two screens trading blocks (a
  monitor moved in hyprmoncfg) pass through ids 100000+ so their windows do
  not mix. Slot assignments are by window address and are not touched; the
  re-route after a hotplug (§8) puts assigned windows in their slots.
- **When.** Ahead of every Omarchy reconcile (`blocks.attach` replaces
  `o.workspaces.reconcile` with a wrapper; Omarchy's handlers call it
  through the table), so Omarchy finds every workspace in its block already
  and only puts each screen on a workspace of its own; and in
  `Engine:reselect` once hyprslots has started (hotplug, a new desk, an
  edit), followed by Omarchy's reconcile when anything moved.
- **Off.** While hyprslots is refused, no desk is the connected monitors
  (until a new desk is made, §8), or Omarchy's internals are out of reach,
  Omarchy numbers as it always did, from the table as hyprslots last left it.

**Workspace switch** (the Super+N path). Public entry points:

- `hyprslots.workspace(n)` — returns an action, bound to `SUPER + N` in place
  of Omarchy's `o.workspaces.focus(n)` (`hyprslots.desk(n)` is a deprecated
  alias).
- `hyprslots.api.call("workspace", '{"workspace": n}')` — the same operation
  through the api (used by the editor and by the e2e tests).

Both run the same function: remember the focused monitor (the origin), run
`o.workspaces.focus(n, name)` for every screen of the active desk, then
refocus the origin monitor.

The screens go left to right with the origin last, so the origin's view
changes last. With no active desk only the origin switches, as Omarchy's
Super+N does.

`setup()` leaves Omarchy's Super+1..0 alone. `hyprslots.bind_workspace_keys()`
rebinds `SUPER + code:10..18` to `hyprslots.workspace(1..9)` by default, up
to `code:19` and workspace 10 (as many as config `workspaces` says, §4, read
when it is called) through
`o.rebind` (so the keybindings menu keeps a description, "Switch to workspace
N on every screen"); the user's shim calls it (`bind_desk_keys` is a
deprecated alias).

**hyprmoncfg.** hyprmoncfg keeps owning monitor modes and positions, but its
workspace planner must be Off. Its generated `hyprmoncfg-monitors.lua`, when
the planner is on, sets `o.workspaces.enabled = false` and replaces
`o.workspaces.focus` with global-number focus, which breaks the workspace
model.
hyprslots therefore refuses to start, with an `hl.notification`, while
`o.workspaces.enabled == false`. Because the hyprmoncfg file loads last in
`hyprland.lua` (after hyprslots), the check runs deferred on
`hyprland.start` / `config.reloaded`, not at require time. While refused,
`hyprslots.workspace(n)` (so Super+N) falls back to `o.workspaces.focus(n)`,
whatever that is then, so the keys never go dead; the api's `workspace` call
still reports the refusal. At the cutover the planner was set Off in every
hyprmoncfg profile (Odyssey, and a new Laptop profile for eDP-1 alone, so
the undocked laptop matches a saved profile instead of a planner-on live
layout).

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
tree      := node | scroll                              -- scroll: the whole tree only
node      := slot | '*' | split
split     := ('h' | 'v') '[' child (',' child)* ']'     -- side by side / stacked
scroll    := 'scroll' (':' width)? '[' column (',' column)* ']'  -- scrolling columns
width     := decimal                                    -- 0.1 to 1 of the screen; none or 1: full
column    := slot | '*'                                 -- no weight
child     := node (':' weight)?                         -- weight: integer >= 1, default 1
```

`h`, `v` and `scroll` open a container only when `[` follows (`scroll`
also when `:<width>[` follows: `h[scroll:2, b]` is a slot named scroll
with weight 2); otherwise they are plain slot names. The root takes no
weight. A scroll branch's width is the fraction of the screen each column
takes: `scroll:0.5[a, b]` half (two columns to a screen), none (or 1) full
width; anything outside 0.1 to 1 is refused with its position (`a scroll
width must be a fraction of the screen from 0.1 to 1, got '2'`). A slot appears at most once
per tree. A scroll branch is a screen's whole tree and holds slots and at
most one `*` (the column windows with no slot go to, §6): a split or weight
inside it, or a `scroll[` below the root, is rejected with its position,
under the branch's config path. `a[...]`, the accordion
this replaced, is rejected with the `scroll[...]` that says the same thing.
`*` is the **overflow leaf** (`h[main:2, v[right, *]]`): it takes a weight
like any leaf and appears at most once per tree. `serialize.tree` writes the
same syntax back (weights of 1 left out, a full width left out, a width
with four significant digits at most), which is what `save` and `state`
use.

### Placement

`recalculate(ctx)` is pure arithmetic: look up the active desk's layout and
the workspace's number and screen, take the tree in force for that branch
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
up the same way. A workspace the active desk's layout has no tree for, or
a workspace where no target has a slot, tiles its targets in equal
columns.

Workspace rules apply when a workspace is created, so `setup()` gives
`lua:slots` to workspace N in every block (N, 10+N, ... 90+N)
for each workspace some layout has a tree for (every workspace, when a
layout has default trees), rather than tracking which blocks are
connected.

Rejected alternative: driving dwindle with dispatched splits. Dwindle's
result depends on window open order and focus at the moment each split
happens, and the dispatches race with window mapping. Arithmetic placement
has neither problem.

### Scroll branches

A screen whose tree is `scroll[a, b, c]` gets its hyprslots workspace on
Hyprland's own `scrolling` layout instead of `lua:slots` (`scroll.lua`):
the user's full-width scrolling (Super+L's full-width stop, which the
user's laptop workspaces were on before the cutover), with hyprslots keeping
the columns in slot order, the windows with no slot in the branch where
the branch places the overflow leaf (`scroll[left, main, *, right]`: after
main, before right), else after the slotted columns, in the order they are
in either way, and the columns that arrive as wide as the branch says:
full width for `scroll[...]`, half the screen for `scroll:0.5[...]`. `scroll.plan` (pure)
takes the branch's columns (`tree.columns`: its slots, and `*` where it
stands) and closes up around empty ones, `*` included.
Everything a scroll branch needs is a deferred pass (20 ms timer), never
work inside an event:

- **Order**, after a window opens or moves to a workspace, a workspace is
  shown (a workspace switch included, even to the workspace already showing), a
  re-route (hotplug, edits, reload) and Hyprland's start or config reload:
  `scroll.plan` (pure) lists the swaps that put the columns in order and
  Hyprland's `window.swap { window, target }` makes them. A swap keeps the
  focus, but Hyprland warps the cursor to the swapped window, so the pass
  sets `cursor:no_warps` around the swaps and puts it back (Hyprland still
  focuses the monitor under that point, so the focused monitor is put back
  too).
- **Widen**, on the focused workspace only (Hyprland's `colresize` acts on
  the focused workspace's focused window): when a column the pass has not
  widened before is there and is not the branch's width (its own,
  `scroll:0.5[...]`; full width 0.99, the user's full-width stop, for
  `scroll[...]`), or the branch now says another width (an edit, `t` in the
  editor), `colresize all <width>`, then `fit_into_view` so the focused
  column stays in view. A hidden workspace's new columns widen when
  it is shown. A focus change runs the widen step alone, so a column the
  user moved (`swapcol`) or resized stays put until the next arrival or
  workspace switch. A window floated and tiled again by hand comes back in a new
  column at Hyprland's default width (the user's own full-width mode does
  the same); Super+L entering slots (api `arrange`) widens every column.

A workspace is **managed** only while its tiled layout is `scrolling` and
Omarchy has no saved mode for it (`$XDG_STATE_HOME/omarchy/workspace-layouts/<id>.lua`):
any Super+L stop saves one, and hyprslots then leaves the workspace's
columns alone until Super+L brings slots back, which removes it.

**Layout rules.** At load, workspace N in every block gets
`scrolling` where the desk's layout selected then has a scroll branch and
`lua:slots` everywhere else; Omarchy's saved modes load afterwards and
win. When the desk, its layout or a tree changes later (hotplug, an edit, the
start check), each hyprslots workspace whose layout should change gets the new
rule unless it has a saved mode, so Super+L's choice stands. `lua:slots`,
should it ever lay out a scroll branch, shows its columns side by side.

**Hyprland 0.56.2's scrolling layout** (`src/layout/algorithm/tiled/scrolling`,
verified in the nested harness): `scrolling.column_width` is one global
option and the scrolling workspace rule only takes `direction`, so full
width per workspace is `colresize` (the window rule `scrolling_width` sets a
window's width wherever it is inserted, on every workspace, so it cannot
make one workspace full width). A new window's column goes right after the
focused column when the focused window is on that workspace, else last; a
window moved in goes last. `HL.Window.layout` reports a scrolling window's
`column = { index (0-based), width, windows }` and `index_in_column`,
which is how the pass reads the order. `swapcol`, `move` and `colresize`
layout messages act on the focused window only; `window.swap` trades two
windows' places (their targets) on any workspace, focus kept.

Rejected alternative: the accordion as a Hyprland group (slice 4). A group
draws a tabbed groupbar and is not what aerolayout's accordion is on the
laptop; the cutover ported the laptop workspaces as accordions and every one
showed tabs.

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
children of the configured split; absent siblings keep their share. (A
scroll branch is on Hyprland's scrolling layout, whose own resize keeps
Omarchy's keys.)

Hyprland sends a layout message to the focused workspace's algorithm only,
so resize always acts on the focused window (`hl.dsp.layout("…")` from a
bind or `hyprctl dispatch`); Hyprland recalculates afterwards. A string
reply (why nothing changed) surfaces as the dispatch's error. A nudged
tree overrides the branch per layout, workspace and screen, in memory
(`engine.resized["<layout>/<workspace>/<screen>"]`): it survives hotplug
back to a desk using the same layout but not a config reload. `resize.effective_branch`
is the one lookup for the tree in force; the layout and the api (§9) both
use it. The api's `save` writes overrides to `slots.lua` and clears them,
its `reload` drops them, and `set_tree` / `set_ratio` / `record` replace
the one they edit. A nudge or reset emits the editor's change event; a `resize` that moves
both edges emits it once.

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

- The cycle acts on the focused workspace only. On a hyprslots
  workspace (one in `hyprslots.api.call("state").workspaces`) it gains a
  slots stop between floating and tiling:
  slots → tiling → side-by-side → full-width → floating → slots
  (`back` reverses). Elsewhere it is unchanged. The slots stop is the layout
  hyprslots gives the workspace (`state.workspaces[id].layout`): `lua:slots`, or
  `scrolling` for a scroll branch, whose columns hyprslots keeps full width
  and in slot order (§6); its full-width stop is the user's own, which
  hyprslots leaves alone.
- Omarchy's mode files know nothing of slots, so "slots" is read from the
  workspace's `tiledLayout` unless the mode file says floating (floating
  keeps the tiled layout underneath): `lua:slots`, or, on a scroll workspace,
  `scrolling` with no mode file of its own.
- Entering slots from floating first applies `dwindle` through
  `o.workspace_mode` to tile the windows again, then sets the workspace's layout
  as a workspace rule, removes the workspace's mode file (and its
  full-width mark), so the rule hyprslots sets at load brings slots back
  after a reload, and on a scroll workspace calls api `arrange`, which orders
  and widens its columns at once. Leaving slots applies the mode and saves
  it, even Omarchy's default, so the workspace stays out of slots across reloads
  until Super+L enters slots again.
- The bar widget shows a grid glyph (nf-md-view_grid) and "Slots"
  (`workspace-layout-current` says `slots` for both kinds).
- Every step refreshes Omarchy's dock as well as its workspaces widget
  (`omarchy-shell -q omarchy.dock refresh` in `refresh_bar()`): the dock
  caches each workspace's floating mode and otherwise stayed up after
  leaving floating.

Verified at cutover: a saved mode file for a hyprslots workspace wins over
hyprslots' load-time rule. Omarchy loads the saved modes from
`default.hypr.toggles`, and each calls `hl.workspace_rule` with its layout.
hyprslots' loader (§10) is a file in that same folder, sorted after them
(`zz-hyprslots.lua` after `default.lua` and `<N>.lua`), so hyprslots itself
leaves a workspace with a saved tiled mode alone at load
(`hl_adapter.omarchy_saved_mode`); one saved as floating still gets the
slots rule, the tiled layout under the floating, as when the mode files
loaded last. So leaving slots for a mode
keeps that mode across reloads until Super+L enters slots again (which
removes the file), and Omarchy's default-layout command, which saves busy
workspaces' current mode, takes those workspaces out of slots too. The cutover
removed the saved modes of the hyprslots workspaces (1, 3, 4, 5, 6, 9) and their
full-width marks. A config reload re-applies the rule to existing
workspaces. The scroll fix (§11) put the laptop workspaces (1 to 9) back in
slots the same way, now on the scrolling layout, so Super+L's full-width
stop and hyprslots' slots stop look alike there: slots also orders.

## 7. Routing

- `window.open` and `window.title` events: match the window against the specs
  of the workspaces, assign it to a slot (assignment is sticky), and
  move it to the slot's workspace when it opened elsewhere. Moves happen in
  the event callback, never in `recalculate`. `window.close` frees the slot:
  Hyprland 0.56.2 passes `window.destroy` a window whose address is already
  gone.
- **Sticky.** An assignment is kept until the window closes. When the engine
  re-solves every assignment (config reload, an api edit, hotplug), a
  window keeps its slot while the slot exists and its spec still admits the
  window's class, whatever its title says now. An assignment made by hand
  (the editor's `assign`, §9) is kept while the slot exists.
- **Overflow.** A window that matches a spec while every slot it matches is
  taken goes to the hyprslots workspace of the first of those slots (precedence
  below), where the layout stacks it in that branch's overflow leaf (§6).
  It follows that workspace on hotplug and edits, and the oldest such window
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
  trying the workspaces that have specs in ascending order and, within a
  workspace,
  slots by name. So when
  two workspaces list the same spec, the lower workspace wins until its slot is taken,
  then the next one (aerolayout: "first workspace in config order").
- Hyprland creates a workspace that does not exist yet on the **focused**
  monitor, and cannot create one elsewhere without showing it. So the router
  moves the window first and then, when the target workspace is on another
  monitor than its screen's, moves the (hidden) workspace there with
  `hl.dsp.workspace.move`. Neither screen's view nor focus changes.

### 7a. Spec grammar and title matching

| Form | Matches |
|---|---|
| `App` | class (Wayland app-id) equal to `App` |
| `App/pat` | class `App` and `pat` in the window's extracted title: a case-insensitive **plain substring**; everything after the first `/` is `pat` |
| `[Tag]` | a window of a `browser_apps` class whose title contains `[Tag]`, in any case (`[keep]` is `[Keep]`'s window) |
| `[Tag]/Profile` | ... and `(Profile)` after it, in any case: Chromium's profile title `[Tag] - Page - Person (Profile)` |

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
every such slot is taken, of the first of them (the workspace whose overflow
leaf the router sends an extra window to). The rule is **disabled** when
that candidate is a title or tag spec (only the title can decide, so the
router does) or when its slot is on no screen of the active desk.

Hyprland cannot remove a window rule at runtime; registering one under an
existing `name` replaces it, and `{ name = ..., enabled = false }` turns it
off (Omarchy's workspace-modes does the same). So rules are re-registered,
only when their target changed, after every desk selection, every
slot taken and every slot freed, and after every api edit or reload (which
can move a slot to another screen). A Hyprland config reload starts from
scratch on both sides.

The rule is only an optimisation. The router does the same placement with or
without it; when a rule opened the window on its workspace already, the
router still moves that workspace to its screen when Hyprland created it on
the focused one.

## 8. Desk selection and hotplug

Each desk lists its `monitors`, each a description, serial or connector
(`desk.lua`). On load and on `monitor.added` / `monitor.removed`, hyprslots
picks the desk whose monitors are exactly the connected ones (every selector
matched by a distinct monitor, no monitor left over; Hyprland's `FALLBACK`
placeholder output does not count; ties go to the first name), and with it
the layout it uses. Screen N is the N-th connected monitor from the left
(x, then y, then connector name), so the same layout drives any desk of as
many monitors, and a monitor moved in hyprmoncfg changes which screen it
is. A monitor turned off in the config (hyprmoncfg's profiles disable the
laptop panel) is not connected: `hl.get_monitors()` leaves it out, and
Hyprland reports turning it off and on as `monitor.removed` and
`monitor.added`, as for an unplug (checked on 0.56.2, both through a config
reload and through `hl.monitor` at runtime). Each screen holds the block of
its number (§5). The recomputation is deferred with a oneshot timer, as Omarchy does for
`monitor.removed`, because Hyprland reports removal from inside the
monitor's teardown. Afterwards each workspace's windows are re-placed under
the new trees.

Order (module `hotplug`): the event itself does nothing; a oneshot hop
re-selects the desk, and a second hop, created inside the first,
re-routes every assigned window (assignments are kept by window address) to
its slot's workspace under the new layout, the same way the router
places a new window. Omarchy reconciles on `monitor.added` inside the event
and on `monitor.removed` from a oneshot timer created in the same event, and
hyprslots' wrapper first gives the screens of the desk for what is connected
their blocks and renumbers the workspaces into them (§5: an unplugged
screen's 13 joins screen 1's 3). The first hop syncs the blocks again before
it re-selects (nothing to do when Omarchy's timer came first), and the
second hop is created after that timer has come due, so it always sees the
workspaces renumbered. When the
re-route is done it asks for the scroll pass (§6), so scroll columns are
put in order on the workspaces the windows now sit on, and every workspace
of the desk is laid out again (a window merged into a workspace before the
desk changed was placed under the old desk's trees): a zero resize of one
of its windows, which lua:slots takes as a relayout. Never on a workspace on
Hyprland's scrolling layout, where that resize collapses the window's column
to 1 px and the scroll pass, having seen the column, would leave it so; the
scroll pass arranges those (an edit's relayout skips them the same way). Keyboard-resized
trees are kept per layout, so returning to a desk using that layout brings
its nudges back. Hotplug never changes a connected screen's view, with one
exception: a **screen that is plugged (back) in shows the active
workspace**, the one last switched to with
`hyprslots.workspace(n)` / `api.call("workspace")`, after the re-route, and
focus returns to the screen that had it. Before the first workspace switch a
new screen keeps whatever Omarchy shows on it.

**Desk geometry.** While a desk is active the engine records its monitors'
logical boxes (`desk.geometry`, §4) in slots.lua under the desk, so the
editor can draw any desk's arrangement later, when it is not connected
(§9's Desk tab). It does so (`api.record_geometry`, a oneshot hop after
`reselect`, which runs inside edits and saves) on load, after every desk
change (hotplug, an edit) and on `monitor.layout_changed` (a mode, scale or
position change), whenever the boxes differ from those recorded. Recording is
no edit: it never makes the engine dirty. It is saved at once and quietly
(`api.save`) while nothing else is unsaved, the same rule as a first run's
new desk (no other edit, no slots.lua of before, no keyboard-resized tree);
with edits pending, or slots.lua on disk no longer what runs (changed by
hand, a `reload` that failed), it waits in the running data and goes with
the next Ctrl+S, never saved over them. `reset` compares the data with the file
without it, so a reset back to the file is clean, and then saves the
geometry quietly. A desk config.lua builds in code, or one not in slots.lua,
records nothing. `HL.Monitor` gives `x`, `y` (logical), `width`, `height`
(the mode's pixels), `scale` and `transform`, as `hyprctl monitors -j` does.

**A new desk.** Monitors no desk knows get a desk of their own once the set
has held for a second (hotplug passes through sets on its way: undocking
goes from laptop + monitor through the monitor alone, or the other way, as
hyprmoncfg applies a profile). Until then no desk is active and windows stay
where they are. The desk (`Engine:new_desk`):

- is named after its monitors' display names (§4) left to right,
  lowercased with `-` between words, joined with `+`: `built-in` for a
  laptop panel, `odyssey-g95nc` for "Samsung Electric Company Odyssey G95NC
  HNTW700044" (`samsung` once labelled so), `headless-2` for a bare
  connector: `built-in+odyssey-g95nc`; `-2`, `-3`... when the name is
  taken;
- selects each monitor by its description, else its serial, else its
  connector;
- uses the most recently used layout for as many screens (the layouts the
  engine ran since it loaded, most recent first; after a Hyprland reload the
  first such layout by name), else a new layout named for what it arranges,
  not after the desk (`scroll` for one screen scrolling, else `<N>-screen`,
  `-2`, `-3`... when taken: a desks table reading `laptop → laptop` says
  nothing), for that many screens, with default trees: screen 1 shows `left`, `main` and
  `right` (those that are slots; else every slot, by name) side by side
  (`h[left, main, right]`), as a scroll branch (`scroll[left, main,
  right]`, full width) when screen 1 is a laptop panel, then every other
  slot after them (every tree holds every slot, §4); the other screens show
  nothing.
  The editor's Desk view then applies another layout, forks one
  to customize, or renames the desk.

It is an edit like the editor's (`api.new_desk`: `edit.add_layout`,
`edit.add_desk`, config.lua re-run), in memory until saved: `dirty`, the
bar's unsaved dot, `state.desks[name].auto` until `save`. A reload without
saving forgets it, and the monitors get one again. While there are no slots
(a first run) the engine saves it at once (`api.save`, the atomic write of
`save`), so nothing reads as unsaved on first contact: the desk and its
treeless layout are all there is to review. It does so only when nothing
else is unsaved (no other edit, no slots.lua of before, no keyboard-resized
tree): with edits pending the new desk waits for Ctrl+S with them, never
saved over them. With slots it waits for Ctrl+S as any edit does: a guessed
layout for a setup that may be a one-off (a projector) is the user's to
keep or drop, and saving it unasked would add a desk to slots.lua for every
display ever plugged in. Where config.lua builds
the desks or layouts in code (or loads no slots.lua) it is added to the
running config only, for this Lua state. Deleting the active desk in the
editor makes its monitors unknown again, so a second later they get a new
desk, on the layout they ran.

A new desk says so in an info notification, in plain words: `hyprslots: new
monitor setup — using layout 'scroll'. Open the editor to change it.` (the
second sentence left out where config.lua builds the desks, so the editor
cannot). While there are no slots (a first run) it says nothing: there is
nothing laid out to change yet.

## 9. Editor

An Omarchy shell plugin, `io.github.milanmitrovic.hyprslots` (QML), with full aerolayout TUI
parity (Assignment, Layout and Desk views, the logical slots
made in the Layout view's slot list, every one in every tree; record). It talks to
the running engine only through Hyprland:

- read: `hyprctl repl 'return hyprslots.api.state()'` (JSON string),
- write: `hyprctl repl 'return hyprslots.api.call(name, json)'`,
- push: the engine emits `hl.dsp.event("hyprslots changed <seq>")`, which the
  shell sees as a `custom>>` event on socket2 and answers with a fresh
  `state()` read.

### The plugin

The repo is the plugin folder: `manifest.json` at its root (`kinds:
["panel", "service", "bar-widget"]`), its entry points in `editor/`:

| File | Role |
|---|---|
| `Engine.qml` | the service: runs the api through `hyprctl repl` (one `Process` per command, in order, 3 s watchdog), reads `state` debounced (60 ms) on `custom>>hyprslots changed` and on window events (`openwindow`, `closewindow`, `movewindowv2`, `windowtitlev2`, monitor events, `configreloaded`) via `Quickshell.Hyprland`'s `rawEvent`, only while someone follows it (`active`: the panel is open; `watchers`: bar widgets, from `watch()` / `unwatch()`); keeps `error` (last state read) and `lastError` (last call); `busy` while a call runs or the re-read after it is pending |
| `Panel.qml` | the panel: an `OverlayWindow` card (`qs.Ui`), themed through `qs.Commons` (`Color.menu.*`, `Color.muted`, `Style`) like Omarchy's own panels; folder tabs Assignment, Layout, Desk (Tab / Shift+Tab) over the page, the active desk and layout beside them, the message band (`MessageBand.qml`, `Messages.js`) at the page's foot and the help row under it; Ctrl+S saves, Esc or q closes (Esc in the Layout tab's slot list goes back to its picture); `press(key)` feeds a key by name (`Ctrl+s` with the modifier) |
| `BarWidget.qml` | the bar widget (below): glyph and active layout; left click toggles the panel, right click a menu |
| `Services.js` | where the service registers itself, for a bar widget whose bar hands it no `serviceFor` |
| `AssignmentView.qml`, `LayoutView.qml`, `DesksLayoutsView.qml` | aerolayout's Assignment, Layout (with its logical slots as a list beside the screens) and monitors views (below) |
| `ui/` (`qmldir`) | the editor's design system, one component per kind of element, all from the theme (below): `Tokens` (a singleton: colours, spacing, the Layout picture's divider band and line, the ratio label by the pointer, drag and drop's outline and fill, the mini-map's box), `SectionHeader`, `WorkspaceSwitcher`, `InfoText`, `ProblemText`, `Placeholder`, `TableHeader`, `TableRow` (`dropTarget`: outlined where a drag would land), `TableCell`, `PaneTitle`, `KeyCap`, `ActionButton`, `Toolbar`, `MiniMap` (a slot's place on its screen), `DeskMap` (a desk's monitors, the Desk tab), `DragGhost` (what a drag carries, and the label of what letting go does) |
| `Protocol.js`, `Assignment.js`, `Layout.js`, `Slots.js`, `DesksLayouts.js`, `Prompts.js`, `Workspaces.js`, `BarStatus.js`, `Help.js`, `Messages.js`, `Guide.js` | pure logic, tested under node (`editor/tests/`); `Slots.js` is the slot list's, `Workspaces.js` the workspace keys', `DesksLayouts.js` the Desk view's and the panel header's, `Help.js` the help rows', `Messages.js` the message band's, `Guide.js` the opening tab's and every empty state's (below) |

**Opening tab.** The panel opens on the Layout tab while there are no
global slots (that is where they are made), else on the Assignment tab
(`Guide.openingTab`); a tab the open payload asks for wins (the bar's
Record: `{"record": true}`, the Layout tab; `{"tab": "Desk"}` by name). The
choice is made again on the first state read after opening (the state the
panel had may be older, or none), unless a tab was picked meanwhile.

**First run and empty states** (`Guide.js`, drawn with the shared
`Placeholder`, `InfoText` and `ActionButton`). Every empty state points to
the next step, in plain words (no "spec", "overflow" or "tree"):

- **Layout tab, zero slots**: in the picture's place, `Start with your
  slots`, then `Slots are named places on your screens, like left, main and
  right. Each app you assign goes into its slot.` and `You choose the names,
  and how many. Arrange them here, then put windows into them in the
  Assignment tab.`, and one button, `[a] Create your first slot` (the
  picture's `a` while it shows; the help row is `create your first slot ·
  slots · Tab view q close`): the slot list's create prompt (a name,
  `Name your first slot (main, left, notes…)`, then an optional
  description; the key is picked from the name, §4), `Made slot 'main': it
  shows in the picture. Ctrl+S saves.` No starter set of slots is offered.
  Not shown where no slot can be made (the slots are config.lua's, a config
  error, hyprslots off): the problem line says why.
- **Layout tab, slots but nothing assigned anywhere** (no workspace has a
  spec): a line under the header, `Add more slots (s, then a), or go to
  Assignment (Tab) to put windows into them.`
- **Assignment tab, zero slots**: `Define slots in the Layout tab first:
  they are the places your windows go into.` and a button, `[Tab] Go to
  Layout`, in place of the table.
- **A workspace with nothing assigned** (no window in a slot, none waited
  for, none overflowing): a line over its table, `Select a window and press
  a (or click assign) to put it into a slot.`, or, with no window there,
  `Open an app on workspace N, then select it here and press a (or click
  assign).`
- **Desk tab**: never empty (the engine makes a desk for the monitors,
  saved already, so neither it nor the header says unsaved);
  its opening line: `A desk is a monitor setup; its layout is how your
  slots are arranged on its screens. The other tabs edit the active desk's
  (●).`
- **Bar widget, zero slots**: `󰕰 set up` with a small accent dot at the
  glyph's top right, the tooltip `Hyprslots: no slots yet` / `Click to set
  up your slots`; gone once a slot exists.

**Every view.** The panel's keys come first: Tab / Shift+Tab cycle the
tabs (Assignment, Layout, Desk), **Ctrl+S saves** (api
`save`, in every tab; the Layout tab applies its edited panes first), Esc
or q closes. The tabs are folder tabs with no outline: the current one is
the page's own surface flowing into it; the others are a dimmer surface on
the card's recessed one. Their top corners, the card's, the page's and
the message band's are the theme's radius (`Style.cornerRadius`, which
follows Hyprland's `decoration:rounding`): square when it is 0. Beside them, in
every tab and quietly (muted, small), what the edits go to: `Desk:
home (Built-in + Odyssey G95NC) · Layout: ultrawide (also used by: office)`
(the desk's monitors by display name, in screen order as the Desk tab lists them; `Desk: none` with no
active desk, `; new, unsaved` in the brackets after a desk the engine made for new
monitors), then `● unsaved (Ctrl+S)` in the urgent colour while
there are any. Every edit outside the Desk view goes to the
active desk's layout, and so to every desk that shares it. Edits go
to the engine as they are made and stay in memory until saved.

**By mouse, the same handlers.** The keyboard works as it always has, and
everything it does the mouse does too, through the very same handler: a
click feeds the panel the key (`Panel.press`), so there is one code path.
The help row is a toolbar (below) whose every button is its key; a
prompt's chips, Yes / No and OK / Cancel are its keys (Prompts below); a
double-click on a row is its view's primary action's key, after the click
selected it (Assignment: `a`, assign; Desk: `a`, on a desk row pick a
layout for it, on a layout row apply it to the active desk; the slot list:
Return, show the slot in the picture); the folder tabs, the workspace
switcher's entries, a row (select), a tile or filmstrip column of the
Layout picture (select it, the keys back to the picture) and a slot of the
slot list (select it, the keys to the list) are clicked as they are. Hover
and press looks come from the theme's control tokens. One thing the mouse
does that no key press spells: dragging a divider of the Layout picture to
a new ratio (below), an edit of the same draft `r` writes. And three the
keys spell differently: dragging an Assignment row's window onto a slot
(`a` with that slot) or onto the other windows (`u`), dragging a
Layout pane by its title onto another pane (`p`, swapping the two
screens' trees), and dragging a Layout tile or filmstrip column onto
another tile, between two columns or onto another screen (hjkl/HJKL's
moves, a drop anywhere rather than a step at a time), below.

**One look per kind of element** (`editor/ui/`, theme tokens only):
section headers are the accent colour in small letter-spaced capitals
(`SectionHeader`: the Desk tab's `DESKS` and `LAYOUTS`, and the workspace
switcher's `WORKSPACE`), a hint after them as information. The Assignment
and Layout tabs open with the same `WorkspaceSwitcher`: the workspaces by
their keys, the current one in the accent colour, bold and underlined
(`Workspaces.numbers` on the Assignment tab; the Layout tab's
`Workspaces.strip` leads with All workspaces and dots its overrides).
Information is muted and small (`InfoText`): the desk line beside the tabs,
the Desk tab's opening line, a section's hint, the Layout tab's notes on
its header line; a warning that something is not in force yet the same in
the urgent colour (`● unsaved`, `edited, not applied`). Tables share column
titles (`TableHeader`, muted and small), cells (`TableCell`) and rows
(`TableRow`): the selection is the strongest thing on a page, the accent's
selected fill with an accent stripe down its left, in the Assignment and
Desk tables and the slot list alike (the slot list's current row while the
keys are in the picture: an outline). Pane titles (`PaneTitle`: the Layout
tab's screens and its slot list) are the accent colour on the pane that has
the keys. What stands in an empty list or picture is a muted `Placeholder`;
why a tab cannot work, an urgent `ProblemText`. Headers, notes and cells
start at one inset (`Tokens.textInset`). What a drag would land on is
outlined in the accent with a faint accent fill (`TableRow.dropTarget`,
`MiniMap.targeted`), what it carries a `DragGhost` on the menu surface,
and what letting go does a label on the tooltip surface, as the ratio
label by the pointer; a slot's place on its screen is a `MiniMap`, the
slot an accent fill among dim outlines.

**Message band** (`MessageBand.qml`, `Messages.js`): the outcome of every
call shows in a band of its own at the foot of the page, just above the
page's bottom edge (the divider over the help row): an info message on an
accent tint with an accent stripe, a failure (`{ok:false,error}`, hyprctl
failing, hyprslots not loaded, the engine off, a config error) on an urgent
tint with an urgent stripe. Info fades after 4 s; an error stays until the
next key. A prompt takes the same band as an input: its question in the
accent colour, what is typed or offered after it, an accent outline, and a
refusal after it (under it when the line is full) in the urgent colour; it
stays while it is open. The
band's one-line height is always kept, so nothing moves when a message
comes or goes; a longer text grows it upwards over the view.

**Help rows** (`Help.js`, one helper for every view and the slot list):
each action shows its trigger key highlighted in the theme's accent colour,
bold, inside its label where the label has that letter (**a**dd,
**f**ork, **u**nassign, **R**ecord), else before it (**x** delete); keys of
more than one character go before their label (**Ctrl+S** save, **[ ]**
prev/next, **Tab** switch view), as does the key of an item marked so
(**o** show/hide other windows). Labels are escaped (Qt StyledText). The
help row sits under the page, on the card's recessed surface, as a
**toolbar** (`ui/Toolbar.qml`, `Help.buttons`): every action a button
(`ActionButton`) showing that same label, its key highlighted; an action
of several keys (`↑/↓`, `hjkl/HJKL`, `[ ]`) a small button per key, then
its label (`Help.presses` names each key as `Panel.press` takes it);
digits and ranges (`1–9`) are shown, not clicked: the workspace switcher
over the view is their mouse. A click on a button feeds its key. An action
the view would refuse now is dim and inert (`enabled: false` in the row's
model: Assignment's `a` off a window and `u` with nothing to unassign;
the picture's edits when read only or with no tree, `w` with nothing
edited, `R` on All workspaces; the slot list's edits when the slots are
code's or there is none to act on; a read-only desk's `a`, `r`, `x`, a
read-only layout's `r`, `x`). It stays one line at the panel's width. While
a prompt is open the row is the prompt's own help, plain.

**Prompts** (`Prompts.js`, one implementation for every view): a line of
text typed in place (←/→ Home End move, Backspace Delete, Ctrl+U clears,
↑/↓ step through suggestions, Return answers), a pick among keyed options
(↑/↓ and Return too), or y/n. A pick among slots (the Assignment view's
`a`) keys each slot by its own stored key (§4), the same in every prompt
and on every workspace's page, shown where the name has it (`(m)ain`,
`m(a)il`, else `(z) right`); a slot with none is picked with the arrows. A
pick among anything else (layouts, desks, monitors) keys each option by its
first letter, else the first free digit, computed per prompt; the help
under a choice says `letter pick`, `letter/digit pick` only where an
option is keyed by a digit. The message
band draws a prompt's controls after its question (`Prompts.controls`): a
choice's options as chips, each with its key cap (the one the arrows are on
selected, except in an inline choice, which takes keys only) and a Cancel;
y/n's Yes and No; a text prompt's OK and Cancel. Each is keys: a chip its
option's key, else the arrows to it and Return (`Prompts.pickPresses`), Yes
`y`, No `n`, OK Return, Cancel Esc, so clicking does exactly what typing
does. While
one is open every key is its own (Tab, q, Esc and Ctrl+S included); Esc
cancels. When an answer is refused (by the engine: the spec grammar,
config.lua's validation, a field config.lua owns; or, for a Layout ratio,
by the ratio grammar) the prompt opens again with the answer kept and the
refusal under it.

**Assignment view** (aerolayout `views.py` AssignmentView). Pages: the
managed workspaces 1 to N (`workspace_count`), one each, and no
every-window page; it opens on the focused workspace's (workspace 1's when
the focused one is not managed). A workspace's table lists
every global slot, always, in the order the active layout's trees for it
place them (every tree holds every slot, §4), screen by screen of the
active desk (by name when the layout has no tree for it). Each is the window in
it, a red `Missing — waiting for it to open` row naming the window it waits
for when one is assigned to the slot on the workspace but none is open, or an empty row (`—` for app
and title alike) when nothing says what fills it; then the
windows overflowing on the workspace and any other windows on it. So a
workspace whose tree is `scroll[main, right]` with a spec for main only
lists main Missing, then right empty. Columns: a mini-map (below; on slot
rows only), Screen (`N <connector>`, when more than one), Slot
(`main`, `main (by hand)`, `other (main taken)` (a window for main while main is taken, waiting with the other windows), `unassigned`, `—`), App (a
Missing row's awaited window, `—` for an empty slot), Title (`Missing —
waiting for it to open`, `—` for an
empty slot). This is where each workspace's specs are set: there is no
workspace × slot table.

| Key | Does |
|---|---|
| ↑/↓, k/j | select |
| ←/→, h/l (p), [ / ] | previous / next workspace's page (1 to N, round) |
| 1–9, 0 | workspace 1–9, 10's page (0 only when ten are managed) |
| a | `Assign kitty to a slot on workspace 3: (m)ain, (r)ight, m(o)re? [Esc] cancel`: every global slot, the workspace's own first, each by its key (§4); then `take_spec`: the window takes the slot and its spec (`spec.from_window`) becomes the workspace's for it, replacing the one it had, and the message says so (`Assigned kitty to main on workspace 3 (instead of foot)`); the slot is in the trees already, so nothing is placed. A window moving out of another slot leaves it empty, not Missing it: that slot's spec goes in the same edit when it is the window's (`; right is empty now`) |
| u | on a window in a slot: `Unassign kitty from main on workspace 3? The slot is left empty. (y/n)`, then `unassign` with `clear_spec`: the window leaves the slot and the workspace no longer says what fills it, so the row is empty, not Missing that window; on an overflowing window, or one in a slot the workspace has no spec for, `unassign` alone; on a red Missing row (a window assigned but not open): `Unassign kitty/deltaf from main on workspace 3? It is not open; the slot is left empty. (y/n)`, then `clear_spec`. The editor's words are assign and unassign; "spec" is the api's |

As aerolayout's `a` did, `a` writes the window's spec into the slot, and
`u` takes it out again (in memory until Ctrl+S, the header saying "unsaved
edits"), for a window that is open or one that is only Missing, on the
page's workspace. aerolayout's `n` (name a workspace) has no counterpart:
workspaces have no names.

**Mini-maps** (`ui/MiniMap.qml`, `Layout.miniMap`, `Layout.miniMapSize`,
`Assignment.miniMapSource`). Every slot row leads with a thumbnail of
where the slot is: the workspace's tree in force on the slot's screen (the
screen of the active layout whose tree for the workspace places it, its
own or the shared ones as state reports them; on a desk of several
screens only that one), at the screen's shape fitted into a fixed box
(`Tokens.miniMapWidth` × `miniMapHeight`, 56 × 32 at scale 1; an
ultrawide flatter, 4:3 narrower), in a column of its own. A tiled tree's
geometry is the Layout picture's, not a copy: its leaves are
`Layout.rects` at thumbnail size (no padding or titles). A scroll tree is
its whole strip across the box, each column its width of a screen and the
box's height (its columns are the screen's height anyway, so the strip
gets all of it), the screen outlined where Hyprland scrolls to show the
slot's column (the least, as `Layout.filmstrip` scrolls), the columns off
it fainter: so `scroll[left, main, aside, side]` shows four columns, the
slot's lit, and which of them the screen shows. The place for
other windows is left out, as the picture does without `o`. The slot is an
accent fill, the others dim outlines, on a faint screen. The other
windows' rows have no mini-map (the column is empty), nor does a slot no
tree places. While a drag would land on a slot row, that row's mini-map is
outlined in the accent as well. The rows are tall enough for it
(`Tokens.miniMapRowHeight`).

**Drag and drop** (`Assignment.canDrag`, `dragBegins`, `dropAction`; one
MouseArea over the table, `rowMouse`, so a drag outlives the rows a state
read makes anew). Any row with a window drags: one in a slot, one
overflowing, a stray. A press that moves `Assignment.DRAG_THRESHOLD` (6) px
starts the drag; under that it is a click (select) or a double-click (`a`),
as before. Let go:

- on a **slot row** of the page (its window, a Missing or an empty one):
  exactly `a` with that slot (the same handler, `take_spec`): the window
  takes the slot and its spec becomes the workspace's; the slot's window,
  if any, gives it up as with `a`, and the slot the dragged window left is
  empty, its spec cleared, as with `a`. On the slot the window is already in:
  nothing;
- on the **other windows** (overflowing and unslotted rows) or the list's
  empty space below its rows: `u` on the window (`unassign` with
  `clear_spec`, as `Assignment.unassignPlan` plans it), without u's
  question (letting go there is the answer), only for a window in a slot;
  one overflowing or in no slot is among the other windows already:
  nothing;
- **anywhere else** (outside the list), or **Esc** while the button is
  held: nothing; the panel stays open (a held drag has the keyboard: Esc
  lets it go, other keys wait).

While held: the row dragged is dimmed (`Tokens.dim`), a ghost of it
follows the pointer (`ui/DragGhost.qml`: its app, bold, and title on the
menu surface), and over a target the target is outlined in the accent
with a faint accent fill (`Tokens.dropOutline`, `dropFill`: the slot row,
or the other windows' section down to the list's foot) and a label under
the ghost, on the tooltip surface as the Layout picture's ratio label,
says what letting go does: `Assign to main`, `Unassign`. Where letting go
does nothing nothing is outlined and no label shows. The cursor is an open
hand over a row that drags, a closed hand while dragging; held near the
list's top or bottom edge the drag scrolls it. A drop is an edit like
`a`'s or `u`'s, in memory until Ctrl+S (the header's `● unsaved`), with
their messages in the message band; the dropped window's row is selected.

**Layout view** (aerolayout `views.py` LayoutView, `tree_visualizer.py`).
One workspace of the active desk's layout at a time; it opens on the
focused workspace and screen, and follows the active layout when it
changes (another desk, a fork, an apply, a rename; unapplied drafts are
dropped, and the message says so). When other desks use the layout too, a
quiet line under the header says so: `Shared with desk beamer: edits here
change it there too — fork it in the Desk tab.` (forking is the Desk
tab's alone). A pane per screen, side by side, titled `Screen 1
· Built-in`, the display name (§4) of the active desk's monitor at that position
(elided first, so the pane's `edited` or `keyboard-resized` after it always
shows), each a scale model of its monitor (`Layout.paneLayout`,
`Layout.screenSize`, node-tested): its size from the active desk's geometry
in state (§8), else the connected monitor's, else 1920 x 1080, and one scale
for every pane, so a 2560-wide screen is drawn larger than a 1920 one; the
largest that fits the picture's width and the page's height under the titles,
every pane top-aligned (the row centred across what is left; a desk much
wider than the picture leaves height unused, as its shape must). Leaves are boxes
proportional to their weights (tree.lua's integer arithmetic) with the slot
name, `×n` for a share other than 1, and the title of the window in the
slot; a nested split is a box titled with its kind and ratio (`h 1:3`). A
scroll branch is a **filmstrip** (`Layout.filmstrip`, node-tested): no tile
boxes, but its columns in slot order on a horizontal strip, each as wide as
the branch says (half or the whole screen), a viewport frame the size of
the screen at the panes' scale, at the top of its pane as a tiled screen is,
scrolled to show the selected column, and the columns beyond it faded,
labelled in the part that shows; a quiet `scroll · half` / `scroll · full`
under the frame. The pane is wider than its screen, the screen in its middle:
up to three screens' widths, so the columns either side show, taking the
width the screens leave, the screens shrinking for it to no less than 0.7 of
the scale they would have without. The picture
is the whole story: no tree text, ratio string or order line under it (a
tiled tree's ratios are the `×n` shares and the split titles; a scroll
branch has none).
**Dividers: ratios by mouse** (`Layout.dividers`, `Layout.dragDivider`,
node-tested). Every boundary between two children of a tiled split, at
any depth, is a divider: a band of at least 8 px along it
(`Tokens.dividerHit`), a resize cursor over it (`SplitHCursor` across an
`h` split, `SplitVCursor` down a `v`), its line lit in the accent colour
on hover and full accent while dragged. Dragging it snaps the whole split
to an allowed arrangement, and the pane draws the tree as it would be let
go, a small label by the pointer saying the split's ratio (`2 : 1`,
`2 : 1 : 1`; the theme's tooltip surface). An allowed arrangement has every
child a whole weight 1 to 5, divided by their gcd (`Layout.arrangements`:
19 for two children, 115 for three, 607 for four, computed once per
count). The snap is anchored to where the split's dividers were when the
drag started (never where the drag has had them since), the pointer's
place measured as a share of the split: of the arrangements keeping every
other divider exactly where it started, the one putting the dragged
divider nearest the pointer, if within 3% of the split; else the one
minimising 3 × the dragged divider's distance from the pointer plus every
other divider's from its start. So dragging the first divider of
`h[a, b, c]` keeps the second at 2/3 while it can (`1 : 3 : 2` at a sixth),
weights never climb past 5 however the pointer wanders, and the pointer
back where it started is the ratio it started as. A ratio typed with `r`
may be any whole one; dragging such a split moves it to the nearest
allowed arrangement (`h[a:6, b, c:6]`'s first divider let go mid a and b
is `3 : 3 : 5`). No child drops below 5% of the split (tree.lua's nudge
minimum): every arrangement of up to four keeps it (the least share is
1/16), and those of five or six that would not are left out. A split of
more than six children (whose arrangements grow past 5^7) snaps only the
dragged divider's two neighbours, as a pair 1 to 5 the same way, neither
below 5% of the split, the others keeping their size. The split's weights
are then divided by their gcd: `h[main:2, right]` let go about the middle
is `h[main, right]`.
Let go, it is an edit like `r`'s: into the draft (`edited, not applied`,
`w` applies, Ctrl+S saves, `d` reverts), asking first on a workspace using
the shared trees (a drag that snaps to the ratio there already changes
nothing and asks nothing). A divider names its neighbours by their leaves,
so a hidden place for other windows keeps its size (out of the
arrangement; a divider lists the leaves of its whole split, so the drag
knows what the picture drew), and one next to that
place where the engine puts it (`o`) writes its `*` into the tree, as
moving it does. No dividers on a scroll tree, a read-only layout, or while
a prompt is open; a press anywhere but on a divider goes on to the tile.
**Dragging slots** (`Layout.slotDrop`, `slotDropAction`, `tileZone`,
`leafAt`, `zoneRect`, `stripGap`, `stripGapX`; node-tested). A tile or a
filmstrip column pressed and moved `Assignment.DRAG_THRESHOLD` (6) px drags
its slot (other windows' place too while `o` shows it); under that a press
is a click (select), and a press on a divider drags the divider, a pane's
title the screen. Let go on a tile: its middle **swaps** the two slots
(each keeping its share, `×n`, as h/l's swap does: `h[main:2, right]`,
right onto main, is `h[right, main:2]`); an edge band a quarter of the
tile deep (the nearer edge in a corner) puts the dragged slot **beside** it
on that side: along the tile's split, a child next to it (its share kept);
across it, the tile split in two that way (the tile's share the new
split's), or, when the two were neighbours in one split, the two paired
in a new split taking both their shares (HJKL's pair). Let go between two
columns of a filmstrip and the column moves there. These are the keys'
own operations: a node test checks that a drop where hjkl/HJKL would put a
slot makes their tree. Let go on another screen's pane, the slot leaves its
tree (closing up) and lands there as the keys' cross-screen move lands it
(a share of 1; the same tree as `l` off the edge for a drop at the next
screen's near edge); a centre drop there trades the two slots between the
screens; a pane with no tree takes it as its whole tree. Other windows'
place never leaves its screen and a screen's only slot only goes in a trade
(refused: letting go says why). It is an edit like hjkl's: into the
drafts (`edited`, `w`, Ctrl+S, `d`), on a workspace using the shared trees
asking first whom it is for; the selection goes with the slot. While held
(as a pane's drag): the slot's tile or column dimmed, a `DragGhost` by the
pointer (the slot, the title of the window in it) with what letting go does
(`Swap with main`, `Put left of main`, `Put above main`, `Put between side
and chat`, `Put on screen 2`), and where: the target tile outlined in the
accent for a swap, the half of it on that side lit (`Tokens.dropBand`) for
an edge, an accent bar in a filmstrip's gap, a pane with no tree outlined
whole; where letting go does nothing, nothing is lit and no label shows. Esc
while held lets it go; an open hand over a tile that drags, a closed hand
while dragging. The panes are kept by count, so a state read while a drag
is held does not drop it.
A node test checks a dragged tree is the whole tree's ratio as ratio.lua
writes it in.
**Swapping screens** (`Layout.swapScreens`, `nextScreen`,
`screenDropAction`, `paneAt`; node-tested). A pane's title (`Screen 1 ·
Built-in`) is its handle: pressed and moved `Assignment.DRAG_THRESHOLD`
(6) px it drags (a click gives that screen the keys). The title, because
the rest of a pane is taken: tiles and filmstrip columns select and drag
slots, dividers drag ratios. Let go over another pane (the pane under the pointer, with
any number of screens; anywhere on it, its title included) and the two
screens trade trees: screen 1's tree goes to screen 2 and screen 2's to
screen 1, so their slots move between the monitors while the screens keep
their numbers, left to right. Each tree goes whole: its place for other
windows (its `*` leaf, or none, where the engine puts them), a scroll
branch's column width, and `t`'s memory of the tiles it came from. `p` is
the keys' way: the selected screen with the next (round from the last to
the first; on a layout of one screen the help row leaves it out and it is
refused). It is a layout edit like any other: into both panes' drafts
(`edited`, `w` applies them in one `set_trees`, so both screens change in
one edit; Ctrl+S saves, `d` reverts a screen), the message naming the
desks that share the layout (fork it in the Desk tab first), and on a
workspace using the shared trees asking first whom it is for (all
workspaces or only this one). The selection goes with the dragged (or
`p`'s) screen's tree. A screen with no tree there is not swapped (the
message says why). While held (as an Assignment row's drag): the dragged
pane dimmed, a `DragGhost` by the pointer (the screen's title, then the
slots its tree places), and over another pane that whole pane, title
included, outlined in the accent with a faint accent fill and the label
`Swap with screen 2` under the ghost; over its own pane or outside the
panes nothing is outlined and no label shows, and letting go does
nothing; Esc while held lets it go (the panel stays open; other keys
wait). An open hand over a title that drags (an editable layout of more
than one screen, no prompt open), a closed hand while dragging.
**Other windows** (windows assigned to no slot) always have a place in
every tree: its `*` leaf, else where the engine puts them (a column at the
right, `h[tree:3, *:1]`; after a scroll branch's columns). `o` shows or
hides that place in the picture (hidden by default), a dim box or
filmstrip column labelled `other windows`; while it shows it can be
selected and moved with hjkl like a slot, which writes the `*` into the
tree there. No key takes it away (it never moves to another screen), and
none takes a slot out or puts one in: every tree holds every slot (§4), an
empty one closes up, and a new slot is in every tree at once (an edited
draft takes it too, on the screen the engine put it on: `Layout.followNewSlot`).
Edits go to a **draft**
per pane (`edited` on the pane, `edited, not applied (w)` in the header).
The header is the workspace switcher, one strip (`Workspaces.stripLine`): `All workspaces · 1 2 3•
… 9`, the layout's shared (default) trees first, then the managed
workspaces (config `workspaces`, 1 to 9 by default) by their keys, a dot
after each with trees of its own (`3•`: an override); the current one in
the accent colour, underlined, the ones using the shared trees italic and
dimmer; a click switches. The view opens on All workspaces. A workspace
without trees of its own shows the shared ones and says so quietly after
the strip; its first edit asks `Apply to (a)ll workspaces or (o)nly
workspace N? [Esc] cancel`: `a` makes this and the following edits there the
shared trees' (`w` applies them as `workspace: "default"`, and every
workspace on them follows; the header then says `editing it for all
workspaces`), `o` this workspace's own (`w` gives it its own trees, an
override). The question comes again after a workspace switch. `u`, on a
workspace with trees of its own (the help row then shows it), asks `Drop
workspace N's own trees and use the shared tree? (y/n)` and calls
`drop_override`. Beside the panes, the **slot list**: the global slots by name,
each with its key and its description and nothing else (below).

| Key | Does |
|---|---|
| ←↑↓→ | select the leaf that way; off a pane's left/right edge, the next screen's |
| h j k l | swap the leaf with its neighbour in its container; off the edge, move it to the next screen's tree; by mouse, drag its tile (above) |
| H J K L | along its container: pair it with its neighbour in a new container across; across: move it out beside its container |
| / | on a tiled tree: flip every split of the tree; on a scroll branch refused (its columns always stand in a row), and the help row leaves it out |
| t | cycle tiles → scroll half → scroll full → tiles: a tiled tree becomes `scroll:0.5[...]` of its leaves in reading order (other windows' place, `*`, as the column they take), that becomes `scroll[...]` (any other width too), and that goes back to the tree it was made from while its columns are as they were, else its columns side by side; the slot order is kept |
| p | swap the selected screen's tree with the next screen's (round); by mouse, drag a pane by its title onto another (above) |
| r | on a tiled tree: prompt for the whole tree's ratio (grammar below; the current one shown, empty clears all); on a scroll branch refused (ratios are for tiles), and the help row leaves it out; by mouse, drag a divider (above) |
| o | show/hide other windows: where windows assigned to no slot go, in the picture (it changes no tree; moving it with hjkl writes its `*`) |
| w | apply the edited panes (`set_trees`) |
| Ctrl+S | apply the edited panes, then `save` (the panel's key) |
| d | revert: `Revert workspace 3's tree on screen 1 to how it was last saved? Its unsaved edits go. (y/n)`, then `reset` (the draft and the applied but unsaved edits of that tree go) |
| R | `record` the pane's workspace, show the tree, its ratio and what it would drop (`missing`), apply after y/n (not on All workspaces; on a workspace using the shared trees, to whichever its first edit's question chose) |
| u | on a workspace with trees of its own: after y/n, drop them (`drop_override`), so it uses the shared trees again |
| [ / ] | previous / next workspace, round from the last managed one to 1 (the arrows stay the picture's) |
| 1–9, 0 | workspace 1–9, 10 (as Super+N; 0 only when ten are managed); unapplied edits are dropped, and the message says which |
| - | All workspaces: the layout's shared (default) trees (`workspace: "default"`), the trees of every workspace without its own (the help row: `- all workspaces (the shared tree)`) |
| s | the keys go to the slot list (its border lights up; s or Esc back) |

The help row is one line at the panel's width (`Layout.pictureHelp`), the
keys grouped, the trigger keys highlighted: `←↑↓→ select  hjkl/HJKL move
/ flip  t scroll half  r ratios  p swap  o others · w apply  d revert
R record  u use shared · s slots · [ ] 1–9 - workspace · Tab view`
(`t`'s label names the next mode,
`/` and `r` only on tiles, `p` only on a layout of more than one screen,
`u` only on a workspace with trees of its own; `o`'s label is `others` to
keep the row one line with all of them, ten workspaces' `0` too).
A layout set in config.lua's code, a config without slots.lua, or the engine being
off shows `Read only: <why>` (naming no file: `layout 'x' is set by code in
your config`) and refuses the editing keys. No text the editor shows names
a file. Layout.js
mirrors tree.lua's text and ratio.lua's grammar (a node test runs the same
corpus through the Lua modules), so a draft is checked and shown without a
round trip; the engine validates again on apply. Deviations from
aerolayout: edits are a draft applied with `w` (aerolayout saved on every
keystroke); `d` reverts one screen's tree to its last save (aerolayout's
`d` dropped a workspace's own tree for the default one; hyprslots' `u`
does that, and `-` edits the shared trees); no `a` / `x` (aerolayout added
and removed slots per tree; here every tree holds every slot) and no `f`
(fork is the Desk tab's); [ ] and the digits change
the workspace (aerolayout's `g` picked a workspace or "all"); the layout is
always the active desk's (aerolayout's arrangements were the Monitors
tab's); the logical slots are made in this view's slot list, not
a tab of their own; `R` always
previews and asks; o only shows or hides the place for other windows
(aerolayout's `o` hid the overflow slot in the saved tree); a scroll
branch's columns are a row, so h / l move a column (the `*` column too;
H J K L refuse: a scroll branch holds slots and `*` only), and a leaf
moved onto a screen whose tree is one becomes its column at the near edge.

**The slot list** (in the Layout view; aerolayout `views.py` LogicalView,
which was a tab of its own). The global slots, one list for every workspace, by
name (the order windows claim them in): each slot's name, its key (a key cap
at the right: the letter that picks it in every slot-choice prompt, §4) and
its optional description, nothing more. Which app fills a slot on a workspace is the
Assignment view's `a`; every tree holds it, where it sits is the picture's.
`s` gives it the keys (the help line says so), and back:

| Key | Does |
|---|---|
| ↑/↓, k/j | select |
| a | new slot: a name, then an optional description (`add_slot`); `Added slot 'notes' to every tree. Ctrl+S saves.`: the engine puts it at the end of every tree (§4) |
| Return | select the slot where it sits in the picture, keys back to the picture |
| r | rename it everywhere: every tree of every layout, every workspace's spec, keyboard-resized trees and assignments, as aerolayout's rename_slot_everywhere (`rename_slot`); edited drafts follow |
| e | describe it (`describe_slot`; empty removes the description) |
| K | its key: `Key for 'main' (one letter a-z; now m)`, one letter (upper case read as lower), refused in the prompt when it is no letter or another slot's (`l is the key of slot 'left' already.`), then `set_slot_key` (`k` stays select: K, shifted, is the key's) |
| d | delete it, after y/n: `Delete slot 'main'? It goes from every tree and from the assignments of workspaces 3, 4.` (`remove_slot`, with `force` when workspaces fill it); edited drafts lose it too |
| [ ] 1–9 0 | the workspace, as in the picture |
| s, Esc | back to the picture |

A slot list config.lua builds in code says so and takes no edit. No
reorder (aerolayout's J/K): slots claim windows by name, so their order is
not the editor's to set.

**Desk view** (the third tab, `Desk`; aerolayout MonitorsView,
reshaped: aerolayout mapped monitors to arrangements; here desks and
layouts are two lists and a desk points at a layout). A line says what the
two are; then two sections, each under its column titles (Desk, Monitors,
Uses layout; Layout, Screens, Used by):

- **Desks** (monitor setups): each stored desk led by its **map** (below),
  by name, its monitors in screen order, left to right as its map and its
  layout number them (not the order the desk lists them in), each led by
  its screen number, by display name (§4), `○` before one not connected:
  `1 · Built-in + 2 · Odyssey G95NC`, `1 · Built-in + 2 · ○ Dell U2723QE`
  (`m` numbers them the same way), the
  layout it uses as a mapping (`→ dual`, so a desk and a layout of one
  name do not read as the name twice); the active desk marked quietly: a
  small `●` in the accent colour and its text at full strength where the
  other rows' is a little dimmer; `(new, unsaved)` on one the engine made.
- **Layouts** (logical arrangements for N screens): each by name, its screen
  count, the desks using it (`unused` when none); the active layout marked
  the same way.

**Desk maps** (`ui/DeskMap.qml`, `DesksLayouts.deskMap`,
`DesksLayouts.deskMapTip`). Each desk row leads with a small map of its
monitors, in a column of its own (layout rows leave it empty): the boxes
state reports (`desks[].geometry`: the live ones on the active desk, the
recorded ones on another, equal boxes side by side in the order the desk
lists its monitors for a desk never seen, §8) fitted at their own shape into
a fixed box (`Tokens.deskMapWidth` × `deskMapHeight`, 72 × 36 at scale 1)
and centred in it, each screen a rectangle labelled with its number, the
layout's (left to right, then top to bottom), a pixel apart from the next;
a connected monitor solid, one that is not outlined; the active desk's in
the accent, the others in a dim line colour. Hovering a map shows its
screens' display names as a tooltip (`1 Built-in · 2 Odyssey G95NC (not
connected)`, the tooltip surface) just under the map's row, its left edge
at the map's (above the row when the list has no room below), drawn over
the list by the view: nothing on the hovered row is hidden (beside the map
it covered the desk's name) and neither the row nor the list clips it. Desk rows are tall enough for it
(`Tokens.deskMapRowHeight`).

The section headers are quiet labels (`DESKS monitor setups · ○ not
connected`, muted small capitals), the column titles muted. One selection runs
through both sections (↑/↓, k/j); it opens on the active desk, and it is
the strongest thing on the page: the theme's selected accent fill, a
stripe of the accent down its left edge, its name in the selected text
colour. hyprslots picks the desk itself (§8): this view says which layout a
desk uses and edits the stored mappings, never the monitors themselves.

| Key | On a desk | On a layout |
|---|---|---|
| a | pick a layout with as many screens as the desk has monitors, then `apply_layout {desk, layout}` | apply it to the active desk (`apply_layout {layout}`; refused on the message line when the screen counts differ) |
| f | fork the desk's layout | fork this layout: a name (the next free `<name>-N` suggested), then `fork_layout {layout, to}`: the active desk uses the copy when its monitor count fits (the reply says) |
| n | new layout: a name, a screen count (the active desk's suggested), then it is made with the default trees (`add_layout`, §4) | the same |
| m | name one of its monitors: which (numbered, when it has more than one), then the name, its current label filled in (`set_monitor_name`; empty clears it, back to the automatic name) | — |
| r | rename (`rename_desk`) | rename (`rename_layout`; its desks follow) |
| x | delete after y/n (`delete_desk`); the active one with a warning that its monitors then get a new desk | delete: when desks use it, pick a layout of as many screens to move them to (`delete_layout {layout, remap}`), else y/n (`delete_layout`); the engine's refusal shows on the message line |

An entry config.lua builds in code (`read_only`) refuses every edit with
`set in your config`.

**Bar widget** (`BarWidget.qml`, model `BarStatus.js`). A grid glyph and
the active layout's name (`none` when no desk is active), nothing else: no
desk or workspace (Omarchy's workspace switcher shows those); the tooltip
names the desk, the workspace its bar's monitor shows (`state.workspaces`)
and that monitor's display name (`workspace 3 on Built-in`), and the layout (`Layout: ultrawide`, and `also used by: office` when
shared). It reads the
plugin's service and calls its `watch()` so the service follows change
events while the panel is closed: one poller for the panel and every widget
instance. Omarchy's built-in bar hands a widget `serviceFor`; a replacement
bar (a `kind: bar` plugin, such as a clone of `omarchy.bar`) hands only
toggle / summon / hide, so the service also registers itself in
`Services.js`, a `.pragma library` script (one instance per QML engine,
shared by the plugin's files), where the widget finds it. The widget looks
again every 2 s: the service may come up after the bar, and a plugin reload
replaces it. The workspace follows workspace switches
from Quickshell's Hyprland objects, with no state read.

| State | Shows |
|---|---|
| normal | `󰕰 scroll` in the bar's foreground |
| zero slots (a fresh install) | `󰕰 set up` and an accent dot at the glyph's top right; the tooltip "no slots yet", "Click to set up your slots" (a click opens the panel on its Layout tab); no unsaved dot meanwhile |
| unsaved edits (`dirty`) | `󰕰 scroll •`, the tooltip says "unsaved edits" |
| error | the bar's urgent colour, the error first in the tooltip: the service missing, a state read failing (hyprctl, `hyprslots` not loaded: `󰕰 hyprslots` until a state was read, else the last one), `refused` (`󰕰 off`), `config_error` (the running config still shown) |

Left click toggles the panel (`shell.toggle`). Right click opens a menu
(Omarchy's `PopupCard`, laid out like the tray's menu; outside click
closes it):

| Entry | Does |
|---|---|
| Re-apply layout (workspace N) | `workspace {workspace: N}` (its Super+N: every screen of the desk shows it again, scroll branches back in slot order), then `arrange` (the scroll pass now, the focused scroll workspace's columns widened) |
| Record workspace N… | opens the panel with `{"record": true}`: the Layout tab on the focused workspace, its `R` flow (preview, then y/n) |
| Save | `save`; only with unsaved edits |
| Reload config | `reload` (drops unsaved edits; how a fixed config error is picked up) |

Re-apply and Record need the bar's screen on a hyprslots workspace of a running engine
(a config error leaves the last good config running); with the engine
off or unreachable only Reload is offered. Each call's outcome, or the
engine's error, is a notification (`notify-send` through `bar.run`).

**Install** (the user's machine; not done by the slices):

```sh
ln -s ~/.local/share/hyprslots/editor ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.milanmitrovic.hyprslots
omarchy-shell shell toggle io.github.milanmitrovic.hyprslots       # open / close
omarchy bar put io.github.milanmitrovic.hyprslots --after milan.layout   # the bar widget
```

(`omarchy bar put` writes the widget into `~/.config/omarchy/shell.json`'s
bar layout; `omarchy bar move` places it elsewhere. A widget whose plugin
was added after the shell started needs `omarchy-shell shell rescanPlugins`
first.)

and a key in `~/.config/hypr/bindings.lua`:
`o.bind("SUPER + CTRL + Y", "Hyprslots", { panel = "io.github.milanmitrovic.hyprslots" })` (any free key;
Omarchy uses SUPER + CTRL + S for Share)
(third-party panels go through `omarchy-shell shell toggle`). Validate with
`omarchy plugin validate <the real editor/ path>` (it refuses symlinks).
Caveats: the shell's plugin watcher does not follow a symlinked folder, so
after editing run `omarchy-shell shell rescanPlugins`; an imported `.js`
can stay cached across that reload, and then only `omarchy-restart-shell`
picks it up.

### Api contract

`hyprslots.api.call(name, json)` returns a JSON object string, never `""`:
`{"ok": true, ...}` or `{"ok": false, "error": "..."}`. Every change bumps
`seq` and emits `hl.dsp.event("hyprslots changed <seq>")` (socket2:
`custom>>hyprslots changed <seq>`): api edits, save, reload, window open /
close, a keyboard nudge or reset, and a desk change on hotplug. `seq`
restarts at 0 when Hyprland reloads its config (Lua state is discarded), so
the editor treats any event as "re-read state", not as an ordering.

`layout?` defaults to the active desk's layout and `desk?` to the active
desk; `workspace` is a number 1 to 10 (1 to config `workspaces`), or `"default"` (a layout's default
trees) where the tree calls say so; `screen` is a screen number (1 the
left-most; as an object key, `"1"`).

| Call | Arguments | Reply (besides `ok`) |
|---|---|---|
| `state` | — | see below |
| `workspace` | `workspace` | `workspace` (the Super+N switch) |
| `set_tree` | `layout?`, `workspace` (or `"default"`), `screen`, `tree` | `layout, workspace, screen, tree, ratio, seq`; on a workspace that shows the default trees, its own copy of them first |
| `set_ratio` | `layout?`, `workspace`, `screen`, `ratio` (grammar below) | same as `set_tree` |
| `set_trees` | `layout?`, `workspace`, `trees` (screen -> tree) | `layout, workspace, trees` (screen -> `tree, ratio`), `seq` |
| `reset` | `layout?`, `workspace`, `screen` | `layout, workspace, screen, tree?, ratio?, seq` |
| `fold_trees` | `layout?` | `layout, folded[]` (workspaces whose own trees went), `kept[]` (`workspace, reason`), `seq`: drops every workspace's own trees the shared ones lay out the same |
| `drop_override` | `layout?`, `workspace`, `screen?` | `layout, workspace, screen?, own` (whether it still has trees of its own), `seq`: the workspace (or that screen of it) back to the shared trees |
| `record` | `workspace_id?` (default focused), `apply?` | `layout, workspace, screen, workspace_id, tree, ratio, missing[], applied, seq` |
| `assign` | `address`, `workspace`, `slot` | `address, workspace, slot, displaced?, seq` |
| `unassign` | `address`, `clear_spec?` | `address, workspace?, slot?` (the slot the window was in), `spec?` (the spec cleared), `seq` |
| `add_slot` | `slot`, `description?`, `key?` (else picked from the name, §4) | `slot, key, description?, seq` |
| `remove_slot` | `slot`, `force?` | `slot, trees[]` (`layout/workspace/screen`, workspace `default` for the default trees), `specs[]` (workspaces), `seq`; refused, saying which, while workspaces fill it (every tree holds it anyway), unless `force` |
| `rename_slot` | `slot`, `to` | `slot, to, trees` (how many were rewritten), `specs[]` (workspaces whose spec moved), `seq` |
| `describe_slot` | `slot`, `description` (`""` removes it) | `slot, description, seq` |
| `set_slot_key` | `slot`, `key` (one letter a-z no other slot has, §4) | `slot, key, seq` |
| `set_spec` | `workspace`, `slot`, `spec` | `workspace, slot, spec` (normalized), `seq` |
| `clear_spec` | `workspace`, `slot` | `workspace, slot, spec` (the one cleared), `seq` |
| `take_spec` | `workspace`, `slot`, `address` | `workspace, slot, spec, replaced?, address, displaced?, left?` (`workspace, slot, spec`: the slot the window left, its spec cleared with the move), `seq`: the window takes the slot and its spec becomes the workspace's (every tree holds the slot already) |
| `add_desk` | `name`, `monitors[]` (selectors), `layout` | `desk, monitors, layout, active, seq` |
| `rename_desk` | `desk`, `to` | `desk, to, active, seq` |
| `delete_desk` | `desk` | `desk, active, seq`; the active one too (its monitors then get a new desk, §8) |
| `apply_layout` | `desk?`, `layout` (one for as many screens as the desk has monitors) | `desk, layout, active, seq` |
| `add_layout` | `name`, `screens`, `default?` (true: the default trees of §8) | `layout, screens, seq` |
| `fork_layout` | `layout?`, `to`, `desk?` | `layout, to, desk` (the desk now using the copy, when its monitor count fits), `active` (layout), `seq`: a copy, keyboard-resized trees included |
| `rename_layout` | `layout`, `to` | `layout, to, active, seq`; the desks using it follow |
| `delete_layout` | `layout`, `remap?` | `layout, remap, desks[]` (those remapped), `active, seq`; refused while desks use it, unless `remap` names a layout for as many screens |
| `set_monitor_name` | `selector` (one a desk lists, or a connected monitor's description, serial or connector), `name` (`""` clears it) | `selector, name` (trimmed), `display` (the name shown now), `seq` |
| `save` | — | `path, seq` |
| `reload` | — | `desk, layout, seq` |
| `arrange` | — | `swaps, widened[]` (workspace ids): the scroll pass now, every column of the focused scroll workspace widened (Super+L entering slots) |

`state`: `seq`, `workspace_count` (config `workspaces`: how many
workspaces hyprslots manages, 9 by default), `dirty` (unsaved edits, keyboard-resized trees, a new desk
and slots.lua in a shape of before included), `desk` and `layout` (the
active ones' names), `screens[]` (the active desk's connectors, left to
right), `workspaces` (id -> `workspace, screen, monitor, layout`:
`lua:slots` or `scrolling`, the Hyprland layout hyprslots gives it),
`assignments` (address -> `workspace, slot`, `manual` when made by
`assign`), `overflow` (address -> `workspace, slot`: a window that matches
that slot's spec while every slot it matches is taken, laid out in that
workspace's overflow leaf), `unassigned[]` (addresses taken out of their
slot by `unassign`), `desks` (name -> `monitors[]` (selectors),
`connected[]` and `displays[]` (one per selector: the display name, §4), `layout`, `active`,
`screens[]` (the active one's connectors), `auto` (made for new monitors,
unsaved), `read_only`, `geometry[]` (one per selector, the desk's map:
`x, y, w, h` normalized as slots.lua records them, §4, and `screen`, its
number as the layout's; the live boxes on the active desk, the recorded ones
on another, else equal boxes side by side in selector order)), `layouts` (name -> `screens` (count), `default`
("1" -> `{tree, ratio, slots[], resized?}`), `workspaces` ("3" -> "1" ->
the same: the trees each workspace shows, its own or the default ones),
`own[]` (the workspaces with trees of their own), `used_by[]` (desks),
`active`, `read_only`), `monitors[]` (`name, description, serial, focused,
x, y, width, height, internal, selector`: what a desk can select them by,
`display`: the name the editor shows, `label`: the user's, when set),
`monitor_names` (selector -> label),
`resized` (`"<layout>/<workspace>/<screen>"` -> `layout, workspace, screen,
tree, ratio` for every unsaved keyboard-resized tree), `scroll[]` (one per
scroll branch on a hyprslots workspace: `workspace_id, workspace, screen,
slots[], width` (its columns', a fraction of the screen: 0.99 full), `layout` (its tiled layout), `managed` (scrolling, no saved Omarchy
mode), `columns[]` (window addresses in column order), `members` (slot ->
address), `in_order`), `slots[]` (the global slots by name: `name, key?,
description?`), `specs` ("3" -> slot -> spec text), `used_workspaces[]`
(workspaces with specs or trees),
`windows[]` (`address, class, title, workspace_id, floating, box{x,y,w,h},
workspace?, slot?, overflow?{workspace, slot}, unassigned?`), `config`
(`dir, data_file, editable, read_only[]` (`"desks.work"`, `"layouts.x"`,
`"specs.4"`, `"slots"`), `migrated`), `refused`, `config_error`,
`log_seq`.

**Assignment by hand** (the Assignment view). `assign` puts an open
window into a slot of a workspace whatever the slot's spec says, and moves it to
the slot's workspace. The window holding that slot is routed again as if it
had just opened (another free slot it matches, else its workspace's overflow) and
is named as `displaced`; the slot the window left goes to the oldest window
overflowing on it. A hand-made assignment is sticky like any other, and
re-solves keep it while the slot exists, even though the spec does not
match. `unassign` takes a window out of its slot: it stays where it is (on a
hyprslots workspace, in the overflow leaf), its slot goes to the oldest window
overflowing on it, and it takes no slot, by routing, late title, layout or
re-solve, until it is assigned again or closes. Both live in memory only
(neither touches `slots.lua`), survive `reload` and hotplug, and are lost on
a Hyprland config reload like every assignment. Both refuse a window that is
not open; `assign` refuses a slot that is not defined (any workspace 1 to 10 may
take any global slot, spec or none).

**Unassigning with the spec** (the Assignment view's `u`). `unassign` with
`clear_spec: true` also drops the workspace's spec for the slot the window held
(the reply's `spec`), so the slot is left empty rather than waiting for the
window just taken out. The spec goes first, as `clear_spec` (checked by
re-running config.lua, refused with nothing moved when config.lua owns the
workspace's specs), so no other window it matched takes the slot; then the
window is unassigned as above. The reply names the slot the window was in,
even where clearing its spec re-routed it into another slot that the spec
of before still matched, a moment before it was taken out. A window that only overflows, or holds a
slot its workspace has no spec for, is just unassigned. The cleared spec stays
in memory until `save`, like any spec edit.

**Taking a spec** (the Assignment view's `a`). `take_spec` makes the
window's spec (`spec.from_window`: `class`, `class/identifier` for a class
with title rules, `[Tag]` or `[Tag]/Profile` for a browser) the workspace's spec
for the slot and puts the window there. The edit is checked (config.lua
re-run over it) before anything moves; then the window is assigned as by
`assign` (the holder displaced and routed again), the assignment is made an
ordinary one (the new spec names the window), and the edit is applied, so
the re-solve keeps that window in the slot over any older one the spec also
matches. **A window moving out of another slot** (slot A to slot B, by `a`
or a drop; on the same workspace or, through the api, another) leaves A
empty: when A's spec on its workspace admits the window (it is what put it
there) and is the editor's, the same edit clears it, as `u` would (reply
`left`: `workspace, slot, spec`), so A is not left `Missing` the window that
just moved, and a later `u` from B leaves it unassigned rather than routing
it back into A. One edit, one change event, one unsaved change. A spec of
A's that is not the window's (it was put there by hand) stays, and so does
one config.lua owns. `assign` (by hand, in memory only) never touches specs.

Every tree holds every slot (§4), so the slot is in the workspace's trees
already: taking a spec places nothing.

**Layout editing** (the Layout view). Every tree call edits a layout (by
default the active desk's), so it changes every desk using that layout.
`set_trees` sets several of a workspace's trees in one edit, all or
nothing: a slot sits on one screen of a workspace, so moving it to another
screen cannot be two `set_tree` calls. A tree set on a workspace that shows
the layout's default trees first gives it its own copy of them (the other
workspaces keep the default ones): an override, which is what the Layout
view's `o` asks for; `"default"` edits the default trees themselves (its
`a`, and All workspaces). `drop_override` sends a workspace (or one screen
of it) back to the shared trees, dropping its keyboard-resized trees
there; `fold_trees` drops, in one edit, every workspace's own trees that
are the shared ones with slots missing (`edit.redundant_with_default`, per
screen: the same containers nested the same way, the same slots in the same
order, the same overflow leaf, and the shares pruning those slots leaves,
2:2 being 1:1; a screen with no tree of its own matches one with no shared
tree, or one whose every slot it leaves out), keeping one whose workspace
has a spec for a slot its own trees leave out and the shared ones place
(that spec would start filling it), and says why it kept each. Each tree it sets replaces that branch's keyboard-resized
override (kept when the edit fails). `reset` puts one branch back to the
tree slots.lua holds on disk (read data-only, as saved, not as first
loaded): the workspace's own tree there, else the saved default one, else
none, and a workspace whose trees are then the saved default ones, with none
of its own on disk, shows the default ones again; it drops an unsaved edit
and a keyboard-resized override of it; other branches keep their edits, and
the engine is clean again once its data is the file's. The saved tree is
read through the slot and layout edits made since (below): the engine keeps
the `rename_slot`, `remove_slot`, `rename_layout` and `delete_layout` calls
until its data is the file's again (save, reload, a reset back to the file)
and replays them over the saved data with `edit.lua`, so after renaming slot
`a` to `x` a reset gives back `h[x:2, b]`, not a tree naming a slot no
longer there, and a layout renamed since finds the tree saved under its old
name.

**Slot, spec, desk and layout edits** (the Layout view's slot list, the
Assignment and Desk views). Each builds new data with `edit.lua`
(pure), re-runs `config.lua` over it, and refuses the edit, changing
nothing, when the result does not validate or does not show the edit (a
field `config.lua` builds in code, or does not take from `slots.lua` at
all). Otherwise it is applied like `set_tree` (re-select, re-assign,
re-route, window rules, relayout, change event) and stays in memory until
`save`. `add_slot` puts the new slot into every tree (§4's
normalization), keyboard-resized ones too (`resize.conform`: an override
loses the slots its configured branch no longer has and gets the new ones
at its end, its nudges kept). `rename_slot` rewrites the slot's name in every tree of every
layout (default trees too), in every workspace's specs, in the
keyboard-resized overrides, and in the assignments (a hand-made one stays
hand-made); `remove_slot` takes the slot out of those trees (a container
left with one child is replaced by it, a branch left empty goes) and drops
every workspace's spec for it, asking for `force` only while workspaces
fill it. `clear_spec` drops one workspace's spec; the
slot and the trees stay. `apply_layout` points a desk at another layout for
as many screens; `fork_layout` copies one (its keyboard-resized trees too)
under a new name and points the desk at the copy, so its edits no longer
reach the desks that shared the original; `add_layout` makes an empty one,
or one with the default trees of §8; `rename_layout` takes the desks using
it along and moves its overrides; `delete_layout` refuses while desks use
it unless `remap` names one for them, and drops its overrides.
`rename_desk` and `delete_desk` change only the desk (the layout stays,
used or not). `active` in a reply is the desk
(or layout) running afterwards.

**The tree in force** for a branch is `api.effective_branch`, which is
`resize.effective_branch`: a keyboard-resized override (§6) if there is
one, else the config's. `state` reports it, `set_ratio` starts from it,
`record` compares against it, `save` writes it.

Edits never write files: they re-run `config.lua` over the edited
`slots.lua` data in memory and take effect only when the result validates.
The new config is then applied like a hotplug: re-select, re-assign,
re-route every assigned window to its slot's workspace (a slot moved to
another screen takes its open window along), scroll pass, relayout.
An edit to a branch replaces that branch's keyboard-resized override.
`save` writes `slots.lua` through `serialize` (temp file + rename), then
runs the saved data as the config and clears the overrides it wrote;
`reload` / `hyprslots.reload_config()` re-reads both files in place,
dropping unsaved edits and every override.

**Read-only fields.** A config field is the editor's only when `config.lua`
passes the data file's own table through (identity check, at the top level
and one level down). Anything built in code is listed in
`config.read_only` (`"desks.work"`, `"layouts.office"`, `"specs.4"`, and
`"slots"`, the global slots being one field) and refused by the edit
calls.

**Ratio grammar** (`ratio.lua`, from aerolayout): `ratio := term (':'
term)*`, `term := (number | '*') ('[' ratio ']')?`. `2[1:2]:1` sets a
split and its first cell's split in one string; spaces separate like `:`;
decimals become the smallest integer ratio (1.5:1 -> 3:2); `*` is a
scroll branch's column (its cells take `*` or `1` and write nothing: each
column is full width; a `*` among tiles is refused). The `ratio` in `state` is always in this grammar
and can be sent back unchanged. This `*` is the ratio grammar's own and is
unrelated to the overflow leaf `*` of tree text.

**Record** (`record.lua`, from aerolayout's record.py): guillotine cuts
over the windows' boxes (3 px epsilon), weights snapped to integers (8%
snap, else a small integer multiple within 2%, else hundredths); windows
that overlap cannot be recorded, as in aerolayout. A scroll branch records
as its slots in the column order they show (so `swapcol` and record set the
slot order); one that places `*` records it where the first window with no
slot in the branch shows (missing when none shows). A slot with no window
stays in the recorded tree, at its end (every tree holds every slot, on the
screen it was on); a record with such a slot, or without the overflow leaf
the tree had, is returned with `missing` and not applied unless
`apply: true`. A scroll branch keeps its width.

**Relayout.** After an edit the engine sends a zero `hl.dsp.window.resize`
to one tiled window per hyprslots workspace: a lua layout recalculates on any
resize request.

## 10. Modules

Under `lua/hyprslots/`:

| Kind | Module | Role |
|---|---|---|
| pure | `spec` | parse and match window specs; the spec naming a window |
| pure | `tree` | parse tree text (§6), split boxes by integer weights, nudge |
| pure | `ratio` | ratio grammar for the editor's `set_ratio` and `state` |
| pure | `record` | rebuild a tree from live window frames |
| pure | `config` | load and validate `config.lua` / `slots.lua` (sandboxed) |
| pure | `migrate` | slots.lua's shapes of before (per-workspace slots; arrangements), read as global slots, desks and layouts |
| pure | `edit` | edits to the `slots.lua` data (trees, slots, specs, desks, layouts); which fields code owns |
| pure | `desk` | pick the desk matching the monitor set, number its screens left to right; name and default trees of a new desk; its geometry (logical boxes) and map |
| pure | `monitor_name` | a monitor's display name: the user's label, Built-in, the model (PNP vendor names read once) |
| pure | `assign` | windows → slots |
| pure | `serialize` | write `slots.lua` and tree text deterministically |
| pure | `slot_key` | each global slot's key: check one, pick a new slot's, fill the ones missing (§4) |
| adapter | `starter` | a fresh install's starter `config.lua` and empty `slots.lua`, written only where missing (§4) |
| pure | `dkjson` | vendored JSON |
| adapter | `init` | `setup()`, wrapped in `pcall`, never takes Hyprland down |
| adapter | `hl_adapter` | the only module that touches `hl` |
| adapter | `layout` | `hl.layout.register("slots", …)` |
| adapter | `router` | window events → assignment and moves |
| adapter | `workspaces` | workspace switching on top of `o.workspaces` |
| adapter | `hotplug` | monitor events → desk selection, then re-route |
| adapter | `blocks` | the active desk's screens own Omarchy's workspace blocks (screen i: block i-1); pure `plan` renumbers workspaces into them |
| adapter | `scroll` | scroll branches on Hyprland's scrolling layout (pure `plan` / `order`, deferred pass, `describe`) |
| adapter | `resize` | keyboard resize via `layout_msg`; the tree in force |
| adapter | `api` | `state()` / `call(name, json)` for the editor |
| adapter | `log` | ring buffer; `hyprslots.dump()` prints it with the state |

Other top-level directories: `editor/` (QML plugin, §9), `spec/` (busted specs and
`spec/helpers/hl_stub.lua`), `e2e/` (headless Hyprland harness).

**Loading.** A shim `~/.config/hypr/hyprslots.lua` prepends the repo's
`lua/?.lua;lua/?/init.lua` to `package.path`, then runs
`hyprslots = require("hyprslots")` and `hyprslots.setup()`; the `hyprslots`
global is what `hyprctl repl` and the editor address. It is
required from `hyprland.lua` right after `require("hypr.autostart")`; it
cannot go after hyprmoncfg's `dofile`, which stays last. On the user's
machine the shim reads the code from `~/.local/share/hyprslots`, a symlink
to the checkout in use (`ln -sfn ~/Projects/hyprslots/master
~/.local/share/hyprslots` once the branch lands), and, being after
Omarchy's and the user's bindings, also calls `bind_workspace_keys()` and
`bind_resize_keys()`; all of it inside `pcall`, with a notification on
failure.

**Gaps.** Hyprland hands a lua layout `ctx.area` already inside
`gaps_out`, and `place` takes the border and `gaps_in` off each box edge
that meets another box, as dwindle does. Hyprland's scrolling layout works
in the same area and keeps the same margins. `e2e/gaps_test.sh` pins both
with Omarchy's gaps (5/10, border 2).

## 11. Roadmap

| Slice | Content | Status |
|---|---|---|
| 1 Tracer | one screen, one desk tree via `lua:slots`; config, arrangement, tree, spec-by-class, layout, route, dump | done |
| 2 Desks | desks across screens, synced Super+N, pinned screens (removed since), hotplug; turns the completion test green | done |
| 3 Specs | full spec grammar, late titles, generated window rules | done |
| 4 Containers | accordion (groups) and overflow | done; the accordion replaced by the scroll branch |
| 5 Resize | keyboard resize via `layout_msg`; `lua:slots` in the Super+L layout cycle, focused screen only | done (Super+L patches applied at cutover) |
| 6 Protocol | record, api protocol, serializer, ratio grammar | done |
| Editor D1 | plugin skeleton (Engine service, panel, tabs) + Assignment view; api `assign` / `unassign`, `overflow` in `state` | done |
| Editor D2 | Layout view; api `set_trees` / `reset` | done |
| Editor D3 | Slots + Arrangements views; their api edits; slot descriptions | done |
| 7 Cutover | install the engine and the editor plugin on the user's machine, retire the old setup | done 2026-11-08 (from `feature/editor`; `~/.local/bin/hyprslots-rollback` undoes it) |
| Scroll | scroll branches on Hyprland's scrolling layout replace accordions; the laptop desks become `scroll[...]`; Super+L's slots stop covers them | done 2026-11-08 |
| Global slots | slots are global logical names (aerolayout's `logical_slots`), specs per desk; the per-desk shape migrated on load; the Slots view edits the list, the Assignment view's `a` sets a desk's spec, the Layout view's `a` / `x` place slots; `[Tag]` matching in any case | done 2026-11-08 |
| Editor rework | the Slots tab folded into the Layout tab as a slot list (name and description only; make a slot and place it there); desks by `[` `]` and the digits in the Layout and Assignment views (the arrows stay the picture's); `u` clears the desk's spec with the window (`unassign` `clear_spec`), the slot left empty; a scroll branch's `*` column (`scroll[left, main, *, right]`) in the engine and the editor's `o`; the Super+L patch refreshes the dock | done 2026-11-08 |
| Desks & layouts | workspaces 1-10 renamed from desks (api `workspace`, `hyprslots.workspace`, `bind_workspace_keys`); arrangements replaced by desks (monitor setups) and layouts (N-screen logical arrangements, shareable, default trees) keyed by screen number left to right; arrangements migrated on load; a desk made for unknown monitors; the editor's Desks & Layouts tab (apply, fork, new, rename, delete, pin), the header naming desk and layout, highlighted help keys, `u` on a Missing row, the bar's `<desk> · ws <n>` | done 2026-11-09 |
| Editor polish | the Assignment view lists every global slot (unplaced ones looking like the rest, `a` placing one: `take_spec` `place`); config `workspaces` (how many hyprslots manages); `-` for the default trees (All workspaces since, see Shared trees); the third tab named Desk, its desks reading `→ <layout>` under column titles; new layouts named for what they arrange (`scroll`, `<N>-screen`) | done 2026-11-09 |
| Shared trees | one shared tree per layout and screen ("All workspaces", the default trees) instead of the cutover's per-workspace copies cut down to each workspace's slots (empty slots close up anyway): `edit.redundant_with_default`, api `fold_trees` and `drop_override`, `take_spec` `place` into the shared trees for a workspace without its own; the Layout view opening on All workspaces, first in the strip, overrides dotted, the first edit of a workspace on the shared tree asking all or only this one, `u` dropping an override; the user's layouts folded (only `wide` and `dual` workspace 3 keep their own) | done 2026-11-09 |
| One set of slots | every tree holds every global slot (`migrate.normalize` on load and every edit; an empty slot closes up), so nothing places or takes out a slot: the Layout tab's `a` / `x`, `take_spec` `place` and `edit.place_slot` go, a new slot is in every tree; a scroll branch's own column width (`scroll:0.5[...]`, config.lua's `scroll.width` migrated into the trees), the Layout tab's `t` cycling tiles, scroll half and scroll full, scroll branches drawn as a filmstrip, `r` on tiles only; `d` reverts; fork only in the Desk tab; pinned screens removed (migrated away); the Layout header one strip and its help one line; no file names in the editor's text | done 2026-11-09 |
| Monitor names | display names for monitors (Built-in, the model from the description less make and serial, the user's label in slots.lua `monitor_names`) everywhere the editor shows one; the Desk tab's `m`; api `set_monitor_name`, `display` / `displays[]`; new desks named after them (`built-in+odyssey-g95nc`) | done 2026-11-11 |
| First run | a fresh install: the starter config.lua and empty slots.lua (`starter.lua`), zero slots running; the panel opening on Layout with no slots, else Assignment; every empty state pointing to the next step (`Guide.js`: the Layout tab's explanation and "Create your first slot", the Assignment tab's way back to it, a workspace's how-to-assign line, the Desk tab's opening line); the bar's set-up state; README's Getting started | done 2026-11-15 |
| Desk maps | the active desk's geometry recorded in slots.lua (quietly: saved when nothing else is unsaved, else with the next save), `state.desks[].geometry`; the Desk tab's rows led by a map of each desk's monitors (`ui/DeskMap`); moving a window to another slot clears the spec of the one it left (`take_spec` `left`), `unassign` naming the slot the window was in | done 2026-11-15 |
| Assignment by mouse | Assignment rows dragged and dropped (onto a slot: `a`; onto the other windows: `u`; Esc or elsewhere: nothing; a ghost, the target outlined, its label); each slot row's mini-map of its screen's tree, the slot lit (the Layout picture's geometry, `ui/MiniMap`) | done 2026-11-15 |

Slices 2 to 6 were built in parallel on top of slices 1 and 2 and
integrated on `feature/engine`; the cross-slice behaviour (keyboard-resized
trees as the api's tree in force, nudges on the laid-out tree, re-routing
and window-rule sync after edits, the scroll pass after hotplug's re-route,
matched extras in their desk's overflow, sticky re-solves) is described in
the sections above and covered by `e2e/scroll_replug_test.sh` and
`e2e/resize_save_test.sh`.

D2 and D3 were built in parallel on top of D1 and integrated on
`feature/editor`, which made them one editor: one save key (Ctrl+S, the
panel's, in every tab), one prompt implementation (`Prompts.js`, the
Layout and Assignment views' own prompts retired), `reset` reading the
saved tree through the slot and Arrangements views' renames and removals,
and the Layout view following an arrangement renamed or deleted under it;
`e2e/editor_smoke.sh` drives every view in one run. The rework after the
cutover made the Slots view the Layout view's slot list.

Parked:

- mouse-resize workaround, and an upstream Hyprland PR for a resize hook;
- spanning windows;
- public release / AUR package;
- QML tests (the views' QML is covered only by the editor smoke; their
  logic is in the node-tested `.js` models);
- the Layout view's parked overflow leaf lives only while the panel is open
  (aerolayout kept it in the saved tree);
- slot reorder (aerolayout's J/K): slots claim windows by name;
- dropping the shapes of before's migration once no slots.lua holds them;
- editing a desk's monitor selectors (desks are made from the monitors
  connected; the editor renames, deletes and repoints them);
- remembering the most recently used layout across a Hyprland reload (a new
  desk then takes the first layout by name of as many screens);
- forking a layout that config.lua builds in code (fork copies slots.lua's).

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
- **Editor**: the api it relies on is S2 (`spec/assignment_api_spec.lua`,
  `spec/layout_api_spec.lua`, `spec/slots_api_spec.lua`, `spec/api_spec.lua`); its pure JavaScript runs under `node --test`
  (`editor/tests/`, part of `make test`); `make editor-lint` runs Qt 6's
  qmllint. `make e2e-editor` (`e2e/editor_smoke.sh`, opt-in, needs qs, grim
  and wtype) runs the plugin in Quickshell on the nested Hyprland through
  `e2e/editor/shell.qml` (which stands in for the Omarchy shell: it injects
  the service and adds an IPC target), drives the panel with real pointer
  clicks (`e2e/shim/vpointer.c`, built by the smoke: a
  wlr-virtual-pointer client that moves to a point in two steps, waits for
  the surface under it to take pointer focus, then clicks, double-clicks or
  drags; one `vpointer serve` for the whole run, fed commands through a
  FIFO, since a pointer device per click made the panel rebind its
  wl_pointer each time and Hyprland now and then sent the fresh one no
  motion after its enter at -1, -1, so a click was lost;
  `smoke_click` clicks the control a `Panel.clickPoint` names by its
  objectName: `toolbar:a`, `chip:s`, `prompt:yes`, `tab:Desk`, `row:3`,
  `slot:main`, `tile:1:aside`, `workspace:8`) and with real keys from
  one wtype session (a fresh virtual keyboard loses its first key, and a
  second wtype's keys did not arrive, so the sequence is one session starting
  with an ignored F13) and with `press()`, asserts through api `state`, the
  windows' geometry and the saved `slots.lua` (Assignment: assign by real
  keys, which takes the window's spec, `u` taking it out with that spec
  (the row empty, slots.lua without it after Ctrl+S), `u` on a Missing row
  clearing that workspace's spec, `c` doing nothing, `[` / digits paging;
  workspace 8 with `scroll[main, aside]` listing every global slot, and
  `a` on a window there assigning it without placing anything;
  the header (`Desk: solo · Layout: solo (also used by: beamer)`) and the
  help rows' highlighted keys in every tab, the Layout tab's help on one
  line and its header one strip; Layout: the panes titled by
  monitor, flip, a refused then a good ratio, apply, Ctrl+S, `t` cycling
  tiles → scroll half → scroll full → tiles (drawn as the filmstrip), `r`
  refused on a scroll branch, l moving a column, `a`, `x` and `f` doing
  nothing, `d` reverting, Ctrl+S applying a draft, `]`
  and `3` switching the workspace, `-` setting the default trees (another
  workspace then shows them), the view opening on All workspaces (first in
  the strip, workspace 3 dotted), an edit on a workspace using the shared
  tree asking `Apply to (a)ll workspaces or (o)nly workspace N?`, `a`
  applying it to the shared tree and `o` giving workspace 5 its own (dotted
  then), `u` dropping it again; its slot list (`s`, no Slots tab): a
  refused then a good rename, a new slot in every tree at once, Return
  selecting a slot in the picture, delete, describe, Esc back; Desk: fork
  (the active desk on the copy, the other desk on the original), apply on
  a layout row and on a desk row, a
  refused screen-count mismatch, rename a desk and a layout, Ctrl+S
  (slots.lua holds the forks, the renames and the new pointers), delete a
  layout with remap, a refused delete of a used one, delete a desk, `p`
  doing nothing, a refused screen count of 0; then the Layout tab following the
  active layout; the bar widget on a stand-in bar strip (a `PluginBarApi`
  whose shell is a replacement bar's facade: it toggles the panel, has no
  `serviceFor`): its label and the
  unsaved dot, the menu's Save and Re-apply, left clicks opening and
  closing the panel, Record opening the record preview, and the error
  state while the `hyprslots` global is gone; then by mouse alone: the
  tabs and a workspace clicked, a row clicked, the toolbar's `a`, a chip
  assigning, the toolbar's `u` and Yes unassigning, a dim toolbar button
  doing nothing, a double-click on a row opening `a` and Cancel closing it,
  a slot clicked in the slot list, the toolbar's `e` and OK, a double-click
  showing the slot in the picture, a tile clicked, a double-click on a desk
  row asking for its layout, the toolbar's Ctrl+S saving and `q` closing;
  screenshots `26-mouse-toolbar-hover` to `31-mouse-desk-chips`; the
  Layout picture's dividers dragged, `32` to `34`; and Assignment rows
  dragged (`mouse_drops`, `smoke_drag` from a row, `smoke assignmentDrag`
  reading the held drag): an unassigned window onto an empty slot assigned
  with its spec, on to main moving there with t-main giving main up and the slot it left
empty again (its spec cleared, the message saying so), let
  go on its own slot doing nothing, onto the other windows unassigned with
  the spec, an unassigned one let go there doing nothing, Esc mid-drag and
  a drop outside the list cancelling, Ctrl+S saving a last drop; the
unassign after the move naming main, the slot it was in;
  screenshots of the slot rows' mini-maps, `35-assignment-minimaps` (tiled)
  and `35b-assignment-minimaps-scroll`, and mid-drag, `36-mouse-drag-assign`
  and `37-mouse-drag-unassign`), and writes screenshots to
  `.e2e-tmp/editor-smoke-*.png` (the Layout tab on tiles, scroll half and
  scroll full: `8a-layout-tiles`, `8b-layout-scroll-half`,
  `8c-layout-scroll-full`). `e2e/editor_first_run.sh` (also `make
  e2e-editor`) starts from no config dir at all: the starter files written,
  zero slots, a desk made; the bar's set-up state; the panel opening on the
  Layout tab's explanation, the Assignment tab's button back to it, the
  Desk tab; "Create your first slot" clicked with the real pointer, the
  prompt answered, the picture showing the slot and the next-step line, the
  bar's set-up state gone; Ctrl+S saving it with config.lua untouched; the
  panel then opening on the Assignment tab with its how-to-assign line, gone
  once the window is assigned (screenshots
  `.e2e-tmp/editor-first-run[-<theme>]-*.png`). `e2e/editor_desk_map.sh` (also `make e2e-editor`): two outputs of
  different sizes, offset (HEADLESS-2 1920x1080 at 0,360, HEADLESS-3
  2560x1440 at 1920,0), desks dual, solo and a never-seen office: dual's
  geometry in slots.lua at once, not dirty; the Desk tab's maps as drawn
  (dual's two screens side by side, the second larger and higher, office's
  equal and outlined), the tip on hover by the real pointer; after
  HEADLESS-3 is removed, solo active and dual's screen 2 outlined where it
  was recorded (screenshots `.e2e-tmp/editor-desk-map[-<theme>]-*.png`).
  `e2e/editor_screen_swap.sh` (also `make e2e-editor`): two outputs, layout
  dual shared with a never-connected desk, workspace 3 tiles on screen 1
  and `scroll:0.5[...]` on screen 2; screen 1's pane dragged by its title
  with the real pointer: over itself nothing, Esc while held nothing (the
  panel open), held over screen 2 its pane outlined, the ghost and `Swap
  with screen 2` (a screenshot mid-drag), let go the drafts swapped and the
  message naming the sharing desk; `w` moving the windows between the
  monitors (workspace 3 scrolling, 13 on lua:slots), Ctrl+S saving it; `p`
  swapping back and `w` moving them back; `p` on a workspace using the
  shared trees asking first (screenshots
  `.e2e-tmp/editor-screen-swap[-<theme>]-*.png`).
  `make e2e-editor-multimon`
  (`e2e/editor_multimon.sh`, opt-in, the same tools) looks rather than
  tests: the editor on a 2-screen desk (HEADLESS-2 and a 2560x1440
  HEADLESS-3, layout `dual` with slots on both screens, foot windows in
  them), screenshotting the Assignment tab, the Layout tab (All
  workspaces, tiles with either pane active, scroll half and full) and the
  Desk tab into `$MULTIMON_SHOTS` (default `.e2e-tmp/multimon/latest`);
  nothing is applied or saved.

### Completion test

`e2e/workspace_across_screens_test.sh`: outputs HEADLESS-2 (2400x1350 at
0,0, Omarchy block 0) and HEADLESS-3 (1920x1080 at 2400,0, block 1), matched
by connector; desks `dual` (both) and `single` (HEADLESS-2) on layouts
`dual` and `single` as in §4; slots `left`, `main`, `right` matched to
classes `t-left`, `t-main`, `t-right`.

1. The three windows open on workspace 1 in shuffled order; workspace 3 is
   activated with `hyprslots.api.call("workspace", '{"workspace":3}')`.
2. Both outputs show their workspace 3 (3 on screen 1, 13 on screen 2);
   `t-left` fills screen 2; `t-main` and `t-right` split screen 1
   horizontally 2:1 (1600 + 800 px, ±1 px).
3. HEADLESS-3 is removed (`hyprctl output remove HEADLESS-3`): desk
   `single` and its layout apply and all three tile 1:1:1 (800 px each) on
   workspace 3.

Desks and layouts besides: `e2e/shared_layout_test.sh` (two desks of one
monitor each on one layout: an edit made on one shows on the other after
the monitors swap, and the set the swap passes through gets no desk) and
`e2e/disabled_screen_test.sh` (hyprmoncfg-style: the left screen turned off
by a config reload leaves the right one block 0, every window under its own
number in 1–9 and the slot assignments kept; turned on again, left shows
1–9 and right 11–19 once more), `e2e/stranded_screen_test.sh` (the only
monitor turned off keeps its workspaces out of sight; the monitor that
comes up next gets them under their numbers), `spec/blocks_spec.lua` (S3,
the renumbering plan) and `spec/omarchy_blocks_spec.lua` (S2, against
Omarchy's real `monitor-workspaces.lua`: the live case, the panel off and
on, hyprslots refused, no desk),
`e2e/new_desk_test.sh` (a monitor set no desk knows gets a desk and a
default layout, saved to slots.lua by `save`; the next unknown set of as
many monitors reuses that layout, the most recently used, not the first by
name).

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
