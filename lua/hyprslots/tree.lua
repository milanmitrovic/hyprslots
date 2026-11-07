-- Layout trees: `h[main:2, right:1]`, `v[top, h[a, b:3]:2]`, or a bare slot.
--
-- Inner nodes are `h` (side by side) or `v` (stacked) splits; each child may
-- carry an integer weight (default 1). Leaves are slot names. An accordion,
-- `a[left, main, right]`, stacks its members in one Hyprland group: it holds
-- slots only (no splits, no weights) and all of its members share its box. A
-- parsed node is
--
--   { slot = "main", weight = 2 }                               -- leaf
--   { split = "h", weight = 1, children = { node, ... } }       -- split
--   { accordion = true, weight = 1, children = { leaf, ... } }  -- accordion
--
-- `boxes` divides an area by those weights in whole pixels: every child but the
-- last gets floor(extent * weight / total), the last gets the remainder, so the
-- boxes tile the area exactly and the result never depends on float rounding.
-- Pure: no `hl`, no I/O.

local M = {}

local NAME = "^[%w_%-%.]+"

-- Letters that open a container when a '[' follows them.
local CONTAINER = { h = true, v = true, a = true }

local function parser(text)
  local p = { text = text, pos = 1 }

  function p.fail(message)
    error({ tree_error = string.format("%s at position %d in '%s'", message, p.pos, text) }, 0)
  end

  function p.skip()
    p.pos = text:find("[^%s]", p.pos) or (#text + 1)
  end

  function p.peek()
    p.skip()
    return text:sub(p.pos, p.pos)
  end

  function p.expect(char)
    if p.peek() ~= char then
      local found = p.pos > #text and "end of text" or ("'" .. p.peek() .. "'")
      p.fail(string.format("expected '%s', found %s", char, found))
    end
    p.pos = p.pos + 1
  end

  function p.name()
    p.skip()
    local first, last = text:find(NAME, p.pos)
    if not first then
      local found = p.pos > #text and "end of text" or ("'" .. text:sub(p.pos, p.pos) .. "'")
      p.fail("expected a slot name, found " .. found)
    end
    p.pos = last + 1
    return text:sub(first, last)
  end

  function p.weight()
    if p.peek() ~= ":" then
      return 1
    end
    p.pos = p.pos + 1
    p.skip()
    local first, last = text:find("^[%d%.%-]+", p.pos)
    local digits = first and text:sub(first, last)
    local weight = digits and digits:match("^%d+$") and tonumber(digits)
    if not weight or weight < 1 then
      p.fail("a weight must be a positive integer, got '" .. (digits or text:sub(p.pos, p.pos)) .. "'")
    end
    p.pos = last + 1
    return weight
  end

  -- `[child, child:w, ...]`, after the container's letter.
  function p.children(child, weightless)
    p.pos = p.pos + 1
    local children = {}
    repeat
      local node = child()
      if weightless and p.peek() == ":" then
        p.fail("accordion members take no weight (the accordion shares one box)")
      end
      node.weight = p.weight()
      children[#children + 1] = node
      local more = p.peek() == ","
      if more then
        p.pos = p.pos + 1
      end
    until not more
    p.expect("]")
    return children
  end

  -- An accordion member: a slot, never a container.
  function p.member()
    local start = p.pos
    local name = p.name()
    if CONTAINER[name] and p.peek() == "[" then
      p.pos = start
      p.skip()
      p.fail("an accordion holds slots only, found '" .. name .. "[' inside it")
    end
    return { slot = name }
  end

  function p.node()
    local name = p.name()
    if CONTAINER[name] and p.peek() == "[" then
      if name == "a" then
        return { accordion = true, children = p.children(p.member, true) }
      end
      return { split = name, children = p.children(p.node) }
    end
    return { slot = name }
  end

  return p
end

local function collect(node, out)
  if node.slot then
    out[#out + 1] = node.slot
  else
    for _, child in ipairs(node.children) do
      collect(child, out)
    end
  end
  return out
end

-- The slot names of a tree, in reading order.
function M.slots(node)
  return collect(node, {})
end

local function collect_accordions(node, out)
  if node.accordion then
    out[#out + 1] = collect(node, {})
  elseif node.children then
    for _, child in ipairs(node.children) do
      collect_accordions(child, out)
    end
  end
  return out
end

-- The member slots of each accordion in a tree, in reading order.
function M.accordions(node)
  return collect_accordions(node, {})
end

-- Parse tree text. Returns the root node, or nil and an error message.
function M.parse(text)
  if type(text) ~= "string" then
    return nil, "a tree must be a string, got " .. type(text)
  end

  local p = parser(text)
  local ok, result = pcall(function()
    local root = p.node()
    if p.peek() == ":" then
      p.fail("the root of a tree takes no weight")
    end
    if p.pos <= #text then
      p.fail("unexpected '" .. text:sub(p.pos, p.pos) .. "'")
    end
    root.weight = 1
    return root
  end)
  if not ok then
    if type(result) == "table" and result.tree_error then
      return nil, result.tree_error
    end
    error(result, 0)
  end

  local seen = {}
  for _, slot in ipairs(M.slots(result)) do
    if seen[slot] then
      return nil, string.format("slot '%s' appears twice in '%s'", slot, text)
    end
    seen[slot] = true
  end

  return result
end

-- The node with absent slots removed (nil when nothing is left). Weights of the
-- survivors are kept, so the remaining ratio is the configured one.
local function prune(node, present)
  if not present then
    return node
  end
  if node.slot then
    return present[node.slot] and node or nil
  end
  local children = {}
  for _, child in ipairs(node.children) do
    local kept = prune(child, present)
    if kept then
      children[#children + 1] = kept
    end
  end
  if #children == 0 then
    return nil
  end
  return { split = node.split, accordion = node.accordion, weight = node.weight, children = children }
end

local function divide(node, x, y, w, h, out)
  if node.slot then
    out[node.slot] = { x = x, y = y, w = w, h = h }
    return
  end
  if node.accordion then
    for _, child in ipairs(node.children) do
      divide(child, x, y, w, h, out)
    end
    return
  end

  local total = 0
  for _, child in ipairs(node.children) do
    total = total + child.weight
  end

  local extent = node.split == "h" and w or h
  local offset = 0
  for i, child in ipairs(node.children) do
    local size
    if i == #node.children then
      size = extent - offset
    else
      size = extent * child.weight // total
    end
    if node.split == "h" then
      divide(child, x + offset, y, size, h, out)
    else
      divide(child, x, y + offset, w, size, out)
    end
    offset = offset + size
  end
end

local function round(n)
  return math.floor(n + 0.5)
end

-- Slot -> { x, y, w, h } in whole pixels for a tree laid over `area`. With
-- `present` (a set of slot names), only those slots are laid out and the rest
-- of the tree closes up around them.
function M.boxes(node, area, present)
  local out = {}
  local kept = prune(node, present)
  if kept then
    local x, y = round(area.x), round(area.y)
    divide(kept, x, y, round(area.x + area.w) - x, round(area.y + area.h) - y, out)
  end
  return out
end

return M
