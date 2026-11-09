-- Layout trees: `h[main:2, right:1]`, `v[top, h[a, b:3]:2]`, or a bare slot.
--
-- Inner nodes are `h` (side by side) or `v` (stacked) splits; each child may
-- carry an integer weight (default 1). Leaves are slot names. A scroll
-- container, `scroll[left, main, right]`, is a whole screen's tree: its slots
-- are full-width columns of Hyprland's scrolling layout, in that order
-- (scroll.lua); it holds slots and at most the overflow leaf (no splits, no
-- weights) and sits at the root only. The accordion `a[...]` (a Hyprland group, with tabs) is gone and
-- refused with a pointer to scroll[...]. A parsed node is
--
--   { slot = "main", weight = 2 }                               -- leaf
--   { split = "h", weight = 1, children = { node, ... } }       -- split
--   { scroll = true, width = 0.5, weight = 1, children = { leaf, ... } }  -- scroll
--   { overflow = true, weight = 1 }                             -- overflow leaf
--
-- A scroll branch's columns are full width unless it says otherwise:
-- `scroll:0.5[a, b]` gives each column half the screen (`width`, a fraction
-- from 0.1 to 1; nil for full width, which `scroll:1[...]` is too).
--
-- The overflow leaf, written `*` (at most one per tree), is where windows with
-- no slot in the tree go; in a scroll container it is the column they take
-- (`scroll[left, main, *, right]`), and without one they go after the slots.
--
-- `boxes` divides an area by those weights in whole pixels: every child but the
-- last gets floor(extent * weight / total), the last gets the remainder, so the
-- boxes tile the area exactly and the result never depends on float rounding.
-- `nudge` (keyboard resize) moves one edge and keeps the weights exact
-- integers. Pure: no `hl`, no I/O.

local M = {}

-- The narrowest column a scroll branch may ask for (a fraction of the screen).
local MIN_WIDTH = 0.1

local NAME = "^[%w_%-%.]+"

-- The key tree.boxes gives the overflow leaf's box (never a slot name).
M.OVERFLOW = "*"

-- An appended overflow column's share beside the tree.
local TREE_WEIGHT, OVERFLOW_WEIGHT = 3, 1

-- Letters that open a container when a '[' follows them.
local CONTAINER = { h = true, v = true, a = true, scroll = true }

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
  -- `weightless` is the error a weight on a child is.
  function p.children(child, weightless)
    p.pos = p.pos + 1
    local children = {}
    repeat
      local node = child()
      if weightless and p.peek() == ":" then
        p.fail(weightless)
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

  -- A member of a slots-only container (`what` names it in errors): a slot,
  -- never a container; the overflow leaf only where `overflow` says it may be
  -- (a scroll branch's column for windows with no slot).
  local function member(what, overflow)
    return function()
      if p.peek() == "*" then
        if overflow then
          return p.node(false)
        end
        p.fail(what .. " holds slots only, found '*' inside it")
      end
      p.skip()
      local start = p.pos
      local name = p.name()
      if CONTAINER[name] and p.peek() == "[" then
        p.pos = start
        p.fail(what .. " holds slots only, found '" .. name .. "[' inside it")
      end
      return { slot = name }
    end
  end

  -- After `scroll`: `:<width>[` gives a scroll branch's column width (a
  -- fraction of the screen, 1 = full width, written as none). Returns
  -- true and the width (nil for full) when one is there, with the position
  -- at its '['; false when `scroll` is no container with a width.
  function p.scroll_width()
    local first, last, given = text:find("^%s*:%s*([^%[%]%s,]*)%s*%[", p.pos)
    if not first then
      return false
    end
    local width = given:match("^%d*%.?%d+$") and tonumber(given)
    if not width or width < MIN_WIDTH or width > 1 then
      p.pos = text:find(":", p.pos, true) + 1
      p.skip()
      p.fail("a scroll width must be a fraction of the screen from " .. MIN_WIDTH .. " to 1, got '" .. given .. "'")
    end
    p.pos = last
    return true, width < 1 and width or nil
  end

  -- A node; `root` when it is the whole tree (where scroll[...] may be).
  function p.node(root)
    if p.peek() == "*" then
      if p.overflow then
        p.fail("more than one place for other windows '*'")
      end
      p.overflow = true
      p.pos = p.pos + 1
      return { overflow = true }
    end
    p.skip()
    local start = p.pos
    local name = p.name()
    local sized, width = false, nil
    if name == "scroll" then
      local probe = p.pos
      sized, width = p.scroll_width()
      if sized and not root then
        p.pos = start
        p.fail("scroll[...] is a whole screen's tree, found it inside a split")
      end
      if not sized then
        p.pos = probe
      end
    end
    if CONTAINER[name] and p.peek() == "[" then
      if name == "a" then
        -- Read its members for the suggestion, then refuse it where it starts.
        local slots = {}
        for i, child in ipairs(p.children(member("a[...]"), "a[...] is gone")) do
          slots[i] = child.slot
        end
        p.pos = start
        p.fail("a[...] (an accordion, a Hyprland group with tabs) is gone: write scroll["
          .. table.concat(slots, ", ") .. "] for full-width scrolling columns"
          .. (root and "" or " (as a screen's whole tree)"))
      end
      if name == "scroll" then
        if not root then
          p.pos = start
          p.fail("scroll[...] is a whole screen's tree, found it inside a split")
        end
        return { scroll = true, width = width,
          children = p.children(member("scroll[...]", true), "columns of scroll[...] take no weight (each is full width)") }
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
  elseif node.children then
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

