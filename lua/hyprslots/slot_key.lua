-- Each global slot's key (docs/design.md §4): the one letter that picks it
-- in every slot-choice prompt of the editor, saved with the slot in
-- slots.lua (`slots = { main = { key = "m" } }`) so it stays the same from
-- prompt to prompt. Letters only, a to z: the digits jump workspaces.
-- A prompt owns every key while it is open, so a slot key may be any letter,
-- the panel's own keys (a, q, s...) included.
--
-- pick chooses a new slot's: the first letter of its name no other slot
-- uses, else the next unused letter of the name, else the first unused
-- letter a-z. fill gives one to every slot that has none, in slot name
-- order (migration, normalization). Pure.

local M = {}

-- Why `key` is no slot key, nil when it is one.
function M.check(key)
  if type(key) ~= "string" or not key:match("^[a-z]$") then
    return "a slot's key is one letter a-z, got '" .. tostring(key) .. "'"
  end
  return nil
end

-- The key for a slot called `name`, given the keys in use (`used`: key ->
-- true); nil when every letter is used.
function M.pick(name, used)
  for char in tostring(name):lower():gmatch("%a") do
    if char:match("^[a-z]$") and not used[char] then
      return char
    end
  end
  for code = string.byte("a"), string.byte("z") do
    local char = string.char(code)
    if not used[char] then
      return char
    end
  end
  return nil
end

local function names(slots)
  local out = {}
  for name, entry in pairs(slots) do
    if type(name) == "string" and type(entry) == "table" then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

-- Give every slot of `slots` (name -> { key?, description? }) that has no
-- key one, in place, in name order around the keys slots have (a key that
-- is no letter is left for validation to report). Returns whether any
-- slot got one.
function M.fill(slots)
  if type(slots) ~= "table" then
    return false
  end
  local list = names(slots)
  local used = {}
  for _, name in ipairs(list) do
    local key = slots[name].key
    if key ~= nil then
      used[key] = true
    end
  end
  local changed = false
  for _, name in ipairs(list) do
    local entry = slots[name]
    if entry.key == nil then
      local key = M.pick(name, used)
      if key then
        entry.key = key
        used[key] = true
        changed = true
      end
    end
  end
  return changed
end

return M
