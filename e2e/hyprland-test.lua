-- Hyprland config for the e2e harness. run.sh starts Hyprland with
--   -c e2e/hyprland-test.lua
-- and these environment variables:
--   XDG_CONFIG_HOME  per-test temp dir holding hyprslots/config.lua,
--                    omarchy/plugins/io.github.milanmitrovic.hyprslots (the
--                    plugin: run.sh links it to the worktree) and,
--                    optionally, hypr/test-extra.lua (per-test monitor rules)
--   XDG_STATE_HOME   per-test temp dir (Omarchy's monitor-workspace blocks,
--                    and its workspace-layouts folder with hyprslots' loader
--                    in it, which run.sh puts there)

local config_home = assert(os.getenv("XDG_CONFIG_HOME"), "XDG_CONFIG_HOME is not set")
local omarchy = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"

-- Only Omarchy's own modules: nothing from the user's ~/.config is reachable.
package.path = omarchy .. "/?.lua;" .. package.path

-- The minimum of Omarchy that defines `o.workspaces`: helpers creates `o`,
-- monitor-workspaces gives every monitor its block of ten workspaces.
require("default.hypr.helpers")
require("default.hypr.monitor-workspaces")

hl.config({
  general = { gaps_in = 0, gaps_out = 0, border_size = 0, layout = "dwindle" },
  decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
  animations = { enabled = false },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  xwayland = { enabled = false },
  debug = { disable_logs = false },
})

-- The window the Wayland backend opens on the sway host is not one of the
-- screens under test; tests create their own headless outputs.
hl.monitor({ output = "WAYLAND-1", disabled = true })

local extra = config_home .. "/hypr/test-extra.lua"
local file = io.open(extra, "r")
if file then
  file:close()
  dofile(extra)
end

-- Load hyprslots the way an installed one loads: Omarchy requires every file
-- in its workspace-layouts folder ($XDG_STATE_HOME/omarchy/workspace-layouts,
-- saved workspace modes and hyprslots' loader, tools/loader.lua), last in
-- the config as from default.hypr.toggles. The loader keeps a failure in
-- `hyprslots_load_error`, so the harness still comes up and the test
-- reports it.
require("default.hypr.workspace-layouts")
