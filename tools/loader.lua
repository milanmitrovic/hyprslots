-- hyprslots engine loader, put here by hyprslots (its editor's Enable, or
-- tools/install-engine.sh) as zz-hyprslots.lua. Remove it with
-- tools/uninstall-engine.sh, or delete this file and run `hyprctl reload`.
--
-- Omarchy's default/hypr/workspace-layouts.lua requires every file in this
-- folder on each Hyprland config load, after Omarchy's defaults, the user's
-- bindings and its own saved workspace modes (default.lua, <N>.lua: "zz-"
-- sorts after them). This file loads the hyprslots engine from the Omarchy
-- plugin io.github.milanmitrovic.hyprslots, sets it up and rebinds Super+1..9
-- and the resize keys to it, and binds the editor's keys when installed with
-- them (install-engine.sh --keys). Everything runs under pcall: a failure shows a
-- notification and the rest of the config loads on. With the plugin removed
-- it does nothing, and removes itself.

local ID = "io.github.milanmitrovic.hyprslots"

-- The editor's keys, which install-engine.sh --keys writes on this line
-- (editor = open the editor, capture = capture this workspace), each only
-- where it was free; none by default.
local KEYS = {}

-- A variable that is set but empty means unset, as Omarchy's paths.lua reads it.
local function env_or(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local config_home = env_or("XDG_CONFIG_HOME", (os.getenv("HOME") or "") .. "/.config")
local plugin = config_home .. "/omarchy/plugins/" .. ID

-- Take hyprslots' entries out of the Omarchy menu (the lines between its
-- markers, which tools/menu-entries.sh wrote); the rest of the file is the
-- user's and stays as it is.
local function remove_menu_entries()
  local path = config_home .. "/omarchy/extensions/omarchy-menu.jsonc"
  local file = io.open(path, "r")
  if not file then
    return
  end
  local text = file:read("a")
  file:close()
  local kept, inside, found = {}, false, false
  for line in text:gmatch("([^\n]*)\n?") do
    if line:match("^%s*// >>> hyprslots") then
      inside, found = true, true
    elseif inside and line:match("^%s*// <<< hyprslots") then
      inside = false
    elseif not inside then
      kept[#kept + 1] = line
    end
  end
  if not found then
    return
  end
  local out = table.concat(kept, "\n"):gsub("\n*$", "\n")
  local tmp = path .. ".hyprslots-tmp"
  local w = io.open(tmp, "w")
  if w then
    w:write(out)
    w:close()
    os.rename(tmp, path)
  end
end

local folder = io.open(plugin, "r")
if not folder then
  -- The plugin is gone (`omarchy plugin remove`): so is hyprslots. Only the
  -- installed copy removes itself (and its Omarchy menu entries), never a
  -- file run from anywhere else.
  local source = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
  local self = source:match("^@(.*/zz%-hyprslots%.lua)$")
  if self then
    pcall(remove_menu_entries)
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
  if next(KEYS) ~= nil then
    hyprslots.bind_editor_keys(KEYS)
  end
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