local function find_overflow(node)
  if node.overflow then
    return true
  end
  for _, child in ipairs(node.children or {}) do
    if find_overflow(child) then
      return true
    end
  end
  return false
end

-- Whether a tree places the overflow leaf itself.
function M.has_overflow(node)
  return find_overflow(node)
end

-- The tree with somewhere for unmatched windows: itself when it has an
-- overflow leaf, else `h[tree:3, *:1]` (a column at the right). The tree given
-- is not modified.
function M.with_overflow(node)
  if find_overflow(node) then
    return node
  end
  local kept = {}
  for key, value in pairs(node) do
    kept[key] = value
  end
  kept.weight = TREE_WEIGHT
  return {
    split = "h",
    weight = 1,
    children = { kept, { overflow = true, weight = OVERFLOW_WEIGHT } },
  }
end

-- The column slots of a scroll branch, in order, or nil when the tree is no
-- scroll[...].
function M.scroll(node)
  if node and node.scroll then
    return collect(node, {})
  end
  return nil
end

-- The columns of a scroll branch in order: its slot names, and M.OVERFLOW
-- where it places the overflow leaf (the column windows with no slot in the
-- branch go to; scroll.plan). Nil when the tree is no scroll[...].
function M.columns(node)
  if not (node and node.scroll) then
    return nil
  end
  local out = {}
  for i, child in ipairs(node.children) do
    out[i] = child.slot or M.OVERFLOW
  end
  return out
end

local function shallow(node)
  local out = {}
  for key, value in pairs(node) do
    out[key] = value
  end
  return out
end

