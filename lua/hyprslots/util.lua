-- Small table, number and text helpers the engine's modules share. Pure: no
-- `hl`, no I/O.

local M = {}

-- The greatest common divisor of two integers (gcd(0, n) is n).
function M.gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

-- `n` rounded to the nearest integer, halves up.
function M.round(n)
  return math.floor(n + 0.5)
end

-- `text` without leading and trailing whitespace.
function M.trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A list's values as a set (value -> true).
function M.set_of(list)
  local out = {}
  for _, value in ipairs(list) do
    out[value] = true
  end
  return out
end

-- The order sorted_keys puts keys in: numbers first, then the other types by
-- name; within a type, numbers and strings by value, anything else (booleans,
-- tables) by its text, so mixed keys never raise.
local function before(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    if ta == "number" or tb == "number" then
      return ta == "number"
    end
    return ta < tb
  end
  if ta == "number" or ta == "string" then
    return a < b
  end
  return tostring(a) < tostring(b)
end

-- A table's keys, sorted (see `before`); no keys for nil.
function M.sorted_keys(t)
  local keys = {}
  for key in pairs(t or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, before)
  return keys
end

-- A one-level copy of a table (an empty one for nil).
function M.shallow(t)
  local out = {}
  for key, value in pairs(t or {}) do
    out[key] = value
  end
  return out
end

-- A deep copy of plain data (tables of tables; no cycles, metatables dropped).
function M.deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, inner in pairs(value) do
    out[key] = M.deep_copy(inner)
  end
  return out
end

return M
