-- The first start of a fresh install (docs/design.md §4, "First run"): with
-- no config.lua in the config dir, a starter config.lua that explains
-- hyprslots and passes slots.lua's data through to the engine, and an empty
-- slots.lua for the editor to fill. A file that is there is never written
-- over: the starter is written only where config.lua is missing, and
-- slots.lua only where it is missing too.

local serialize = require("hyprslots.serialize")

local M = {}

M.CONFIG = [[
-- hyprslots: config.lua
--
-- hyprslots lays out your windows in named places that span all your
-- screens. You name the places ("slots": left, main, right, as many as you
-- like), arrange them on your screens, and say which app goes into which
-- slot on each workspace. An app you open goes straight to its slot, and a
-- workspace switch shows that workspace on every screen at once.
--
-- Set it up in the editor (click hyprslots in the bar):
--   Layout      make your slots and arrange them on your screens
--   Assignment  select a window and press a to put it into a slot
--   Desk        your monitor setups and the layout each one uses
-- Ctrl+S saves.
--
-- Two files live here:
--   config.lua  this file. It is yours: hyprslots wrote it once, because
--               there was none, and never writes it again.
--   slots.lua   the editor's data: the slots, which app fills them, the
--               desks and the layouts. The editor rewrites it when you save,
--               so leave it to the editor; put your own changes here.
--
-- This file is Lua, run each time hyprslots loads its config, so it can
-- compute what it returns (examples at the end). It runs in a sandbox: the
-- string, table and math libraries, os.getenv, os.date and os.time,
-- hostname() and load_data(), but no io, os.execute or require. A field
-- you build in code instead of passing slots.lua's on is yours alone: the
-- editor shows it but does not change it.

local data = load_data("slots.lua")

return {
  -- What the editor edits, passed on as it is. Keep these lines: a field
  -- left out is lost, and one you replace is read only in the editor.
  slots = data.slots,                 -- the slots, each with its key and description
  specs = data.specs,                 -- per workspace: which app fills which slot
  desks = data.desks,                 -- your monitor setups, each using a layout
  layouts = data.layouts,             -- where the slots sit on 1, 2, ... screens
  monitor_names = data.monitor_names, -- your names for your monitors

  -- How many workspaces hyprslots manages: 1 to this (9 when unset).
  workspaces = data.workspaces,

  -- Examples (replace a line above, or add one, and reload Hyprland):
  --
  --   workspaces = 10,                               -- Super+0's workspace 10 too
  --   workspaces = hostname() == "work" and 5 or 9,  -- one number per machine
  --
  -- Tell windows of one app apart by their title: with this, the spec
  -- "com.mitchellh.ghostty/notes" fills a slot with the Ghostty window
  -- whose title starts "notes | " (foot, kitty and Alacritty work so
  -- already):
  --
  --   title_matching = { extractors = { ["com.mitchellh.ghostty"] = " | " } },
}
]]

-- An empty data file, as the editor writes one.
M.SLOTS = serialize.dump({})

local function exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function write(path, text)
  local file, err = io.open(path, "w")
  if not file then
    return nil, tostring(err)
  end
  local written, write_err = file:write(text)
  local closed, close_err = file:close()
  if not written or not closed then
    os.remove(path)
    return nil, tostring(write_err or close_err)
  end
  return true
end

local function quote(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Write the starter into `dir` when it has no config.lua (the dir made
-- first when it is not there). Returns the names written ({} when
-- config.lua was there already), or nil and why not.
function M.ensure(dir)
  local config = dir .. "/config.lua"
  if exists(config) then
    return {}
  end
  -- Hyprland reaps its own children, so os.execute's status says nothing
  -- there: whether the dir is there shows when the file is written.
  os.execute("mkdir -p " .. quote(dir) .. " 2>/dev/null")
  local written = {}
  local slots = dir .. "/slots.lua"
  if not exists(slots) then
    local ok, err = write(slots, M.SLOTS)
    if not ok then
      return nil, "cannot write a starter " .. slots .. ": " .. err
    end
    written[#written + 1] = "slots.lua"
  end
  local ok, err = write(config, M.CONFIG)
  if not ok then
    return nil, "cannot write a starter " .. config .. ": " .. err
  end
  table.insert(written, 1, "config.lua")
  return written
end

return M
