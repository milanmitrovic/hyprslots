# hyprslots design

Status: engine slices 1 to 6 and editor slices D1 to D3 (Assignment,
Layout, Slots, Arrangements) done and integrated on `feature/editor` (§11),
slots made global logical names with specs per desk;
slice 7, the cutover, done on the user's machine from that branch; the
accordion (a Hyprland group, with tabs) replaced by the scroll branch (§6)
after the cutover showed what aerolayout's laptop accordion is on
Hyprland. Targets Hyprland 0.56.2 (Lua config) on Omarchy 4.5.

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
  (`h[main:2, right:1]`); leaves are slots or the overflow leaf. A whole
  branch may instead be a scroll branch.
- **Slot**: a named leaf, a **global logical name** (`left`, `main`,
  `right`) defined once with an optional description, aerolayout's logical
  slots. Every desk's trees may place any slot; trees belong to the
  **arrangement** (where `main` sits and how big it is depends on which
  screens exist).
- **Spec**: the window matcher that fills a slot **on one desk** (desk 3's
  `main` is `kitty/deltaf`, desk 9's `main` is `kitty/tako`): `class`,
  `class/title-pattern`, `[Tag]` and `[Tag]/Profile` (grammar in §7a). A
  slot a desk has no spec for takes a window only by hand.
- **Scroll branch**: a screen's whole tree written `scroll[a, b, c]`: its
  slots are full-width columns of Hyprland's own scrolling layout, in that
  order (aerolayout's accordion: full-screen windows side by side, scrolled
  through). Slots only.
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
  slots = data.slots,                 -- slot name -> { description? }
  specs = data.specs,                 -- desk -> slot name -> spec
  arrangements = data.arrangements,   -- name -> { screens = {...}, desks = {...} }
  pinned = { "laptop" },              -- screen roles excluded from desk switching
  title_matching = { ... },           -- per-class title extraction (§7a)
}
```

```lua
-- slots.lua (data only)
return {
  slots = { left = {}, main = { description = "the editor" }, right = {} },
  specs = {
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

A tree or a spec may only name a slot defined under `slots`; anything else
is a config error with its path (`specs[3].mian: no slot 'mian' (define it
under slots)`). A slot's `description` is the editor's note (aerolayout's
logical slot description); the engine does not use it.

**The per-desk shape of before** (`slots = { [3] = { main = "kitty/deltaf"
} }`, `descriptions = { [3] = { main = "..." } }`) is still read
(`migrate.lua`, pure), both in a data file `load_data` hands config.lua and
in the table config.lua returns: every slot name some desk had becomes a
global slot, each desk's entries move under `specs` unchanged, and a slot's
descriptions move onto it (every different one, in desk order, joined with
"; "; one for a slot no desk has is dropped). The editor works on the new
shape and `save` writes it. A `config.lua` written for the old shape passes
`slots = data.slots` and nothing more, which would lose the specs, so it is
refused at load with what to add (`specs = data.specs`).

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
`hyprland.start` / `config.reloaded`, not at require time. While refused,
`hyprslots.desk(n)` (so Super+N) falls back to `o.workspaces.focus(n)`,
whatever that is then, so the keys never go dead; the api's `desk` call
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
scroll    := 'scroll' '[' slot (',' slot)* ']'          -- full-width scrolling columns
child     := node (':' weight)?                         -- weight: integer >= 1, default 1
```

`h`, `v` and `scroll` open a container only when `[` follows; otherwise they
are plain slot names. The root takes no weight. A slot appears at most once
per tree. A scroll branch is a screen's whole tree and holds slots only: a
split, `*` or weight inside it, or a `scroll[` below the root, is rejected
with its position, under the branch's config path. `a[...]`, the accordion
this replaced, is rejected with the `scroll[...]` that says the same thing.
`*` is the **overflow leaf** (`h[main:2, v[right, *]]`): it takes a weight
like any leaf and appears at most once per tree. `serialize.tree` writes the
same syntax back (weights of 1 left out), which is what `save` and `state`
use.

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

### Scroll branches

A screen whose tree is `scroll[a, b, c]` gets its desk workspace on
Hyprland's own `scrolling` layout instead of `lua:slots` (`scroll.lua`):
the user's full-width scrolling (Super+L's full-width stop, which the
user's laptop desks were on before the cutover), with hyprslots keeping
the columns in slot order, the windows with no slot in the branch after
them in the order they are in, and the columns that arrive full width.
Everything a scroll branch needs is a deferred pass (20 ms timer), never
work inside an event:

- **Order**, after a window opens or moves to a workspace, a workspace is
  shown (a desk switch included, even to the desk already showing), a
  re-route (hotplug, edits, reload) and Hyprland's start or config reload:
  `scroll.plan` (pure) lists the swaps that put the columns in order and
  Hyprland's `window.swap { window, target }` makes them. A swap keeps the
  focus, but Hyprland warps the cursor to the swapped window, so the pass
  sets `cursor:no_warps` around the swaps and puts it back (Hyprland still
  focuses the monitor under that point, so the focused monitor is put back
  too).
- **Widen**, on the focused workspace only (Hyprland's `colresize` acts on
  the focused workspace's focused window): when a column the pass has not
  widened before is there and is not the configured width (`scroll =
  { width = 0.99 }` in `config.lua`, the default 0.99 as the user's
  full-width stop), `colresize all <width>`, then `fit_into_view` so the
  focused column stays in view. A hidden workspace's new columns widen when
  it is shown. A focus change runs the widen step alone, so a column the
  user moved (`swapcol`) or resized stays put until the next arrival or
  desk switch. A window floated and tiled again by hand comes back in a new
  column at Hyprland's default width (the user's own full-width mode does
  the same); Super+L entering slots (api `arrange`) widens every column.

A workspace is **managed** only while its tiled layout is `scrolling` and
Omarchy has no saved mode for it (`$XDG_STATE_HOME/omarchy/workspace-layouts/<id>.lua`):
any Super+L stop saves one, and hyprslots then leaves the workspace's
columns alone until Super+L brings slots back, which removes it.

**Layout rules.** At load, desk N's workspace in every Omarchy block gets
`scrolling` where the arrangement selected then has a scroll branch and
`lua:slots` everywhere else; Omarchy's saved modes load afterwards and
win. When the arrangement or a tree changes later (hotplug, an edit, the
start check), each desk workspace whose layout should change gets the new
rule unless it has a saved mode, so Super+L's choice stands. `lua:slots`,
should it ever lay out a scroll branch, shows its columns side by side.

**Hyprland 0.56.2's scrolling layout** (`src/layout/algorithm/tiled/scrolling`,
verified in the nested harness): `scrolling.column_width` is one global
option and the scrolling workspace rule only takes `direction`, so full
width per workspace is `colresize` (the window rule `scrolling_width` sets a
window's width wherever it is inserted, on every workspace, so it cannot
make one desk full width). A new window's column goes right after the
focused column when the focused window is on that workspace, else last; a
window moved in goes last. `HL.Window.layout` reports a scrolling window's
`column = { index (0-based), width, windows }` and `index_in_column`,
which is how the pass reads the order. `swapcol`, `move` and `colresize`
layout messages act on the focused window only; `window.swap` trades two
windows' places (their targets) on any workspace, focus kept.

Rejected alternative: the accordion as a Hyprland group (slice 4). A group
draws a tabbed groupbar and is not what aerolayout's accordion is on the
laptop; the cutover ported the laptop desks as accordions and every one
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
tree overrides the branch per arrangement, desk and screen role, in memory
(`engine.resized["<arrangement>/<desk>/<role>"]`): it survives hotplug back
to the same arrangement but not a config reload. `resize.effective_branch`
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

- The cycle acts on the focused workspace only. On a hyprslots desk
  workspace (one in `hyprslots.api.call("state").workspaces`) it gains a
  slots stop between floating and tiling:
  slots → tiling → side-by-side → full-width → floating → slots
  (`back` reverses). Elsewhere it is unchanged. The slots stop is the layout
  hyprslots gives the desk (`state.workspaces[id].layout`): `lua:slots`, or
  `scrolling` for a scroll branch, whose columns hyprslots keeps full width
  and in slot order (§6); its full-width stop is the user's own, which
  hyprslots leaves alone.
- Omarchy's mode files know nothing of slots, so "slots" is read from the
  workspace's `tiledLayout` unless the mode file says floating (floating
  keeps the tiled layout underneath): `lua:slots`, or, on a scroll desk,
  `scrolling` with no mode file of its own.
- Entering slots from floating first applies `dwindle` through
  `o.workspace_mode` to tile the windows again, then sets the desk's layout
  as a workspace rule, removes the workspace's mode file (and its
  full-width mark), so the rule hyprslots sets at load brings slots back
  after a reload, and on a scroll desk calls api `arrange`, which orders
  and widens its columns at once. Leaving slots applies the mode and saves
  it, even Omarchy's default, so the desk stays out of slots across reloads
  until Super+L enters slots again.
- The bar widget shows a grid glyph (nf-md-view_grid) and "Slots"
  (`workspace-layout-current` says `slots` for both kinds).

Verified at cutover: a saved mode file for a desk workspace wins over
hyprslots' load-time rule. Omarchy loads the saved modes from
`default.hypr.toggles`, after the user's requires (hyprslots included), and
each calls `hl.workspace_rule` with its layout. So leaving slots for a mode
keeps that mode across reloads until Super+L enters slots again (which
removes the file), and Omarchy's default-layout command, which saves busy
workspaces' current mode, takes those desks out of slots too. The cutover
removed the saved modes of the desk workspaces (1, 3, 4, 5, 6, 9) and their
full-width marks. A config reload re-applies the rule to existing
workspaces. The scroll fix (§11) put the laptop desks (1 to 9) back in
slots the same way, now on the scrolling layout, so Super+L's full-width
stop and hyprslots' slots stop look alike there: slots also orders.

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
  window's class, whatever its title says now. An assignment made by hand
  (the editor's `assign`, §9) is kept while the slot exists.
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
  trying the desks that have specs in ascending order and, within a desk,
  slots by name. So when
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
re-route is done it asks for the scroll pass (§6), so scroll columns are
put in order on the workspaces the windows now sit on. Keyboard-resized trees are
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

### The plugin

`editor/` is the plugin folder (manifest `kinds: ["panel", "service", "bar-widget"]`):

| File | Role |
|---|---|
| `Engine.qml` | the service: runs the api through `hyprctl repl` (one `Process` per command, in order, 3 s watchdog), reads `state` debounced (60 ms) on `custom>>hyprslots changed` and on window events (`openwindow`, `closewindow`, `movewindowv2`, `windowtitlev2`, monitor events, `configreloaded`) via `Quickshell.Hyprland`'s `rawEvent`, only while someone follows it (`active`: the panel is open; `watchers`: bar widgets, from `watch()` / `unwatch()`); keeps `error` (last state read) and `lastError` (last call); `busy` while a call runs or the re-read after it is pending |
| `Panel.qml` | the panel: an `OverlayWindow` card (`qs.Ui`), themed through `qs.Commons` (`Color.menu.*`, `Style`) like Omarchy's own panels; tabs Assignment, Layout, Slots, Arrangements (Tab / Shift+Tab), Ctrl+S saves, Esc or q closes; `press(key)` feeds a key by name (`Ctrl+s` with the modifier) |
| `BarWidget.qml` | the bar widget (below): glyph, arrangement and desk; left click toggles the panel, right click a menu |
| `AssignmentView.qml`, `LayoutView.qml`, `SlotsView.qml`, `ArrangementsView.qml` | aerolayout's Assignment, Layout, logical slots and monitors views (below) |
| `Protocol.js`, `Assignment.js`, `Layout.js`, `Slots.js`, `Arrangements.js`, `Prompts.js`, `BarStatus.js` | pure logic, tested under node (`editor/tests/`) |

**Every view.** The panel's keys come first: Tab / Shift+Tab cycle the
tabs (Assignment, Layout, Slots, Arrangements), **Ctrl+S saves** (api
`save`, in every tab; the Layout tab applies its edited panes first), Esc
or q closes. The outcome of every call shows on the view's message line, a
failure (`{ok:false,error}`, hyprctl failing, hyprslots not loaded, the
engine off, a config error) in the urgent colour. Edits go to the engine as
they are made and stay in memory until saved; a header says so ("unsaved
edits", `● unsaved (Ctrl+S)` in the Layout view).

**Prompts** (`Prompts.js`, one implementation for every view): a line of
text typed in place (←/→ Home End move, Backspace Delete, Ctrl+U clears,
↑/↓ step through suggestions, Return answers), a pick among keyed options
(first letter, else the first free digit; ↑/↓ and Return), or y/n. While
one is open every key is its own (Tab, q, Esc and Ctrl+S included); Esc
cancels. When an answer is refused (by the engine: the spec grammar,
config.lua's validation, a field config.lua owns; or, for a Layout ratio,
by the ratio grammar) the prompt opens again with the answer kept and the
refusal under it.

**Assignment view** (aerolayout `views.py` AssignmentView). Pages: every
window, then each desk; it opens on the focused workspace's desk. A desk's
table lists its slots in tree order, screen role by screen role of the
active arrangement (then slots no tree shows): the window in each, or a
`Missing` row with the spec it waits for; then the windows overflowing on
the desk and any other windows on its workspaces. A desk's slots are the
ones its trees place and the ones it has a spec for; a slot with no spec
on the desk shows `Missing` with `(no spec)`. Columns: Desk (every-window
page), Screen (when more than one), Slot (`main`, `main (by hand)`,
`overflow (main)`, `unassigned`, `—`), App (a Missing row's spec), Title.
This is where each desk's specs are set: there is no desk × slot table.

| Key | Does |
|---|---|
| ↑/↓, k/j | select |
| ←/→, h/l (p) | previous / next page |
| a | `Assign to desk 3 slot (takes its spec): (m)ain, (r)ight, (1) more? [Esc] cancel`: every global slot, the desk's own first; then `take_spec`: the window takes the slot and its spec (`spec.from_window`) becomes the desk's for it, replacing the one it had |
| c | `Clear desk 3's spec for main (kitty/deltaf)? (y/n)`, then `clear_spec` |
| u | `Unassign … from … slot? (y/n)`, then `unassign` |

As aerolayout's `a` did, `a` writes the window's spec into the slot (in
memory until Ctrl+S, the header saying "unsaved edits"). On the
every-window page it acts on the window's desk, else the focused
workspace's. aerolayout's `n` (name a workspace) has no counterpart: desks
have no names.

**Layout view** (aerolayout `views.py` LayoutView, `tree_visualizer.py`).
One desk of one arrangement at a time; it opens on the active arrangement
at the focused workspace's desk and screen, and moves to the running
arrangement (same desk) when the one it edits is renamed or deleted in the
Arrangements view. A pane per screen role, side by side, each a scale model
of its monitor (its aspect from Hyprland, else 16:9): leaves are boxes
proportional to their weights (tree.lua's integer arithmetic) with the slot
name, `×n` for a share other than 1, and the title of the window in the
slot; a nested split is a box titled with its kind and ratio (`h 1:3`); a
scroll branch is a filmstrip: its columns side by side in equal frames,
numbered in order (no tabs: each frame stands for a full-width column of
the screen); the overflow leaf is `* overflow`. Under each pane its tree
text and ratio string (and `overflow parked` when the tree has no `*`, or
that windows with no slot go after a scroll branch's columns); under the
panes the leaf order once the tree nests, or a scroll branch's column
order. Edits go to a **draft**
per pane (`edited` on the pane, `edited, not applied (w)` in the header).

| Key | Does |
|---|---|
| ←↑↓→ | select the leaf that way; off a pane's left/right edge, the next screen's |
| h j k l | swap the leaf with its neighbour in its container; off the edge, move it to the next screen's tree |
| H J K L | along its container: pair it with its neighbour in a new container across; across: move it out beside its container |
| a | add a global slot no pane of the desk places yet, after the selected leaf (or as the tree of a screen that has none) |
| x | take the selected slot out of the tree (it stays a slot) |
| / | flip every split of the tree |
| t | make the whole tree a scroll branch of its slots in reading order (the overflow leaf has no place in one), or back to the tree it was made from while its columns are as they were, else its columns side by side |
| r | prompt for the whole tree's ratio (grammar below; the current one shown, empty clears all) |
| o | park the overflow leaf (the engine then gives it a column at the right) or put it back where it was; refused on a scroll branch |
| w | apply the edited panes (`set_trees`) |
| Ctrl+S | apply the edited panes, then `save` (the panel's key) |
| d | after y/n, put the pane's tree back to slots.lua (`reset`) |
| R | `record` the pane's workspace (active arrangement only), show the tree, its ratio and what it would drop (`missing`), apply after y/n |
| g / c | pick the desk / the arrangement to edit |

A read-only arrangement, a config without slots.lua, or the engine being
off shows `Read only: <why>` and refuses the editing keys. Layout.js
mirrors tree.lua's text and ratio.lua's grammar (a node test runs the same
corpus through the Lua modules), so a draft is checked and shown without a
round trip; the engine validates again on apply. Deviations from
aerolayout: edits are a draft applied with `w` (aerolayout saved on every
keystroke); `d` resets one screen to slots.lua (aerolayout's `d` dropped a
workspace's own tree for the arrangement default, which hyprslots does not
have); `g` picks a desk and `c` an arrangement (aerolayout's `g` picked a
workspace or "all", and arrangements were the Monitors tab's); `R` always
previews and asks; a parked overflow leaf is remembered only while the
panel is open (aerolayout kept it hidden in the saved tree); a scroll
branch's columns are a row, so h / l move a column (H J K L refuse: a
scroll branch holds slots only), and a leaf moved onto a screen whose tree
is one becomes its column at the near edge.

**Slots view** (aerolayout `views.py` LogicalView). The global slots, one
list for every desk, by name (the order windows claim them in): Slot,
Description, Placed by (every `arrangement/desk/role` whose tree places
it), Filled on desk (each desk's spec for it); under the table, the
selected slot's specs. Which app fills a slot on a desk is the Assignment
view's `a`.

| Key | Does |
|---|---|
| ↑/↓, k/j | select |
| a | add a slot: name, description (`add_slot`) |
| r, Return | rename it everywhere: every tree of every desk and arrangement, every desk's spec, keyboard-resized trees and assignments, as aerolayout's rename_slot_everywhere (`rename_slot`) |
| e | describe it (`describe_slot`) |
| d | delete it, after y/n naming every tree and desk it goes from (`remove_slot`, with `force` when something uses it) |

A slot list config.lua builds in code says so and takes no edit. No
reorder (aerolayout's J/K): slots claim windows by name, so their order is
not the editor's to set.

**Arrangements view** (aerolayout MonitorsView). A header names the
connected monitors and what they run; the arrangements are listed by name
with their screen count, `● in use here` on the running one, dim when
these monitors could not run it, `(set in config.lua)` when read-only;
below, the highlighted one's screens (role, selector, the monitor it finds,
pinned) and the connected monitors with their description and serial.
hyprslots picks the arrangement itself (the one whose screens are exactly
the connected monitors, §8), so aerolayout's "map these monitors to this
arrangement" becomes "point this arrangement's screens at these monitors".

| Key | Does |
|---|---|
| ↑/↓ | select |
| a | use on these monitors: a monitor for each role, when the counts agree (`set_screens`) |
| n | new: a name, then a role for each connected monitor (suggested from what the running arrangement calls it, else `laptop` for eDP, else `screenN`), each selected by its description, else its serial, else its connector, then its trees: the default (the slots each desk has a spec for side by side on the first role), none, or another arrangement's (roles of the same name map; others are asked) (`add_arrangement`) |
| r | rename (`rename_arrangement`) |
| x | delete, after y/n naming its desks; the running one too, after which these monitors run nothing (`delete_arrangement`) |
| e | edit a screen: role name, then selector (↑/↓ step through the monitors' descriptions, serials and connectors); a renamed role keeps its trees (`set_screens`) |
| + / - | add a screen / remove one, its trees with it (`set_screens`) |
| p | pin or unpin a role; pinned is one list for every arrangement (`set_pinned`) |
| c | copy trees from the default or another arrangement, after y/n (`copy_trees`) |

Every reply says what the monitors run afterwards: a new arrangement for
screens another one already names runs only when its name sorts first
(§8's tie rule), and the message says which one runs.

**Bar widget** (`BarWidget.qml`, model `BarStatus.js`). A grid glyph and
`<arrangement> · <desk>`: the active arrangement and the desk of the
workspace its bar's monitor shows (`state.workspaces`; `–` on a workspace
that is no desk, `none` when the monitors run no arrangement). It reads the
plugin's service (`bar.shell.serviceFor("milan.hyprslots")`, asked again
every 2 s while the service is not up yet) and calls its `watch()` so the
service follows change events while the panel is closed: one poller for
the panel and every widget instance. The desk follows workspace switches
from Quickshell's Hyprland objects, with no state read.

| State | Shows |
|---|---|
| normal | `󰕰 solo · 3` in the bar's foreground |
| unsaved edits (`dirty`) | `󰕰 solo · 3 •`, the tooltip says "unsaved edits" |
| error | the bar's urgent colour, the error first in the tooltip: the service missing, a state read failing (hyprctl, `hyprslots` not loaded: `󰕰 hyprslots` until a state was read, else the last one), `refused` (`󰕰 off`), `config_error` (the running config still shown) |

Left click toggles the panel (`shell.toggle`). Right click opens a menu
(Omarchy's `PopupCard`, laid out like the tray's menu; outside click
closes it):

| Entry | Does |
|---|---|
| Re-apply layout (desk N) | `desk {desk: N}` (the desk's Super+N: every screen of the arrangement shows it again, scroll branches back in slot order), then `arrange` (the scroll pass now, the focused scroll workspace's columns widened) |
| Record desk N… | opens the panel with `{"record": true}`: the Layout tab on the focused desk, its `R` flow (preview, then y/n) |
| Save | `save`; only with unsaved edits |
| Reload config | `reload` (drops unsaved edits; how a fixed config error is picked up) |

Re-apply and Record need the bar's screen on a desk of a running engine
(a config error leaves the last good config running); with the engine
off or unreachable only Reload is offered. Each call's outcome, or the
engine's error, is a notification (`notify-send` through `bar.run`).

**Install** (the user's machine; not done by the slices):

```sh
ln -s ~/.local/share/hyprslots/editor ~/.config/omarchy/plugins/milan.hyprslots
omarchy-shell shell rescanPlugins
omarchy plugin enable milan.hyprslots
omarchy-shell shell toggle milan.hyprslots       # open / close
omarchy bar put milan.hyprslots --after milan.layout   # the bar widget
```

(`omarchy bar put` writes the widget into `~/.config/omarchy/shell.json`'s
bar layout; `omarchy bar move` places it elsewhere. A widget whose plugin
was added after the shell started needs `omarchy-shell shell rescanPlugins`
first.)

and a key in `~/.config/hypr/bindings.lua`:
`o.bind("SUPER + CTRL + Y", "Hyprslots", { panel = "milan.hyprslots" })` (any free key;
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
close, a keyboard nudge or reset, and an arrangement change on hotplug. `seq` restarts at 0 when
Hyprland reloads its config (Lua state is discarded), so the editor treats
any event as "re-read state", not as an ordering.

| Call | Arguments | Reply (besides `ok`) |
|---|---|---|
| `state` | — | see below |
| `desk` | `desk` | `desk` |
| `set_tree` | `arrangement?` (default active), `desk`, `role`, `tree` | `arrangement, desk, role, tree, ratio, seq` |
| `set_ratio` | `arrangement?`, `desk`, `role`, `ratio` (grammar below) | same as `set_tree` |
| `set_trees` | `arrangement?`, `desk`, `trees` (role -> tree) | `arrangement, desk, trees` (role -> `tree, ratio`), `seq` |
| `reset` | `arrangement?`, `desk`, `role` | `arrangement, desk, role, tree?, ratio?, seq` |
| `record` | `workspace?` (default focused), `apply?` | `arrangement, desk, role, workspace, tree, ratio, missing[], applied, seq` |
| `assign` | `address`, `desk`, `slot` | `address, desk, slot, displaced?, seq` |
| `unassign` | `address` | `address, desk?, slot?, seq` |
| `add_slot` | `slot`, `description?` | `slot, description?, seq` |
| `remove_slot` | `slot`, `force?` | `slot, trees[]` (`arrangement/desk/role`), `specs[]` (desks), `seq`; refused, saying where, while trees place it or desks fill it, unless `force` |
| `rename_slot` | `slot`, `to` | `slot, to, trees` (how many were rewritten), `specs[]` (desks whose spec moved), `seq` |
| `describe_slot` | `slot`, `description` (`""` removes it) | `slot, description, seq` |
| `set_spec` | `desk`, `slot`, `spec` | `desk, slot, spec` (normalized), `seq` |
| `clear_spec` | `desk`, `slot` | `desk, slot, spec` (the one cleared), `seq` |
| `take_spec` | `desk`, `slot`, `address` | `desk, slot, spec, replaced?, address, displaced?, seq`: the window takes the slot and its spec becomes the desk's |
| `add_arrangement` | `name`, `screens` (role -> selector), `from?` + `roles?` or `default?` | `arrangement, screens, active, seq` |
| `rename_arrangement` | `arrangement`, `to` | `arrangement, to, active, seq` |
| `delete_arrangement` | `arrangement` | `arrangement, active, seq` |
| `set_screens` | `arrangement?`, `screens`, `renames?` (old role -> new) | `arrangement, screens, active, seq` |
| `set_pinned` | `pinned[]` | `pinned, seq` |
| `copy_trees` | `arrangement?`, `from` + `roles?` or `default: true` | `arrangement, from, seq` |
| `save` | — | `path, seq` |
| `reload` | — | `arrangement, seq` |
| `arrange` | — | `swaps, widened[]` (workspace ids): the scroll pass now, every column of the focused scroll workspace widened (Super+L entering slots) |

`state`: `seq`, `dirty` (unsaved edits, keyboard-resized trees included),
`arrangement` (active name), `screens` (role -> connector), `workspaces`
(id -> desk, role, monitor, `layout`: `lua:slots` or `scrolling`, what
hyprslots gives it), `assignments` (address -> desk, slot,
`manual` when made by `assign`),
`overflow` (address -> desk, slot: a window that matches that slot's spec
while every slot it matches is taken, laid out in that desk's overflow leaf), `unassigned[]` (addresses taken out of their slot by `unassign`),
`arrangements` (name -> `screens`, `roles[]`, `desks` ("3" -> role ->
`{tree, ratio, slots[], resized?}`), `active`, `read_only`), `monitors[]`
(`name, description, serial, focused`: what a screen selector can name),
`resized`
(`"<arrangement>/<desk>/<role>"` -> `arrangement, desk, role, tree, ratio`
for every unsaved keyboard-resized tree), `scroll[]` (one per scroll branch
on a desk workspace: `workspace, desk, role, slots[], layout` (its tiled
layout), `managed` (scrolling, no saved Omarchy mode), `columns[]` (window
addresses in column order), `members` (slot -> address), `in_order`),
`slots[]` (the global slots by name: `name, description?`), `specs` ("3" ->
slot -> spec text), `desks[]` (desks with specs or trees),
`pinned[]`, `windows[]` (`address, class, title, workspace, floating,
box{x,y,w,h}, desk?, slot?, overflow?{desk, slot}, unassigned?`), `config` (`dir, data_file, editable,
read_only[]`), `refused`, `config_error`, `log_seq`.

**Assignment by hand** (the Assignment view). `assign` puts an open
window into a slot of a desk whatever the slot's spec says, and moves it to
the slot's workspace. The window holding that slot is routed again as if it
had just opened (another free slot it matches, else its desk's overflow) and
is named as `displaced`; the slot the window left goes to the oldest window
overflowing on it. A hand-made assignment is sticky like any other, and
re-solves keep it while the slot exists, even though the spec does not
match. `unassign` takes a window out of its slot: it stays where it is (on a
desk workspace, in the overflow leaf), its slot goes to the oldest window
overflowing on it, and it takes no slot, by routing, late title, layout or
re-solve, until it is assigned again or closes. Both live in memory only
(neither touches `slots.lua`), survive `reload` and hotplug, and are lost on
a Hyprland config reload like every assignment. Both refuse a window that is
not open; `assign` refuses a slot that is not defined (any desk 1 to 10 may
take any global slot, spec or none).

**Taking a spec** (the Assignment view's `a`). `take_spec` makes the
window's spec (`spec.from_window`: `class`, `class/identifier` for a class
with title rules, `[Tag]` or `[Tag]/Profile` for a browser) the desk's spec
for the slot and puts the window there. The edit is checked (config.lua
re-run over it) before anything moves; then the window is assigned as by
`assign` (the holder displaced and routed again), the assignment is made an
ordinary one (the new spec names the window), and the edit is applied, so
the re-solve keeps that window in the slot over any older one the spec also
matches.

**Layout editing** (the Layout view). `set_trees` sets several of a
desk's trees in one edit, all or nothing: a slot sits on one screen of a
desk, so moving it to another screen cannot be two `set_tree` calls. Each
tree it sets replaces that branch's keyboard-resized override (kept when
the edit fails). `reset` puts one branch back to the tree slots.lua holds
on disk (read data-only, as saved, not as first loaded; no tree when the
file has none), dropping an unsaved edit and a keyboard-resized override
of it; other branches keep their edits, and the engine is clean again once
its data is the file's. The saved tree is read through the slot and
arrangement edits made since (below): the engine keeps the `rename_slot`,
`remove_slot`, `rename_arrangement`, `delete_arrangement` and `set_screens`
calls until its data is the file's again (save, reload, a reset back to
the file) and replays them over the saved data with `edit.lua`, so after
renaming slot `a` to `x` a reset gives back `h[x:2, b]`, not a tree naming
a slot the desk no longer has, and an arrangement or role renamed since
finds the tree saved under its old name.

**Slot, spec and arrangement edits** (the Slots, Assignment and
Arrangements views). Each builds new data with `edit.lua` (pure), re-runs
`config.lua` over it, and refuses the edit, changing nothing, when the
result does not validate or does not show the edit (a field `config.lua`
builds in code, or does not take from `slots.lua` at all: `set_pinned`
under a `config.lua` that never reads `pinned`). Otherwise it is applied
like `set_tree` (re-assign, re-route, window rules, relayout, change event)
and stays in memory until `save`. `rename_slot` rewrites the slot's name in
every tree of every desk in every arrangement, in every desk's specs, in
the keyboard-resized overrides, and in the assignments (a hand-made one
stays hand-made); `remove_slot` takes the slot out of those trees (a
container left with one child is replaced by it, a branch left empty goes)
and drops every desk's spec for it. `clear_spec` drops one desk's spec; the
slot and the trees stay. `rename_arrangement` / `delete_arrangement` /
`set_screens` move or drop the overrides they touch, and `copy_trees` drops
the target's. `set_screens` replaces the whole role -> selector map; a role
in `renames` keeps its trees, a role it drops loses them. `copy_trees` maps
each target role to `roles[role]` (default: the source role of the same
name) and replaces every tree of the target; `default` lays each desk's
slots it has a spec for side by side, by name, on the target's first role.
`active` in a reply is the arrangement running afterwards (the new one runs
only when it is the first by name to match the monitors). Arrangement names
hold no `/`.

**The tree in force** for a branch is `api.effective_branch`, which is
`resize.effective_branch`: a keyboard-resized override (§6) if there is
one, else the config's. `state` reports it, `set_ratio` starts from it,
`record` compares against it, `save` writes it.

Edits never write files: they re-run `config.lua` over the edited
`slots.lua` data in memory and take effect only when the result validates.
The new config is then applied like a hotplug: re-select, re-assign,
re-route every assigned window to its slot's workspace (a slot moved to
another screen role takes its open window along), scroll pass, relayout.
An edit to a branch replaces that branch's keyboard-resized override.
`save` writes `slots.lua` through `serialize` (temp file + rename), then
runs the saved data as the config and clears the overrides it wrote;
`reload` / `hyprslots.reload_config()` re-reads both files in place,
dropping unsaved edits and every override.

**Read-only fields.** A config field is the editor's only when `config.lua`
passes the data file's own table through (identity check, at the top level
and one level down). Anything built in code is listed in
`config.read_only` (`"pinned"`, `"arrangements.work"`, `"specs.4"`, and
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
slot order). A record that would drop a slot with no window, or the
overflow leaf, is returned with `missing` and not applied unless
`apply: true`.

**Relayout.** After an edit the engine sends a zero `hl.dsp.window.resize`
to one tiled window per desk workspace: a lua layout recalculates on any
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
| pure | `migrate` | slots.lua's per-desk shape of before, read as global slots and per-desk specs |
| pure | `edit` | edits to the `slots.lua` data (trees, slots, specs, arrangements); which fields code owns |
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
Omarchy's and the user's bindings, also calls `bind_desk_keys()` and
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
| 2 Desks | desks across screens, synced Super+N, pinned screens, hotplug; turns the completion test green | done |
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
saved tree through the Slots and Arrangements views' renames and removals,
and the Layout view following an arrangement renamed or deleted under it;
`e2e/editor_smoke.sh` drives all four views in one run.

Parked:

- mouse-resize workaround, and an upstream Hyprland PR for a resize hook;
- spanning windows;
- public release / AUR package;
- QML tests (the views' QML is covered only by the editor smoke; their
  logic is in the node-tested `.js` models);
- the Layout view's parked overflow leaf lives only while the panel is open
  (aerolayout kept it in the saved tree);
- slot reorder (aerolayout's J/K): slots claim windows by name;
- dropping the per-desk shape's migration once no slots.lua holds it.

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
  the service and adds an IPC target), drives the panel with real keys from
  one wtype session (a fresh virtual keyboard loses its first key, and a
  second wtype's keys did not arrive, so the sequence is one session starting
  with an ignored F13) and with `press()`, asserts through api `state`, the
  windows' geometry and the saved `slots.lua` (Assignment: assign by real
  keys, which takes the window's spec, unassign, clear the spec; Layout:
  flip, a refused then a good ratio, apply, Ctrl+S, t making a scroll branch
  and l moving a column, reset, Ctrl+S applying a draft; Slots: a refused
  then a good rename, add (the Layout tab's a places it, x takes it out),
  delete, describe; Arrangements: create from the
  connected screen, Ctrl+S, rename, a refused pin, copy the default trees,
  rename a role, delete; then the Layout tab following the running
  arrangement; the bar widget on a stand-in bar strip (a `PluginBarApi`
  whose shell finds the service and toggles the panel): its label and the
  unsaved dot, the menu's Save and Re-apply, left clicks opening and
  closing the panel, Record opening the record preview, and the error
  state while the `hyprslots` global is gone), and writes screenshots to `.e2e-tmp/editor-smoke-*.png`.

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
