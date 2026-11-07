local tree = require("hyprslots.tree")

local function parse(text)
  local node, err = tree.parse(text)
  assert(node, err)
  return node
end

local function area(x, y, w, h) return { x = x, y = y, w = w, h = h } end

local SCREEN = area(0, 0, 2400, 1350)

-- Widths (h) or heights (v) of the named slots after laying `node` over SCREEN.
local function sizes(node, slots, axis)
  local boxes = tree.boxes(node, SCREEN)
  local out = {}
  for i, slot in ipairs(slots) do
    out[i] = boxes[slot][axis or "w"]
  end
  return out
end

local function nudged(text, slot, dir, delta, opts)
  local node, err = tree.nudge(parse(text), slot, dir, delta, opts)
  assert(node, err)
  return node
end

describe("tree.nudge", function()
  it("grows a slot toward its right neighbour by a fraction of the split", function()
    -- 0.1 of 2400 px moves the a|b edge 240 px right.
    assert.are.same({ 1440, 960 }, sizes(nudged("h[a, b]", "a", "r", 0.1), { "a", "b" }))
  end)

  it("leaves the tree it was given untouched", function()
    local before = parse("h[a, b:3]")
    tree.nudge(before, "a", "r", 0.1)
    assert.are.same(parse("h[a, b:3]"), before)
  end)

  it("keeps weights as the smallest exact integers", function()
    local node = nudged("h[a, b]", "a", "r", 0.1)
    assert.are.same({ 3, 2 }, { node.children[1].weight, node.children[2].weight })
    assert.are.equal("integer", math.type(node.children[1].weight))
  end)

  it("grows toward the left by taking from the left neighbour", function()
    assert.are.same({ 300, 900, 1200 }, sizes(nudged("h[a:2, b:2, c:4]", "b", "l", 0.125), { "a", "b", "c" }))
  end)
  it("adjusts the nearest ancestor split in the nudge's axis", function()
    -- a sits in an h split inside a v split; growing down moves the v edge.
    local node = nudged("v[h[a, b], c]", "a", "d", 0.2)
    assert.are.same({ 945, 405 }, sizes(node, { "a", "c" }, "h"))
    assert.are.same({ 945, 945 }, sizes(node, { "a", "b" }, "h"), "a and b share the row")
    assert.are.same({ 1200, 1200 }, sizes(node, { "a", "b" }), "the h split is untouched")
  end)

  it("climbs past a split where the slot has no neighbour on that side", function()
    -- c is first in its own h split, so growing left moves the outer a|v edge.
    local node = nudged("h[a, v[b, h[c, d]]]", "c", "l", 0.25)
    assert.are.same({ 600, 900, 900 }, sizes(node, { "a", "c", "d" }))
  end)

  it("shrinks the slot for a negative delta", function()
    assert.are.same({ 960, 1440 }, sizes(nudged("h[a, b]", "a", "r", -0.1), { "a", "b" }))
  end)

  local function refuses(text, slot, dir, delta, pattern)
    local node, err = tree.nudge(parse(text), slot, dir, delta)
    assert.is_nil(node)
    assert.matches(pattern, err)
  end

  it("refuses when nothing lies on that side", function()
    refuses("h[a, b]", "b", "r", 0.1, "nothing right of 'b'")
    refuses("h[a, b]", "a", "u", 0.1, "nothing above 'a'")
    refuses("a", "a", "l", 0.1, "nothing left of 'a'")
  end)

  it("refuses an unknown slot or direction", function()
    refuses("h[a, b]", "z", "r", 0.1, "no slot 'z'")
    refuses("h[a, b]", "a", "x", 0.1, "direction")
  end)

  it("stops each side at a minimum share of the split", function()
    -- At most down to 5% of the split: 120 of 2400 px.
    assert.are.same({ 2280, 120 }, sizes(nudged("h[a, b]", "a", "r", 0.9), { "a", "b" }))
    assert.are.same({ 120, 2280 }, sizes(nudged("h[a, b]", "a", "r", -0.9), { "a", "b" }))
  end)
  describe("in pixels", function()
    it("moves the edge by exactly that many pixels of the given area", function()
      local px = { area = SCREEN }
      assert.are.same({ 1300, 1100 }, sizes(nudged("h[a, b]", "a", "r", 100, px), { "a", "b" }))
      assert.are.same({ 807, 793, 800 }, sizes(nudged("h[a, b, c]", "a", "r", 7, px), { "a", "b", "c" }))
      assert.are.same({ 693, 907, 800 }, sizes(nudged("h[a, b, c]", "b", "l", 107, px), { "a", "b", "c" }))
    end)

    it("measures the split being adjusted, not the whole area", function()
      -- The v split is the right half (1200 px wide, 1350 tall); 100 px down.
      local node = nudged("h[a, v[b, c]]", "b", "d", 100, { area = SCREEN })
      assert.are.same({ 775, 575 }, sizes(node, { "b", "c" }, "h"))
    end)

    it("keeps weights small after repeated nudges", function()
      local node = parse("h[a, b, c]")
      for _ = 1, 50 do
        node = assert(tree.nudge(node, "a", "r", 3, { area = area(0, 0, 2561, 1439) }))
        node = assert(tree.nudge(node, "c", "l", 0.01))
      end
      for _, child in ipairs(node.children) do
        assert.is_true(math.type(child.weight) == "integer" and child.weight < 2 ^ 40, tostring(child.weight))
      end
    end)
  end)
end)

