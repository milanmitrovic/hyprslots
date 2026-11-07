-- Recording live window boxes back into a weighted tree (ported from
-- aerolayout's record.py and tests/test_record.py).

local record = require("hyprslots.record")
local tree = require("hyprslots.tree")
local serialize = require("hyprslots.serialize")

local function box(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

local function weights(node)
  local out = {}
  for i, child in ipairs(node.children) do
    out[i] = child.weight
  end
  return out
end

local function recorded(boxes)
  local node, err = record.tree(boxes)
  assert(node, err)
  return node
end

describe("record.tree", function()
  it("snaps two hand-dragged columns to 1:2", function()
    -- Real frames observed live on macOS: 1743 vs 3342, meant as 1:2.
    local node = recorded({ left = box(10, 57, 1743, 1372), main = box(1768, 57, 3342, 1372) })
    assert.are.equal("h", node.split)
    assert.are.same({ "left", "main" }, tree.slots(node))
    assert.are.same({ 1, 2 }, weights(node))
  end)

  it("reads three columns 1:2:1 across gaps", function()
    local node = recorded({
      left = box(0, 0, 1250, 1400),
      main = box(1265, 0, 2540, 1400),
      right = box(3820, 0, 1250, 1400),
    })
    assert.are.equal("h", node.split)
    assert.are.same({ 1, 2, 1 }, weights(node))
  end)

  it("reads a stacked column next to a main pane", function()
    local node = recorded({
      left = box(0, 0, 1700, 690),
      right = box(0, 705, 1700, 695),
      main = box(1715, 0, 3400, 1400),
    })
    assert.are.equal("h", node.split)
    local stack, main = node.children[1], node.children[2]
    assert.are.equal("v", stack.split)
    assert.are.same({ "left", "right" }, tree.slots(stack))
    assert.are.equal("main", main.slot)
    assert.are.same({ 1, 2 }, weights(node))
  end)

  it("reads a vertical split", function()
    local node = recorded({ top = box(0, 0, 5100, 700), bottom = box(0, 715, 5100, 700) })
    assert.are.equal("v", node.split)
    assert.are.same({ "top", "bottom" }, tree.slots(node))
  end)

  it("reads exactly what tree.boxes laid out, to the integer weight", function()
    for _, text in ipairs({
      "h[a, b:2, c]",
      "h[v[a, b:3]:2, c]",
      "v[top, h[a:3, b:5]:2]",
      "h[v[a, b], v[c, d]:3]",
      "h[a:2, b:3]",
    }) do
      local node = assert(tree.parse(text))
      local laid = tree.boxes(node, { x = 0, y = 0, w = 2400, h = 1350 })
      assert.are.equal(text, serialize.tree(recorded(laid)), "recording " .. text)
    end
  end)

  it("records one window as a bare slot", function()
    assert.are.same({ slot = "a", weight = 1 }, recorded({ a = box(0, 0, 100, 100) }))
  end)

  it("refuses no windows at all", function()
    local node, err = record.tree({})
    assert.is_nil(node)
    assert.matches("no window", err)
  end)

  it("refuses overlapping windows (an accordion has no cut lines)", function()
    local node, err = record.tree({ a = box(0, 0, 3000, 1400), b = box(100, 0, 3000, 1400) })
    assert.is_nil(node)
    assert.matches("overlap", err)
  end)

  it("lets a subgroup without cut lines fail the whole record", function()
    local node = record.tree({
      left = box(0, 0, 1000, 1400),
      main = box(1015, 0, 2000, 1400),
      right = box(1500, 200, 2000, 1000),
    })
    assert.is_nil(node)
  end)
end)

describe("record.weights", function()
  it("snaps near-integer ratios, as aerolayout does", function()
    assert.are.same({ 1, 2 }, record.weights({ 1743, 3342 }))
    assert.are.same({ 1, 1 }, record.weights({ 1000, 1000 }))
  end)

  it("finds a small integer ratio for an exact fraction", function()
    assert.are.same({ 2, 3 }, record.weights({ 1000, 1500 }))
    assert.are.same({ 3, 5 }, record.weights({ 900, 1500 }))
  end)

  it("keeps a ratio that has no small integer form close", function()
    local w = record.weights({ 1000, 1370 })
    local measured, kept = 1370 / 1000, w[2] / w[1]
    assert.is_true(math.abs(kept - measured) / measured < 0.02, "kept " .. w[1] .. ":" .. w[2])
  end)

  it("always gives positive integers", function()
    for _, w in ipairs(record.weights({ 7, 1999, 333 })) do
      assert.are.equal("integer", math.type(w))
      assert.is_true(w >= 1)
    end
  end)
end)
