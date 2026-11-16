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
- Omarchy's resize keys resize the slots, and Super+L still cycles a
  workspace out of slots and back.

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
   Hyprland. Your Hyprland config is not edited. Or, from a terminal:

   ```sh
   ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/install-engine.sh
   ```

   Nothing is written until you do one of these.

3. Make your slots. On its first start hyprslots writes
   `~/.config/hyprslots/config.lua` (yours: commented, real Lua) and an empty
   `slots.lua` (the editor's), and the bar widget shows **set up**. Click it:
   the editor opens on the **Layout** tab. **Create your first slot** (a name
   such as `main`), add more (`s`, then `a`) and arrange them on your screens.
   Then, in the **Assignment** tab, select a window and press `a` to put it
   into a slot (or drag its row onto the slot's row): from now on that app
   opens there on that workspace. **Ctrl+S** saves.

The bar widget's place: `omarchy bar put io.github.milanmitrovic.hyprslots`
(`--after <widget id>`, or `omarchy bar move`; see `omarchy bar --help`). A
key for the editor, in `~/.config/hypr/bindings.lua` (any free key):

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
- **Desk tab**: every monitor setup hyprslots has seen, drawn to scale, and
  the layout each uses. Two desks can share a layout (docked at home and at
  the office, say); fork one to change it for that desk only.
- The **bar widget** names the active layout; a dot means unsaved edits.
  Right-click it to re-apply the layout, record the windows on a workspace
  as its layout, save, or reload the config.

`~/.config/hyprslots/config.lua` is plain Lua and wins over the editor for
whatever it sets. docs/design.md describes everything in detail.

## Removal

1. Disable the engine: this removes `zz-hyprslots.lua` and reloads Hyprland,
   which brings back Omarchy's own Super+1..9 and resize keys.

   ```sh
   ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/uninstall-engine.sh
   ```

2. Remove the plugin (the editor and the bar widget):

   ```sh
   omarchy plugin remove io.github.milanmitrovic.hyprslots
   ```

   Removing the plugin first is fine too: the loader then finds no plugin at
   the next config load and removes itself.

3. Optionally, your configuration: `rm -r ~/.config/hyprslots`.

## Development

```sh
make test          # Lua specs (busted) and the editor's JavaScript (node)
make editor-lint   # qmllint over the editor
make e2e           # end to end, each test in its own nested Hyprland
make e2e-editor    # the editor in Quickshell on a nested Hyprland
```

The tests need busted (`luarocks --local --lua-version 5.4 install busted`),
node, and, for the end-to-end ones, sway, foot, jq, gcc, qs, grim and wtype.
For a development install, link the plugin folder to your checkout
(`ln -s ~/src/hyprslots ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots`)
and run `tools/install-engine.sh`; `omarchy plugin update` does not update a
linked plugin.

## License

MIT, see [LICENSE](LICENSE).