describe("tree.nudge over the laid-out tree (opts.present)", function()
  -- Boxes the way the layout computes them: overflow column appended when the
  -- tree has no *, then pruned to the slots present.
  local function laid(node, present, slots, axis)
    local boxes = tree.boxes(tree.with_overflow(node), SCREEN, present)
    local out = {}
    for i, slot in ipairs(slots) do
      out[i] = boxes[slot][axis or "w"]
    end
    return out
  end

  it("moves the edge by exact pixels with the appended overflow column showing", function()
    -- h[h[a, b]:3, *:1]: the tree gets 1800 px, a and b 900 each.
    local present = { a = true, b = true, [tree.OVERFLOW] = true }
    local node = nudged("h[a, b]", "a", "r", 100, { area = SCREEN, present = present })
    assert.are.same({ 1000, 800, 600 }, laid(node, present, { "a", "b", tree.OVERFLOW }))
  end)

  it("moves the edge by exact pixels with an empty slot closed up", function()
    -- c is absent: a and b share 2400 px, 1200 each.
    local present = { a = true, b = true }
    local node = nudged("h[a, b, c]", "a", "r", 100, { area = SCREEN, present = present })
    assert.are.same({ 1300, 1100 }, laid(node, present, { "a", "b" }))
  end)

  it("takes from the next present neighbour, past an empty slot", function()
    local present = { a = true, c = true }
    local node = nudged("h[a, b, c]", "a", "r", 100, { area = SCREEN, present = present })
    assert.are.same({ 1300, 1100 }, laid(node, present, { "a", "c" }))
  end)

  it("never takes from the appended overflow column", function()
    local present = { a = true, b = true, [tree.OVERFLOW] = true }
    local node, err = tree.nudge(parse("h[a, b]"), "b", "r", 100, { area = SCREEN, present = present })
    assert.is_nil(node)
    assert.matches("nothing right of 'b'", err)
  end)

  it("takes from an explicit overflow leaf like any neighbour", function()
    local present = { a = true, [tree.OVERFLOW] = true }
    local node = nudged("h[*, a]", "a", "l", 100, { area = SCREEN, present = present })
    assert.are.same({ 1100, 1300 }, laid(node, present, { tree.OVERFLOW, "a" }))
  end)

  it("resizes an accordion member's whole container", function()
    local present = { x = true, y = true, z = true }
    local node = nudged("h[a[x, y], z]", "y", "r", 100, { area = SCREEN, present = present })
    assert.are.same({ 1300, 1300, 1100 }, laid(node, present, { "x", "y", "z" }))
    assert.is_true(node.children[1].accordion)
  end)

  it("takes a fraction of the split as laid out", function()
    local present = { a = true, b = true }
    local node = nudged("h[a, b, c]", "a", "r", 0.1, { present = present })
    assert.are.same({ 1440, 960 }, laid(node, present, { "a", "b" }))
  end)
end)
