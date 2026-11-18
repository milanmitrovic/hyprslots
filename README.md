# hyprslots

**Name your slots once — every app finds its place on every workspace, on every screen, at every desk you plug into.**

![The hyprslots editor: the Layout tab on a two-screen desk](preview.png)

hyprslots is a layout plugin for [Omarchy](https://omarchy.org) on Hyprland.
You name a few **slots** (say `left`, `main`, `chat`) and arrange them on your
screens as exact split trees; then you say which app fills which slot on each
workspace. From then on:

- an app you open goes straight into its slot, at its size, on its workspace;
- **Super+1..9** switch workspace N on every screen at once, each screen
  showing its part of the same arrangement;
- plug in a monitor (or leave the dock) and hyprslots picks the **desk** for
  the monitors now connected and the **layout** it uses, and puts every
  window back where that layout says;
- Omarchy's resize keys resize the slots (Super+L takes a workspace out
  of slots; see [Super+L](#superl) for bringing it back);
- **capture**: arrange your windows by hand, then capture them, and each
  one becomes a slot (named after its app) in the arrangement you made;
- **launch missing apps**: a workspace can open the apps its empty slots
  wait for, on demand or at login (never by default).

Everything is set up in an editor in Omarchy's shell, with a bar widget: the
**Layout** tab (slots and how they split each screen), the **Assignment**
tab (which window fills which slot) and the **Desk** tab (your monitor setups
and their layouts). The engine itself is Lua running inside Hyprland; there
is no daemon.

## Requirements

- **Omarchy 4.5** or later (its shell hosts the editor and the bar widget;
  hyprslots loads through its `~/.local/state/omarchy/workspace-layouts`
  folder).
- **Hyprland 0.56** or later with its **Lua config** (`hyprland.lua`), as
  Omarchy 4.5 sets it up. Your `hyprland.lua` must still require
  `default.hypr.toggles`, as Omarchy's own does.
- If you use **hyprmoncfg**, set its **workspace planner to Off** (in every
  profile). The planner replaces Omarchy's per-monitor workspace blocks
  with global workspace numbers, which is the model hyprslots builds on
  (workspace N is workspace N in each screen's block); while it is on,
  hyprslots stays off and says so. hyprmoncfg keeps managing your monitors'
  modes and positions.

## Install

1. Add the plugin (Omarchy clones it into
   `~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots`, enables it
   and puts its widget on the bar, on the right by default):

   ```sh
   omarchy plugin add https://github.com/milanmitrovic/hyprslots --enable
   ```

2. Enable the engine. Click the bar widget (it shows **enable**): the editor
   asks **Enable the hyprslots engine?** and says what that does. **Enable**
   adds one file, `zz-hyprslots.lua`, to Omarchy's workspace-layouts folder
   (`~/.local/state/omarchy/workspace-layouts`), which Omarchy loads with its
   own saved workspace layouts on every Hyprland config load, and reloads
   Hyprland. Your Hyprland config is not edited. Two choices sit under it:
   **Add hyprslots to the Omarchy menu** (on: three entries under
   Trigger, *hyprslots: Open editor*, *Capture this workspace* and *Launch
   missing apps*, added to your `~/.config/omarchy/extensions/omarchy-menu.jsonc`
   between marker lines) and **Also bind Super+Ctrl+Y to open the editor
   and Super+Ctrl+Shift+C to capture** (off; each key only where it is
   free, bound by the engine, not in your `bindings.lua`). Or, from a
   terminal:

   ```sh
   ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/install-engine.sh --menu --keys
   ```

   Nothing is written until you do one of these.

3. Make your slots. On its first start hyprslots writes
   `~/.config/hyprslots/config.lua` (yours: commented, real Lua) and an empty
   `slots.lua` (the editor's), and the bar widget shows **set up**. Click it:
   the editor opens on the **Layout** tab. Quickest: arrange your windows on
   a workspace the way you like them and **Capture my windows** (`c`): each
   window becomes a slot named after its app, the arrangement its layout
   (a preview first, then `y`). Or **Create your first slot** (a name
   such as `main`), add more (`s`, then `a`) and arrange them on your screens.
   Then, in the **Assignment** tab, select a window and press `a` to put it
   into a slot (or drag its row onto the slot's row): from now on that app
   opens there on that workspace. **Ctrl+S** saves.

The bar widget's place: `omarchy bar put io.github.milanmitrovic.hyprslots`
(`--after <widget id>`, or `omarchy bar move`; see `omarchy bar --help`).
Keys and menu entries later: run `tools/install-engine.sh --keys` or
`--menu` again (`--no-keys`, `--no-menu` take them away); or a key of your
own in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + Y", "Hyprslots", { panel = "io.github.milanmitrovic.hyprslots" })
```

## Using it

- **Layout tab**: one picture per screen of the active desk. Pick *All
  workspaces* (the trees every workspace shares) or one workspace (its own
  trees, where it differs). Drag a divider to change a split, drag a slot
  onto another to swap them, drag a screen by its title to swap screens;
  `t` turns a screen into a scrolling strip of columns. The slot list beside
  the picture makes, renames and deletes slots.
- **Assignment tab**: the windows on a workspace and the slot each one is
  in. `a` (or a drag onto a slot) assigns, `u` unassigns. An assignment is a
  spec such as `kitty` or `firefox/Mail` (class, optionally a title match).
  `m` sets whether the workspace launches its missing apps (never, on
  demand, at login) and `L` launches them now, each onto its workspace
  and into its slot, never one already open. An app's command comes from
  its desktop entry; a title spec (`ghostty/deltaf`) needs one of yours in
  `config.lua`: `launch_commands = { ["ghostty/deltaf"] = "ghostty
  --working-directory ~/Projects/deltaf" }`.
- **Capture** (`c` in the Layout and Assignment tabs, the bar's menu, the
  Omarchy menu, Super+Ctrl+Shift+C): the windows of a workspace, on every
  screen, become slots and their arrangement the layout, for that
  workspace or all of them; previewed, then an unsaved edit like any.
- **Desk tab**: every monitor setup hyprslots has seen, drawn to scale, and
  the layout each uses. Two desks can share a layout (docked at home and at
  the office, say); fork one to change it for that desk only.
- The **bar widget** names the active layout; a dot means unsaved edits.
  Right-click it to re-apply the layout, capture or record the windows on
  a workspace as its layout, save, or reload the config.

### Super+L

Omarchy's Super+L (and Super+Alt+L) cycles the focused workspace through
tiling, scrolling and floating, and knows nothing of slots: the first press
takes a hyprslots workspace out of slots, and the cycle never comes back to
them. Every mode but Omarchy's default is saved in
`~/.local/state/omarchy/workspace-layouts/<N>.lua`, and hyprslots leaves a
workspace with a saved mode alone, so your choice outlasts reloads. To bring
slots back to workspace N:

1. Press Super+L until the workspace is in Omarchy's default layout (tiling,
   unless you changed it), which removes its saved mode, or delete the file
   yourself: `rm ~/.local/state/omarchy/workspace-layouts/<N>.lua`.
2. Reload Hyprland (`hyprctl reload`): hyprslots gives the workspace its
   slots again.

`contrib/super-l/` has patches that add a slots stop to a customized cycle
script (slots, tiling, side-by-side, full width, floating, slots). They
patch the author's own scripts, which stock Omarchy does not have, so they
are not installed and serve only as a starting point for your own cycle;
docs/design.md §6 describes what a slots stop has to do.

`~/.config/hyprslots/config.lua` is plain Lua and wins over the editor for
whatever it sets. docs/design.md describes everything in detail.

## Removal

1. Disable the engine: this removes `zz-hyprslots.lua` (and with it the
   editor's keys) and hyprslots' Omarchy menu entries, and reloads Hyprland,
   which brings back Omarchy's own Super+1..9 and resize keys.

   ```sh
   ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/uninstall-engine.sh
   ```

2. Remove the plugin (the editor and the bar widget):

   ```sh
   omarchy plugin remove io.github.milanmitrovic.hyprslots
   ```

   Removing the plugin first is fine too: the loader then finds no plugin at
   the next config load and removes itself and the menu entries.

3. Optionally, your configuration: `rm -r ~/.config/hyprslots`.

## Development

```sh
make test          # Lua specs (busted), the editor's JavaScript (node) and QML (qmltestrunner)
make editor-lint   # qmllint over the editor
make e2e           # end to end, each test in its own nested Hyprland
make e2e-editor    # the editor in Quickshell on a nested Hyprland
```

The tests need busted (`luarocks --local --lua-version 5.4 install busted`),
node, Qt 6's qmltestrunner (skipped where missing), and, for the end-to-end ones, sway, foot, jq, gcc, qs, grim and wtype.
`make test` fails without node, and its editor tests that check the JavaScript
against the engine's Lua fail without a Lua interpreter; `make editor-test`
alone skips them, saying so.
For a development install, link the plugin folder to your checkout
(`ln -s ~/src/hyprslots ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots`)
and run `tools/install-engine.sh`; `omarchy plugin update` does not update a
linked plugin.

## License

MIT, see [LICENSE](LICENSE).
