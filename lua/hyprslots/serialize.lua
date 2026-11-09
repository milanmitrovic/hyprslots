-- Write the editor-owned slots.lua deterministically (docs/design.md §4, §9).
--
-- `dump(data)` is the text of a data-only Lua file: one `return { ... }`
-- table literal under a header comment, two-space indentation, one entry per
-- line with a trailing comma; a desk's `monitors` list of
-- scalars go on one line (`monitors = { "eDP-1", "DP-1" },`), trees stay one
-- screen per line. Key order is fixed (slots, specs, desks, layouts, then a
-- desk's monitors and layout and a layout's screens, default,
-- workspaces, then integer keys ascending, then string keys sorted), strings
-- are written with %q, so the same data always gives the same bytes and
-- load(dump(x)) == x.
--
-- `write(path, data)` replaces a file atomically: the dump goes to a temp
-- file next to it, which is then renamed over the target.
--
-- `tree(node)` turns a parsed tree back into the text tree.parse reads.

local M = {}

-- A scroll branch's column width as tree text writes it (`0.5`): four
-- significant digits at most, as the editor's Layout.js writes it too.
function M.width(width)
  return string.format("%.4g", width)
end

-- The text of a parsed tree: weights of 1 are left out, children are joined
-- with ", ". A split is written as h[...] or v[...], a scroll branch
-- ({ scroll = true }, tree.lua) as scroll[...] (scroll:0.5[...] with a
-- width), and a leaf without a slot is
-- the overflow leaf `*`. Any other split kind is written as kind[children].
function M.tree(node)
  if node.slot then
    return node.slot
  end
  if node.children == nil then
    return "*" -- the overflow leaf
  end
  local parts = {}
  for i, child in ipairs(node.children) do
    local text = M.tree(child)
    if child.weight and child.weight ~= 1 then
      text = text .. ":" .. tostring(child.weight)
    end
    parts[i] = text
  end
  local kind = node.scroll and "scroll" or node.split
  if node.scroll and node.width then
    kind = kind .. ":" .. M.width(node.width)
  end
  return kind .. "[" .. table.concat(parts, ", ") .. "]"
end

M.HEADER = [[
-- slots.lua: written by the hyprslots editor (hyprslots.api "save").
-- Data only: config.lua loads it with load_data("slots.lua"). Edits made here
-- by hand are overwritten on the next save; put code in config.lua instead.
]]

-- Keys that come first, in this order, wherever they appear.
local KEY_ORDER = { slots = 1, specs = 2, desks = 3, layouts = 4, monitors = 5, layout = 6, screens = 8,
  default = 9, workspaces = 10 }

-- Keys whose list of scalars is written on one line.
local INLINE = { monitors = true }

local KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in
  local nil not or repeat return then true until while]]):gmatch("%a+") do
  KEYWORDS[word] = true
end

local function key_before(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return ta == "number"
  end
  if ta == "number" then
    return a < b
  end
  local ra, rb = KEY_ORDER[a], KEY_ORDER[b]
  if ra or rb then
    if ra and rb then
      return ra < rb
    end
    return ra ~= nil
  end
  return a < b
end

local function scalar(value)
  local kind = type(value)
  if kind == "string" then
    return string.format("%q", value)
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "number" then
    if math.type(value) == "integer" then
      return string.format("%d", value)
    end
    if value ~= value or value == math.huge or value == -math.huge then
      error("serialize: a data file cannot hold " .. tostring(value), 0)
    end
    local text = string.format("%.17g", value)
    if tonumber(string.format("%.15g", value)) == value then
      text = string.format("%.15g", value)
    end
    if not text:find("[%.eE]") then
      text = text .. ".0"
    end
    return text
  end
  error("serialize: a data file cannot hold a " .. kind, 0)
end

local function key_text(key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") and not KEYWORDS[key] then
    return key
  end
  if type(key) == "string" or math.type(key) == "integer" then
    return "[" .. scalar(key) .. "]"
  end
  error("serialize: a data file cannot have a " .. type(key) .. " key", 0)
end

-- The values of a non-empty list of strings and numbers (keys 1..n), or nil.
local function scalar_list(value)
  local n = #value
  if n == 0 then
    return nil
  end
  local count = 0
  for key, item in pairs(value) do
    count = count + 1
    if math.type(key) ~= "integer" or key < 1 or key > n or (type(item) ~= "string" and type(item) ~= "number") then
      return nil
    end
  end
  return count == n and value or nil
end

local function emit(value, indent, out, seen, inline)
  if inline and type(value) == "table" and scalar_list(value) then
    local items = {}
    for i, item in ipairs(value) do
      items[i] = scalar(item)
    end
    out[#out + 1] = "{ " .. table.concat(items, ", ") .. " }"
    return
  end
  if type(value) ~= "table" then
    out[#out + 1] = scalar(value)
    return
  end
  if seen[value] then
    error("serialize: a data file cannot hold a table inside itself", 0)
  end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  if #keys == 0 then
    out[#out + 1] = "{}"
    seen[value] = nil
    return
  end
  table.sort(keys, key_before)
  local inner = indent .. "  "
  out[#out + 1] = "{\n"
  for _, key in ipairs(keys) do
    out[#out + 1] = inner .. key_text(key) .. " = "
    emit(value[key], inner, out, seen, INLINE[key] == true)
    out[#out + 1] = ",\n"
  end
  out[#out + 1] = indent .. "}"
  seen[value] = nil
end

-- The text of a data file returning `data`. Raises on what a data file cannot
-- hold (functions, userdata, cycles, NaN).
function M.dump(data)
  local out = { M.HEADER, "return " }
  emit(data, "", out, {})
  out[#out + 1] = "\n"
  return table.concat(out)
end

-- Write data to path atomically. Returns true, or nil and an error message.
function M.write(path, data)
  local ok, text = pcall(M.dump, data)
  if not ok then
    return nil, tostring(text)
  end
  local tmp = string.format("%s.tmp.%d.%d", path, os.time(), math.random(1, 1 << 30))
  local file, err = io.open(tmp, "w")
  if not file then
    return nil, "cannot write " .. path .. ": " .. tostring(err)
  end
  local written, write_err = file:write(text)
  local closed, close_err = file:close()
  if not written or not closed then
    os.remove(tmp)
    return nil, "cannot write " .. path .. ": " .. tostring(write_err or close_err)
  end
  local renamed, rename_err = os.rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return nil, "cannot replace " .. path .. ": " .. tostring(rename_err)
  end
  return true
end

return M