-- The tree with `slots` (names, in order) added: as new children of a tiled
-- tree's root split (a bare leaf becoming h[leaf, slot, ...]), or as columns
-- at the end of a scroll branch, before its `*` when that is the last
-- column (windows with no slot keep coming last). The tree given is not
-- modified.
function M.append(node, slots)
  if #slots == 0 then
    return node
  end
  local out
  if node.children then
    out = shallow(node)
    out.children = {}
    for i, child in ipairs(node.children) do
      out.children[i] = child
    end
  else
    local leaf = shallow(node)
    leaf.weight = 1
    out = { split = "h", weight = node.weight or 1, children = { leaf } }
  end
  local at = #out.children + 1
  if out.scroll and out.children[#out.children].overflow then
    at = #out.children
  end
  for _, slot in ipairs(slots) do
    table.insert(out.children, at, { slot = slot, weight = 1 })
    at = at + 1
  end
  return out
end

-- Parse tree text. Returns the root node, or nil and an error message.
function M.parse(text)
  if type(text) ~= "string" then
    return nil, "a tree must be a string, got " .. type(text)
  end

  local p = parser(text)
  local ok, result = pcall(function()
    local root = p.node(true)
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
  if node.overflow then
    return present[M.OVERFLOW] and node or nil
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
  return { split = node.split, scroll = node.scroll, width = node.width, weight = node.weight, children = children }
end

local function divide(node, x, y, w, h, out)
  if node.slot or node.overflow then
    out[node.slot or M.OVERFLOW] = { x = x, y = y, w = w, h = h }
    return
  end
  local total = 0
  for _, child in ipairs(node.children) do
    total = total + child.weight
  end

  -- A scroll branch on lua:slots (scroll.lua puts it on Hyprland's scrolling
  -- layout) shows its columns side by side.
  local across = node.split == "h" or node.scroll
  local extent = across and w or h
  local offset = 0
  for i, child in ipairs(node.children) do
    local size
    if i == #node.children then
      size = extent - offset
    else
      size = extent * child.weight // total
    end
    if across then
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
    for _, child in ipairs(node.children or {}) do
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

-- `node` as `boxes` lays it out: pruned to `present` (every node when nil),
-- each copy keeping its node in the given tree as `source`.
local function mirror(node, present)
  if node.slot or node.overflow then
    if present and not present[node.slot or M.OVERFLOW] then
      return nil
    end
    return { slot = node.slot, overflow = node.overflow, weight = node.weight, source = node }
  end
  local children = {}
  for _, child in ipairs(node.children) do
    local kept = mirror(child, present)
    if kept then
      children[#children + 1] = kept
    end
  end
  if #children == 0 then
    return nil
  end
  return { split = node.split, scroll = node.scroll, weight = node.weight, children = children, source = node }
end

-- The tree the layout shows for `root` with these slots present: the
-- appended overflow column when windows overflow a tree with no `*`, then
-- pruned. Nodes keep `source`; the appended column and its parent have none.
local function laid_out(root, present)
  local view = mirror(root, present)
  if view and present and present[M.OVERFLOW] and not find_overflow(root) then
    view.weight = TREE_WEIGHT
    view = { split = "h", weight = 1, children = { view, { overflow = true, weight = OVERFLOW_WEIGHT } } }
  end
  return view
end

-- The nearest split on `path` in `axis` where the path's child has a
-- neighbour `step` away: depth of the split on the path, child index, neighbour index.
-- Splits the layout added (no `source`) are passed over.
local function hinge(path, axis, step)
  for depth = #path - 1, 1, -1 do
    local split = path[depth]
    if split.split == axis and split.source then
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
  return weights, total, math.floor(units + 0.5), scale
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
-- tree is laid over that area, and the edge moves by exactly that many pixels.
--
-- With `opts.present` (slot names, plus tree.OVERFLOW when windows overflow),
-- the nudge acts on the tree as the layout shows it (`boxes` over
-- `with_overflow`, pruned to `present`): the neighbour is the nearest present
-- one, fractions and pixels are of the split as laid out, so pixels stay
-- exact with empty slots or overflow showing, and the appended overflow
-- column never gives up space. Absent siblings keep their share of the split.
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
  local view = laid_out(root, opts and opts.present)
  local path = view and path_to(view, slot)
  if not path then
    if not path_to(root, slot) then
      return nil, "no slot '" .. tostring(slot) .. "' in this tree"
    end
    return nil, "slot '" .. tostring(slot) .. "' is not laid out"
  end
  local depth, i, j = hinge(path, axis, step)
  if not depth then
    return nil, string.format("nothing %s '%s' to take space from", SIDE[dir], slot)
  end

  -- Measure and limit on the split as laid out ...
  local shown = path[depth]
  local extent = opts and opts.area and extent_of(path, depth, opts.area)
  if extent and extent <= 0 then
    return nil, "the area has no room to nudge in"
  end
  local visible, total, change, scale = scaled(shown, delta, extent)
  local floor = (total + MIN_SHARE - 1) // MIN_SHARE
  change = math.min(change, math.max(visible[j] - floor, 0))
  change = math.max(change, -math.max(visible[i] - floor, 0))

  -- ... and change the same two children of the split in `root`.
  local split = shown.source
  local weights = {}
  for k, child in ipairs(split.children) do
    weights[k] = child.weight * scale
  end
  local si = index_of(split.children, shown.children[i].source)
  local sj = index_of(split.children, shown.children[j].source)
  weights[si] = weights[si] + change
  weights[sj] = weights[sj] - change

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
    local parent = path[d].source
    if parent then
      local rebuilt = copy(parent)
      rebuilt.children = {}
      for k, child in ipairs(parent.children) do
        rebuilt.children[k] = child == path[d + 1].source and node or child
      end
      node = rebuilt
    end
  end
  return node
end

return M
