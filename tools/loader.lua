-- hyprslots engine loader, put here by hyprslots (its editor's Enable, or
-- tools/install-engine.sh) as zz-hyprslots.lua. Remove it with
-- tools/uninstall-engine.sh, or delete this file and run `hyprctl reload`.
--
-- Omarchy's default/hypr/workspace-layouts.lua requires every file in this
-- folder on each Hyprland config load, after Omarchy's defaults, the user's
-- bindings and its own saved workspace modes (default.lua, <N>.lua: "zz-"
-- sorts after them). This file loads the hyprslots engine from the Omarchy
-- plugin io.github.milanmitrovic.hyprslots, sets it up and rebinds Super+1..9
-- and the resize keys to it. Everything runs under pcall: a failure shows a
-- notification and the rest of the config loads on. With the plugin removed
-- it does nothing, and removes itself.

local ID = "io.github.milanmitrovic.hyprslots"

-- A variable that is set but empty means unset, as Omarchy's paths.lua reads it.
local function env_or(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local plugin = env_or("XDG_CONFIG_HOME", (os.getenv("HOME") or "") .. "/.config") .. "/omarchy/plugins/" .. ID

local folder = io.open(plugin, "r")
if not folder then
  -- The plugin is gone (`omarchy plugin remove`): so is hyprslots. Only the
  -- installed copy removes itself, never a file run from anywhere else.
  local source = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
  local self = source:match("^@(.*/zz%-hyprslots%.lua)$")
  if self then
    os.remove(self)
  end
  return
end
folder:close()

hyprslots_load_error = nil

local ok, err = pcall(function()
  local lua = plugin .. "/lua"
  if not package.path:find(lua .. "/?.lua;", 1, true) then
    package.path = lua .. "/?.lua;" .. lua .. "/?/init.lua;" .. package.path
  end
  if not package.searchpath("hyprslots", lua .. "/?.lua;" .. lua .. "/?/init.lua") then
    error("no engine in " .. plugin .. " (lua/hyprslots is missing)", 0)
  end
  hyprslots = require("hyprslots")
  hyprslots.setup()
  hyprslots.bind_workspace_keys()
  hyprslots.bind_resize_keys()
end)

if not ok then
  hyprslots = nil
  hyprslots_load_error = tostring(err)
  pcall(hl.notification.create, {
    text = "hyprslots failed to load: " .. tostring(err),
    timeout = 15000,
    icon = 3,
  })
end
