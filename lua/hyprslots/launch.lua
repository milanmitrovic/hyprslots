-- Launching apps (docs/design.md §9, Launching apps): each workspace says
-- whether hyprslots opens the apps its empty slots wait for, never (the
-- default), on demand (the editor's Launch missing) or at login too. This
-- is the pure half: the command a spec launches with and which slots to
-- launch for. api.lua runs it (desktop.lua finds an app's desktop entry,
-- hl_adapter.exec starts it). No `hl`, no I/O.

local spec = require("hyprslots.spec")

local M = {}

M.MODES = { "never", "on_demand", "at_login" }
M.DEFAULT = "never"

-- What the editor says for a slot no command can be had for: a title or tag
-- spec (the app alone would not open the window it means) or an app with no
-- desktop entry, and none in config.lua.
M.NO_COMMAND = "can't launch: set a command"

local VALID = {}
for _, mode in ipairs(M.MODES) do
  VALID[mode] = true
end

function M.valid_mode(mode)
  return VALID[mode] == true
end

-- The mode after `mode`, round (the editor's key cycles them).
function M.next_mode(mode)
  for i, m in ipairs(M.MODES) do
    if m == (mode or M.DEFAULT) then
      return M.MODES[i % #M.MODES + 1]
    end
  end
  return M.MODES[2]
end

-- The command of a desktop entry's text: the Exec of its [Desktop Entry]
-- group with the field codes (%f %U %i ...) dropped and %% kept as %. Nil
-- for an entry with none, one that is Hidden (deleted), or one that runs in
-- a terminal (Terminal=true: which terminal is not the entry's to say).
function M.exec_line(text)
  if type(text) ~= "string" then
    return nil
  end
  local group, exec, hidden, terminal
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local name = line:match("^%[(.-)%]%s*$")
    if name then
      group = name
    elseif group == "Desktop Entry" then
      local key, value = line:match("^%s*([%w%-]+)%s*=%s*(.-)%s*$")
      if key == "Exec" then
        exec = value
      elseif key == "Hidden" then
        hidden = value == "true"
      elseif key == "Terminal" then
        terminal = value == "true"
      end
    end
  end
  if not exec or exec == "" or hidden or terminal then
    return nil
  end
  local out = exec:gsub("%%(.)", function(code)
    return code == "%" and "\0" or ""
  end)
  out = out:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):gsub("%z", "%%")
  return out ~= "" and out or nil
end

-- How a spec (parsed) launches: config.lua's command for it (`commands`:
-- spec text -> command), else, for a spec of a class alone, the app's own
-- from its desktop entry (`desktop(class)` -> id, command, or nil). Returns
-- { command, source = "config" | "desktop", desktop? } or { reason }.
function M.command(entry, commands, desktop)
  local given = commands and commands[entry.text]
  if type(given) == "string" and given ~= "" then
    return { command = given, source = "config" }
  end
  if spec.class_only(entry) and desktop then
    local id, command = desktop(entry.class)
    if id and command then
      return { command = command, source = "desktop", desktop = id }
    end
  end
  return { reason = M.NO_COMMAND }
end

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

-- Which of workspace `input.workspace`'s empty slots to launch an app for:
--
--   input.specs        slot -> parsed spec (the workspace's)
--   input.assignments  address -> { workspace, slot }
--   input.windows      the open windows ({ address, class, title })
--   input.pending      slot -> true: launched for and not arrived yet
--   input.command      fn(parsed spec) -> M.command's reply
--
-- A slot with a spec there and no window in it, by slot name. Never twice:
-- not for a window already open that its spec matches (overflowing, or
-- anywhere but in another slot of the workspace; each such window counts
-- for one slot), nor while one launched for it is on its way. Returns
-- { launch = { { slot, spec, command } }, open = { slots }, pending =
-- { slots }, cannot = { { slot, spec, reason } } }.
function M.missing(input)
  local n = input.workspace
  local filled, holding = {}, {}
  for address, a in pairs(input.assignments or {}) do
    if a.workspace == n then
      filled[a.slot] = true
      holding[address] = true
    end
  end
  local spare = {}
  for _, window in ipairs(input.windows or {}) do
    if window.address and not holding[window.address] then
      spare[#spare + 1] = window
    end
  end
  local out = { launch = {}, open = {}, pending = {}, cannot = {} }
  for _, slot in ipairs(sorted_keys(input.specs)) do
    local entry = input.specs[slot]
    if not filled[slot] then
      local found
      for i, window in ipairs(spare) do
        if spec.match(entry, window) then
          found = i
          break
        end
      end
      if found then
        table.remove(spare, found)
        out.open[#out.open + 1] = slot
      elseif input.pending and input.pending[slot] then
        out.pending[#out.pending + 1] = slot
      else
        local how = input.command(entry)
        if how.command then
          out.launch[#out.launch + 1] = { slot = slot, spec = entry.text, command = how.command }
        else
          out.cannot[#out.cannot + 1] = { slot = slot, spec = entry.text, reason = how.reason }
        end
      end
    end
  end
  return out
end

return M
