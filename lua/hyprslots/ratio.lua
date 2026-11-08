-- The ratio grammar: one string states the weights of every split in a tree
-- (ported from aerolayout's nested ratio editor, tree_visualizer.py).
--
--   ratio := term (':' term)*
--   term  := (number | '*') ('[' ratio ']')?
--
--   2[1:2]:1    cell 1 takes 2 shares and splits 1:2 inside; cell 2 takes 1
--
-- Whitespace separates cells like ':' does ('1 2 1' is '1:2:1'). A `*` is a
-- cell with no share to state: a column of a scroll branch (`scroll[...]`),
-- each of which is full width. A scroll branch's cells are written `*` (or
-- `1`) and setting them writes nothing; a `*` among tiled siblings is
-- refused.
--
-- hyprslots trees carry integer weights only (tree.lua), so a decimal ratio is
-- turned into the smallest integer ratio meaning the same thing (1.5:1 ->
-- 3:2), and a container's weights are always shown reduced (2:4:2 -> 1:2:1).
--
-- format(node) renders every split below the root, so whatever it shows can
-- be handed back to apply() and changes nothing. Pure: no `hl`, no I/O.

local M = {}

M.STAR = "*"

local ROOT_SUBJECT = "the outer container"

-- A leaf is a slot or the overflow leaf (no children either way).
local function is_leaf(node)
  return node.children == nil
end

-- Whether a node's cells have no share of their own (a scroll branch).
local function shareless(node)
  return not is_leaf(node) and node.scroll == true
end

