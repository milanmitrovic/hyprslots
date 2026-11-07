-- Rebuild a weighted tree from live window boxes (ported from aerolayout's
-- record.py): the "record what I arranged by hand" path of the editor.
--
-- A tiled layout is a guillotine partition: every split can be recovered by
-- finding full-width or full-height cut lines between the boxes. `tree`
-- clusters the boxes along x (an `h` split) or else along y (a `v` split),
-- recurses into each group, and weighs the groups by their extent.
--
-- Accordions cannot be recorded: their windows overlap, so there is no cut
-- line, and the record is refused (as in aerolayout) rather than guessed.
--
-- Weights are integers, as everywhere in hyprslots. aerolayout keeps a
-- measured 1:1.37 as a decimal; here `weights` looks for the smallest integer
-- ratio close to what was measured (see below). Pure: no `hl`, no I/O.

local M = {}

-- Windows are separated by gaps; intervals closer than this along an axis
-- count as overlapping.
M.CUT_EPSILON = 3

-- aerolayout's snap: a weight within 8% (relative) of an integer, with the
-- smallest extent as 1, is that integer (a hand-dragged 1743:3342 is 1:2).
M.SNAP_TOLERANCE = 0.08

-- Failing that, the smallest multiplier m (up to MAX_MULTIPLIER) whose scaled
-- weights are all within FINE_TOLERANCE of integers (1000:1500 -> 2:3).
M.MAX_MULTIPLIER = 12
M.FINE_TOLERANCE = 0.02

-- Failing that, the smallest extent becomes FALLBACK_SCALE and the rest are
-- rounded to it, then reduced.
M.FALLBACK_SCALE = 100

local function gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

local function reduce(list)
  local common = 0
  for _, value in ipairs(list) do
    common = gcd(common, value)
  end
  if common > 1 then
    for i = 1, #list do
      list[i] = list[i] // common
    end
  end
  return list
end

local function round(n)
  return math.floor(n + 0.5)
end

local function snapped(extents, smallest, multiplier, tolerance)
  local out = {}
  for i, extent in ipairs(extents) do
    local w = extent / smallest * multiplier
    local nearest = math.max(1, round(w))
    if math.abs(w - nearest) > tolerance * nearest then
      return nil
    end
    out[i] = nearest
  end
  return out
end

-- Integer weights for a list of extents.
function M.weights(extents)
  local smallest = math.huge
  for _, extent in ipairs(extents) do
    smallest = math.min(smallest, extent)
  end
  if smallest <= 0 then
    smallest = 1
  end
  local found = snapped(extents, smallest, 1, M.SNAP_TOLERANCE)
  for multiplier = 2, M.MAX_MULTIPLIER do
    if found then
      break
    end
    found = snapped(extents, smallest, multiplier, M.FINE_TOLERANCE)
  end
  if not found then
    found = {}
    for i, extent in ipairs(extents) do
      found[i] = math.max(1, round(extent / smallest * M.FALLBACK_SCALE))
    end
  end
  return reduce(found)
end

local function interval(box, axis)
  if axis == "h" then
    return box.x, box.x + box.w
  end
  return box.y, box.y + box.h
end

-- Items grouped into runs separated by full cut lines along axis.
local function cluster(items, axis)
  local ordered = {}
  for i, item in ipairs(items) do
    ordered[i] = item
  end
  table.sort(ordered, function(a, b)
    local sa, sb = interval(a.box, axis), interval(b.box, axis)
    if sa ~= sb then
      return sa < sb
    end
    return a.slot < b.slot
  end)
  local groups, group_end = {}, nil
  for _, item in ipairs(ordered) do
    local start, finish = interval(item.box, axis)
    if group_end == nil or start >= group_end - M.CUT_EPSILON then
      groups[#groups + 1] = { item }
    else
      table.insert(groups[#groups], item)
    end
    group_end = group_end and math.max(group_end, finish) or finish
  end
  return groups
end

local function extent(group, axis)
  local low, high = math.huge, -math.huge
  for _, item in ipairs(group) do
    local start, finish = interval(item.box, axis)
    low, high = math.min(low, start), math.max(high, finish)
  end
  return high - low
end

local function build(items)
  if #items == 1 then
    return { slot = items[1].slot, weight = 1 }
  end
  for _, axis in ipairs({ "h", "v" }) do
    local groups = cluster(items, axis)
    if #groups > 1 then
      local children, extents = {}, {}
      for i, group in ipairs(groups) do
        local child = build(group)
        if not child then
          return nil
        end
        children[i] = child
        extents[i] = extent(group, axis)
      end
      for i, weight in ipairs(M.weights(extents)) do
        children[i].weight = weight
      end
      return { split = axis, weight = 1, children = children }
    end
  end
  return nil -- no cut line on either axis: not a tiled partition
end

-- A tree from slot -> { x, y, w, h }. Returns the root node, or nil and why.
function M.tree(boxes)
  local items = {}
  for slot, box in pairs(boxes) do
    items[#items + 1] = { slot = slot, box = box }
  end
  if #items == 0 then
    return nil, "no windows to record"
  end
  table.sort(items, function(a, b) return a.slot < b.slot end)
  local root = build(items)
  if not root then
    return nil, "the windows overlap, so there are no cut lines to record "
      .. "(an accordion cannot be recorded)"
  end
  return root
end

return M
