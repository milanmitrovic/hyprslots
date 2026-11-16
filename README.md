# hyprslots

Hyprland (0.56+, Lua config) layout plugin for Omarchy: named slots in exact split-ratio layout trees, spanning all connected screens; Super+N switches workspace N on every screen; apps routed into their slots. A **desk** is a monitor setup (picked by which monitors are connected) and uses a **layout**, a logical arrangement of its screens that several desks can share. Design: docs/design.md.

## Getting started

Needs Hyprland 0.56+ with its Lua config, on Omarchy (its shell hosts the
editor; hyprmoncfg's workspace planner, if you use it, Off).

1. Put the code where Hyprland can load it, and load it with
   `require("hypr.hyprslots")` in `~/.config/hypr/hyprland.lua`, right after
   `require("hypr.autostart")`:

   ```sh
   git clone https://github.com/milanmitrovic/hyprslots ~/.local/share/hyprslots
   ```

   ```lua
   -- ~/.config/hypr/hyprslots.lua
   local root = os.getenv("HOME") .. "/.local/share/hyprslots/lua"
   package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
   hyprslots = require("hyprslots")
   hyprslots.setup()
   hyprslots.bind_workspace_keys() -- Super+1..9 switch every screen at once (Super+0 too with workspaces = 10)
   hyprslots.bind_resize_keys()    -- Omarchy's resize keys work on slots
   ```

2. Add the editor to the shell, its icon to the bar, and a key for it
   (`~/.config/hypr/bindings.lua`):

   ```sh
   ln -s ~/.local/share/hyprslots/editor ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots
   omarchy-shell shell rescanPlugins
   omarchy plugin enable io.github.milanmitrovic.hyprslots
   omarchy bar put io.github.milanmitrovic.hyprslots   # placement: --after <widget id>, as omarchy bar --help says
   ```

   ```lua
   o.bind("SUPER + CTRL + Y", "Hyprslots", { panel = "io.github.milanmitrovic.hyprslots" })
   ```

3. Reload Hyprland (`hyprctl reload`). On its first start hyprslots writes
   `~/.config/hyprslots/config.lua` (yours: commented, real Lua) and an
   empty `slots.lua` (the editor's), and the bar shows **set up**.

4. Click it. The editor opens on the **Layout** tab: **Create your first
   slot** (a name such as `main`), add more (`s`, then `a`) and arrange them
   on your screens. Then, in the **Assignment** tab, select a window and
   press `a` to put it into a slot (or drag its row onto the slot's row;
   each slot row shows a small map of where the slot is on its screen):
   from now on that app opens there on that workspace. `Ctrl+S` saves.

The **Desk** tab lists your monitor setups (desks, made for you when you
plug in monitors hyprslots has not seen) and the layout each one uses.
