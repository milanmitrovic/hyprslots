-- Edits to the editor-owned data file (slots.lua), and which parts of the
-- config the editor may change at all (docs/design.md §4, §9).
--
-- config.lua is real code: it receives the slots.lua table from load_data and
-- returns a config built from it. A config field is editable when config.lua
-- passed the data's own table straight through (the same table, by identity);
-- a field it built in code is read-only, because changing slots.lua would not
-- change it. Granularity: top-level keys, and one level below them
-- (`arrangements.<name>`, `slots.<desk>`).
--
-- Every edit returns a new data table; the one given is never mutated. Pure:
-- no `hl`, no I/O.

local serialize = require("hyprslots.serialize")
local tree = require("hyprslots.tree")

local M = {}

local DESKS = 10

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)
  return keys
end

-- A deep copy of plain data.
function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, inner in pairs(value) do
    out[key] = M.copy(inner)
  end
  return out
end

-- The config paths config.lua sets by code, sorted: "pinned",
-- "arrangements.work", "slots.4". `raw` is what config.lua returned, `given`
-- the table load_data("slots.lua") handed it (nil when it loaded none).
function M.read_only(raw, given)
  local out = {}
  for _, key in ipairs(sorted_keys(raw)) do
    local value, source = raw[key], given and given[key]
    if source ~= nil and rawequal(value, source) then
      -- passed straight through: all of it is the data's
    elseif type(value) == "table" and type(source) == "table" then
      for _, sub in ipairs(sorted_keys(value)) do
        if not rawequal(value[sub], source[sub]) then
          out[#out + 1] = key .. "." .. tostring(sub)
        end
      end
    else
      out[#out + 1] = tostring(key)
    end
  end
  return out
end

-- Whether `section.name` (e.g. arrangements.solo) is the data's to change.
function M.editable(read_only, section, name)
  local whole, one = section, section .. "." .. tostring(name)
  for _, path in ipairs(read_only) do
    if path == whole or path == one then
      return false
    end
  end
  return true
end

-- The data with arrangement's tree for desk and screen role set to `text`
-- (normalized). Returns the new data, or nil and why not.
function M.set_tree(data, arrangement, desk, role, text)
  local entry = data and type(data.arrangements) == "table" and data.arrangements[arrangement]
  if type(entry) ~= "table" then
    return nil, "no arrangement '" .. tostring(arrangement) .. "' in slots.lua"
  end
  if math.type(desk) ~= "integer" or desk < 1 or desk > DESKS then
    return nil, "a desk must be an integer from 1 to " .. DESKS .. ", got " .. tostring(desk)
  end
  if type(entry.screens) ~= "table" or entry.screens[role] == nil then
    return nil, string.format("arrangement '%s' has no screen role '%s'", arrangement, tostring(role))
  end
  local node, err = tree.parse(text)
  if not node then
    return nil, err
  end

  local out = M.copy(data)
  local target = out.arrangements[arrangement]
  target.desks = target.desks or {}
  target.desks[desk] = target.desks[desk] or {}
  target.desks[desk][role] = serialize.tree(node)
  return out
end

return M