-- Tokens: numbers/words, ':', '[' and ']'. Whitespace runs become ':', and
-- runs of ':' collapse, so ' 1 : 2 ' reads as '1:2' while '1:' stays an error.
local function tokenize(text)
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
  end
  local normalized = table.concat(words, ":")
  local tokens, word = {}, ""
  for char in normalized:gmatch(".") do
    if char == ":" or char == "[" or char == "]" then
      if word ~= "" then
        tokens[#tokens + 1] = word
        word = ""
      end
      if char ~= ":" or (#tokens > 0 and tokens[#tokens] ~= ":") then
        tokens[#tokens + 1] = char
      end
    else
      word = word .. char
    end
  end
  if word ~= "" then
    tokens[#tokens + 1] = word
  end
  return tokens
end

local function syntax_error(message)
  error({ ratio_error = message }, 0)
end

-- Run fn, turning a ratio_error into nil, message; anything else re-raises.
local function protect(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end
  if type(result) == "table" and result.ratio_error then
    return nil, result.ratio_error
  end
  error(result, 0)
end

-- Parse a ratio into { { weight = n | "*", nested = terms | nil }, ... }.
-- Returns the terms, or nil and a message meant for the user.
function M.parse(text)
  if type(text) ~= "string" then
    return nil, "a ratio must be a string, got " .. type(text)
  end
  return protect(function()
    local tokens = tokenize(text)
    if #tokens == 0 then
      syntax_error("the ratio is empty")
    end
    local pos = 1

    local parse_ratio

    local function parse_term()
      local token = tokens[pos]
      if token == nil then
        syntax_error('ratio ends with a stray ":"')
      end
      if token == ":" or token == "[" or token == "]" then
        syntax_error('expected a number, found "' .. token .. '"')
      end
      local weight
      if token == M.STAR then
        weight = M.STAR
      else
        weight = token:match("^[%d%.%-+eE]+$") and tonumber(token)
        if not weight then
          syntax_error('"' .. token .. '" is not a number')
        end
        if weight <= 0 or weight ~= weight or weight == math.huge then
          syntax_error("ratios must be greater than zero")
        end
        if math.type(weight) == "float" and weight == math.floor(weight) then
          weight = math.tointeger(weight)
        end
      end
      pos = pos + 1

      local term = { weight = weight }
      if tokens[pos] == "[" then
        pos = pos + 1
        term.nested = parse_ratio()
        if tokens[pos] ~= "]" then
          syntax_error('unclosed "["')
        end
        pos = pos + 1
      end
      return term
    end

    function parse_ratio()
      local list = { parse_term() }
      while tokens[pos] == ":" do
        pos = pos + 1
        list[#list + 1] = parse_term()
      end
      return list
    end

    local result = parse_ratio()
    if pos <= #tokens then
      syntax_error('unexpected "' .. tokens[pos] .. '"')
    end
    return result
  end)
end

local function gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

-- The integer ratio a list of positive numbers states: decimals become exact
-- fractions (denominators up to 1000), then the common factor is divided out.
-- 1.5:1 -> 3:2, 0.25:0.25:0.5 -> 1:1:2, 2:4:2 -> 1:2:1.
function M.integers(values)
  local denominator = 1
  local fractions = {}
  for i, value in ipairs(values) do
    local num, den = value, 1
    while math.type(num) ~= "integer" and den < 1000 do
      local rounded = math.floor(num + 0.5)
      if math.abs(num - rounded) < 1e-9 * math.max(1, math.abs(num)) then
        num = rounded
        break
      end
      num, den = num * 10, den * 10
    end
    num = math.floor(num + 0.5)
    fractions[i] = { num = num, den = den }
    denominator = denominator * den // gcd(denominator, den)
  end
  local out, common = {}, 0
  for i, f in ipairs(fractions) do
    out[i] = f.num * (denominator // f.den)
    common = gcd(common, out[i])
  end
  if common > 1 then
    for i = 1, #out do
      out[i] = out[i] // common
    end
  end
  for i = 1, #out do
    out[i] = math.max(1, out[i])
  end
  return out
end

-- How an error names one cell: its slot when it is a window, else its position
-- under its parent ("cell 1 > cell 2").
local function cell_label(child, index, parent)
  local own = child.slot or (is_leaf(child) and "the overflow") or ("cell " .. index)
  if parent == ROOT_SUBJECT then
    return own
  end
  return parent .. " > " .. own
end

local function validate(node, list, path)
  if is_leaf(node) then
    syntax_error(path .. " is a window, not a split")
  end
  local count = #node.children
  if #list ~= count then
    syntax_error(string.format("expected %d value%s for %s, got %d", count, count == 1 and "" or "s", path, #list))
  end
  if shareless(node) then
    for _, term in ipairs(list) do
      if term.weight ~= M.STAR and term.weight ~= 1 then
        syntax_error("ratios don't apply to " .. path .. " — it's a scroll branch, and each of its columns "
          .. "is full width. Write * for every column")
      end
    end
  else
    for _, term in ipairs(list) do
      if term.weight == M.STAR then
        syntax_error("* is a scroll column with no share of its own, and " .. path
          .. " is tiled — every cell here needs a number")
      end
    end
  end
  for i, child in ipairs(node.children) do
    local nested = list[i].nested
    if nested then
      local label = cell_label(child, i, path)
      if is_leaf(child) then
        syntax_error(label .. " is a window, so it has nothing to split")
      end
      validate(child, nested, label)
    end
  end
end

-- A copy of node with the ratio written in (validated beforehand).
local function write(node, list)
  local copy = {}
  for key, value in pairs(node) do
    copy[key] = value
  end
  if is_leaf(node) then
    return copy
  end
  local weights
  if list and not shareless(node) then
    local values = {}
    for i, term in ipairs(list) do
      values[i] = term.weight
    end
    weights = M.integers(values)
  end
  copy.children = {}
  for i, child in ipairs(node.children) do
    local written = write(child, list and list[i].nested)
    if weights then
      written.weight = weights[i]
    end
    copy.children[i] = written
  end
  return copy
end

-- A copy of `node` (a parsed tree) with the ratio `text` applied. Returns the
-- new tree, or nil and a message for the user; on error nothing is written.
function M.apply(node, text)
  if type(node) ~= "table" then
    return nil, "a ratio needs a tree to apply to, got " .. type(node)
  end
  local list, err = M.parse(text)
  if not list then
    return nil, err
  end
  return protect(function()
    validate(node, list, ROOT_SUBJECT)
    return write(node, list)
  end)
end

-- The ratio of node and every split below it, e.g. "2[1:2]:1". A single
-- window has no ratio: "".
function M.format(node)
  if is_leaf(node) or #node.children == 0 then
    return ""
  end
  local cells
  if shareless(node) then
    cells = {}
    for i = 1, #node.children do
      cells[i] = M.STAR
    end
  else
    local values = {}
    for i, child in ipairs(node.children) do
      values[i] = child.weight or 1
    end
    cells = M.integers(values)
  end
  local parts = {}
  for i, child in ipairs(node.children) do
    local inner = M.format(child)
    parts[i] = tostring(cells[i]) .. (inner ~= "" and ("[" .. inner .. "]") or "")
  end
  return table.concat(parts, ":")
end

return M
