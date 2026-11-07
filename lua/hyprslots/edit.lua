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
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local M = {}

local DESKS = 10
local SLOT_NAME = "^[%a_][%w_%-]*$" -- config.lua's rule for slot and role names

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

local function check_desk(desk)
  if math.type(desk) ~= "integer" or desk < 1 or desk > DESKS then
    return nil, "a desk must be an integer from 1 to " .. DESKS .. ", got " .. tostring(desk)
  end
  return true
end

local function check_name(name, what)
  if type(name) ~= "string" or not name:match(SLOT_NAME) then
    return nil, string.format("a %s name must start with a letter or '_' and hold only letters, digits, '_' or '-', got '%s'",
      what, tostring(name))
  end
  return true
end

-- The data's slots of a desk, or nil and why not.
local function desk_slots(data, desk)
  local ok, err = check_desk(desk)
  if not ok then
    return nil, err
  end
  return data and type(data.slots) == "table" and type(data.slots[desk]) == "table" and data.slots[desk] or {}
end

local function existing_slot(data, desk, slot)
  local slots, err = desk_slots(data, desk)
  if not slots then
    return nil, err
  end
  if type(slot) ~= "string" or slots[slot] == nil then
    return nil, string.format("desk %s has no slot '%s'", tostring(desk), tostring(slot))
  end
  return true
end

-- Spec text, normalized (trimmed), or nil and the grammar's complaint.
local function spec_text(text)
  local parsed, err = spec.parse(text)
  if not parsed then
    return nil, err
  end
  return parsed.text
end

-- A copy of a parsed tree with slot `old` called `new`.
function M.rename_leaf(node, old, new)
  local out = {}
  for key, value in pairs(node) do
    out[key] = value
  end
  if node.slot == old then
    out.slot = new
  end
  if node.children then
    out.children = {}
    for i, child in ipairs(node.children) do
      out.children[i] = M.rename_leaf(child, old, new)
    end
  end
  return out
end

-- A copy of a parsed tree without slot `name`: a container left with one
-- child is replaced by that child (taking the container's weight), one left
-- with none goes too. Nil when nothing is left.
function M.remove_leaf(node, name)
  if node.slot ~= nil or node.children == nil then
    if node.slot == name then
      return nil
    end
    return M.copy(node)
  end
  local children = {}
  for _, child in ipairs(node.children) do
    local kept = M.remove_leaf(child, name)
    if kept then
      children[#children + 1] = kept
    end
  end
  if #children == 0 then
    return nil
  end
  if #children == 1 and not node.accordion then
    children[1].weight = node.weight
    return children[1]
  end
  local out = M.copy(node)
  out.children = children
  return out
end

-- Rewrite every tree of desk `desk` in every arrangement with fn(node) ->
-- node or nil (nil drops the branch). Trees that do not parse are left as
-- they are (config.lua's validation reports them).
local function rewrite_trees(out, desk, fn)
  for _, entry in pairs(type(out.arrangements) == "table" and out.arrangements or {}) do
    local branches = type(entry) == "table" and type(entry.desks) == "table" and entry.desks[desk]
    if type(branches) == "table" then
      for role, text in pairs(branches) do
        local node = tree.parse(text)
        if node then
          local changed = fn(node)
          branches[role] = changed and serialize.tree(changed) or nil
        end
      end
      if next(branches) == nil then
        entry.desks[desk] = nil
      end
    end
  end
end

local function set_description(out, desk, slot, text)
  out.descriptions = type(out.descriptions) == "table" and out.descriptions or {}
  local entries = type(out.descriptions[desk]) == "table" and out.descriptions[desk] or {}
  out.descriptions[desk] = entries
  if text == nil or text == "" then
    entries[slot] = nil
  else
    entries[slot] = text
  end
  if next(entries) == nil then
    out.descriptions[desk] = nil
  end
  if next(out.descriptions) == nil then
    out.descriptions = nil
  end
end

local function description_of(data, desk, slot)
  local entries = type(data.descriptions) == "table" and data.descriptions[desk]
  return type(entries) == "table" and entries[slot] or nil
end

-- The data with a slot's spec set (normalized). Nil and why not.
function M.set_spec(data, desk, slot, text)
  local ok, err = existing_slot(data, desk, slot)
  if not ok then
    return nil, err
  end
  local normalized, spec_err = spec_text(text)
  if not normalized then
    return nil, spec_err
  end
  local out = M.copy(data)
  out.slots[desk][slot] = normalized
  return out
end

-- The data with a new slot on a desk (description optional).
function M.add_slot(data, desk, name, text, description)
  local slots, err = desk_slots(data, desk)
  if not slots then
    return nil, err
  end
  local ok, name_err = check_name(name, "slot")
  if not ok then
    return nil, name_err
  end
  if slots[name] ~= nil then
    return nil, string.format("desk %d already has a slot '%s'", desk, name)
  end
  local normalized, spec_err = spec_text(text)
  if not normalized then
    return nil, spec_err
  end
  local out = M.copy(data or {})
  out.slots = type(out.slots) == "table" and out.slots or {}
  out.slots[desk] = type(out.slots[desk]) == "table" and out.slots[desk] or {}
  out.slots[desk][name] = normalized
  if type(description) == "string" and description ~= "" then
    set_description(out, desk, name, description)
  end
  return out
end

-- The data without a slot: gone from the desk, from every tree that placed
-- it (a branch it was all of goes too) and from the descriptions.
function M.remove_slot(data, desk, slot)
  local ok, err = existing_slot(data, desk, slot)
  if not ok then
    return nil, err
  end
  local out = M.copy(data)
  out.slots[desk][slot] = nil
  rewrite_trees(out, desk, function(node) return M.remove_leaf(node, slot) end)
  set_description(out, desk, slot, nil)
  return out
end

-- The data with a slot renamed, on its desk and in every tree of every
-- arrangement that places it (aerolayout's rename_slot_everywhere), its
-- description following.
function M.rename_slot(data, desk, old, new)
  local ok, err = existing_slot(data, desk, old)
  if not ok then
    return nil, err
  end
  local named, name_err = check_name(new, "slot")
  if not named then
    return nil, name_err
  end
  if new == old then
    return M.copy(data)
  end
  if data.slots[desk][new] ~= nil then
    return nil, string.format("desk %d already has a slot '%s'", desk, new)
  end
  local out = M.copy(data)
  out.slots[desk][new], out.slots[desk][old] = out.slots[desk][old], nil
  rewrite_trees(out, desk, function(node) return M.rename_leaf(node, old, new) end)
  local description = description_of(data, desk, old)
  set_description(out, desk, old, nil)
  if description then
    set_description(out, desk, new, description)
  end
  return out
end

-- The data with a slot's description set; "" (or nil) removes it.
function M.describe_slot(data, desk, slot, text)
  local ok, err = existing_slot(data, desk, slot)
  if not ok then
    return nil, err
  end
  if text ~= nil and type(text) ~= "string" then
    return nil, "a description must be text"
  end
  local out = M.copy(data)
  set_description(out, desk, slot, text)
  return out
end

return M
