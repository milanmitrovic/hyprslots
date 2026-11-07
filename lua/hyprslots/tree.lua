-- Layout trees: `h[main:2, right:1]`, `v[top, h[a, b:3]:2]`, or a bare slot.
--
-- Inner nodes are `h` (side by side) or `v` (stacked) splits; each child may
-- carry an integer weight (default 1). Leaves are slot names. A parsed node is
--
--   { slot = "main", weight = 2 }                          -- leaf
--   { split = "h", weight = 1, children = { node, ... } }  -- split
--
-- `boxes` divides an area by those weights in whole pixels: every child but the
-- last gets floor(extent * weight / total), the last gets the remainder, so the
-- boxes tile the area exactly and the result never depends on float rounding.
-- `nudge` (keyboard resize) moves one edge and keeps the weights exact
-- integers. Pure: no `hl`, no I/O.

local M = {}

local NAME = "^[%w_%-%.]+"

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

  function p.node()
    local name = p.name()
    if (name == "h" or name == "v") and p.peek() == "[" then
      p.pos = p.pos + 1
      local children = {}
      repeat
        local child = p.node()
        child.weight = p.weight()
        children[#children + 1] = child
        local more = p.peek() == ","
        if more then
          p.pos = p.pos + 1
        end
      until not more
      p.expect("]")
      return { split = name, children = children }
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
  return { split = node.split, weight = node.weight, children = children }
end

local function divide(node, x, y, w, h, out)
  if node.slot then
    out[node.slot] = { x = x, y = y, w = w, h = h }
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

-- Keyboard resize ---------------------------------------------------------

local AXIS = { l = "h", r = "h", u = "v", d = "v" }
local STEP = { l = -1, r = 1, u = -1, d = 1 }
local RESOLUTION = 10000 -- a fractional nudge is quantised to 1/RESOLUTION of its split

-- The path of nodes from `node` down to the leaf `slot`, or nil.
local function path_to(node, slot, path)
  path = path or {}
  path[#path + 1] = node
  if node.slot then
    if node.slot == slot then
      return path
    end
  else
    for _, child in ipairs(node.children) do
      if path_to(child, slot, path) then
        return path
      end
    end
  end
  path[#path] = nil
  return nil
end

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end
end

local function gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

local function copy(node)
  local out = {}
  for key, value in pairs(node) do
    out[key] = value
  end
  return out
end

local SIDE = { l = "left of", r = "right of", u = "above", d = "below" }
local MIN_SHARE = 20 -- no child of a nudged split drops below 1/MIN_SHARE (5%) of it

-- The nearest split on `path` in `axis` where the path's child has a
-- neighbour `step` away: depth of the split on the path, child index, neighbour index.
local function hinge(path, axis, step)
  for depth = #path - 1, 1, -1 do
    local split = path[depth]
    if split.split == axis then
      local i = index_of(split.children, path[depth + 1])
      local j = i + step
      if split.children[j] then
        return depth, i, j
      end
    end
  end
  return nil
end

local LIMIT = 1 << 40 -- weights are never scaled past this

-- The extent (w for h, h for v) of path[depth] when the root is laid over
-- `area`, the way `boxes` divides it (ignoring absent slots).
local function extent_of(path, depth, area)
  local x, y = round(area.x), round(area.y)
  local w, h = round(area.x + area.w) - x, round(area.y + area.h) - y
  for d = 1, depth - 1 do
    local split, total, before, size = path[d], 0, 0, nil
    for _, child in ipairs(split.children) do
      total = total + child.weight
    end
    local length = split.split == "h" and w or h
    for k, child in ipairs(split.children) do
      size = k == #split.children and length - before or length * child.weight // total
      if child == path[d + 1] then
        break
      end
      before = before + size
    end
    if split.split == "h" then
      w = size
    else
      h = size
    end
  end
  return path[depth].split == "h" and w or h
end

-- The split's weights scaled so the nudge is a whole number of weight units,
-- the scaled total, and that number of units. A fraction is quantised to
-- 1/RESOLUTION of the split; pixels (`extent` given) are exact: the total is
-- scaled to a multiple of the extent. Past LIMIT the weights are not scaled
-- and the nudge is rounded instead.
local function scaled(split, delta, extent)
  local total = 0
  for _, child in ipairs(split.children) do
    total = total + child.weight
  end
  local scale = extent and extent // gcd(extent, total) or RESOLUTION
  if total * scale > LIMIT then
    scale = 1
  end
  local weights = {}
  for k, child in ipairs(split.children) do
    weights[k] = child.weight * scale
  end
  total = total * scale
  local units = extent and delta * total / extent or delta * total
  return weights, total, math.floor(units + 0.5)
end

-- Grow `slot` toward `dir` (l, r, u, d) by `delta`, a fraction of the nearest
-- ancestor split in that axis that has a neighbour on that side; only that
-- neighbour gives up what the slot gains (a negative delta shrinks the slot
-- and grows the neighbour). Each of the two keeps at least 1/MIN_SHARE of the
-- split. Weights stay exact integers: the split is scaled so the nudge is a
-- whole number of units (fractions are quantised to 1/RESOLUTION of the
-- split), then divided by the weights' greatest common divisor, so
-- h[a, b] nudged by 0.1 becomes h[a:3, b:2].
--
-- With `opts.area`, `delta` is in pixels instead: the split's extent when the
-- tree is laid over that area (absent slots are not pruned first), and the
-- edge moves by exactly that many pixels.
--
-- Returns a new tree sharing untouched subtrees with `root` (which is never
-- modified), or nil and why not.
function M.nudge(root, slot, dir, delta, opts)
  local axis, step = AXIS[dir], STEP[dir]
  if not axis then
    return nil, "a direction must be l, r, u or d, got '" .. tostring(dir) .. "'"
  end
  if type(delta) ~= "number" or delta ~= delta then
    return nil, "a nudge must be a number, got '" .. tostring(delta) .. "'"
  end
  local path = path_to(root, slot)
  if not path then
    return nil, "no slot '" .. tostring(slot) .. "' in this tree"
  end
  local depth, i, j = hinge(path, axis, step)
  if not depth then
    return nil, string.format("nothing %s '%s' to take space from", SIDE[dir], slot)
  end

  local split = path[depth]
  local extent = opts and opts.area and extent_of(path, depth, opts.area)
  if extent and extent <= 0 then
    return nil, "the area has no room to nudge in"
  end
  local weights, total, change = scaled(split, delta, extent)
  local floor = (total + MIN_SHARE - 1) // MIN_SHARE
  change = math.min(change, math.max(weights[j] - floor, 0))
  change = math.max(change, -math.max(weights[i] - floor, 0))
  weights[i] = weights[i] + change
  weights[j] = weights[j] - change

  local common = 0
  for _, weight in ipairs(weights) do
    common = gcd(weight, common)
  end

  local node = copy(split)
  node.children = {}
  for k, child in ipairs(split.children) do
    node.children[k] = copy(child)
    node.children[k].weight = weights[k] // common
  end

  -- Rebuild the ancestors above the split, sharing everything else.
  for d = depth - 1, 1, -1 do
    local parent = copy(path[d])
    parent.children = {}
    for k, child in ipairs(path[d].children) do
      parent.children[k] = child == path[d + 1] and node or child
    end
    node = parent
  end
  return node
end

return M
