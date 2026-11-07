-- Test seam S3: groups.plan, the moves that make each accordion one group.

local groups = require("hyprslots.groups")

-- A window on the workspace: w("0x1", "x") is slot x, ungrouped;
-- w("0x1", "x", { "0x1", "0x2" }) is in the group 0x1, 0x2.
local function w(address, slot, group)
  return { address = address, slot = slot, group = group }
end

local function plan(accordions, windows)
  return groups.plan(accordions, windows)
end

local function out(a) return { op = "out", window = a } end
local function create(a) return { op = "create", window = a } end
local function add(a, into) return { op = "add", window = a, into = into } end

describe("groups.plan", function()
  local XYZ = { { "x", "y", "z" } }

  it("groups an accordion's windows around the first, in accordion order", function()
    assert.are.same({ create("0x1"), add("0x3", "0x1"), add("0x2", "0x1") },
      plan(XYZ, { w("0x2", "z"), w("0x1", "x"), w("0x3", "y") }))
  end)

  it("does nothing once the accordion is one group", function()
    assert.are.same({}, plan(XYZ, { w("0x1", "x", { "0x1", "0x2" }), w("0x2", "y", { "0x1", "0x2" }) }))
  end)

  it("adds a newcomer to the existing group", function()
    local g = { "0x2", "0x1" }
    assert.are.same({ add("0x3", "0x1") },
      plan(XYZ, { w("0x1", "x", g), w("0x2", "y", g), w("0x3", "z") }))
  end)

  it("leaves a lone member alone", function()
    assert.are.same({}, plan(XYZ, { w("0x1", "x"), w("0x9", nil) }))
  end)

  it("takes a window that is no member out of the accordion's group", function()
    local g = { "0x1", "0x9", "0x2" }
    assert.are.same({ out("0x9") },
      plan(XYZ, { w("0x1", "x", g), w("0x2", "y", g), w("0x9", nil, g) }))
  end)

  it("takes another slot's window out of the accordion's group", function()
    local g = { "0x1", "0x4" }
    assert.are.same({ out("0x4") }, plan(XYZ, { w("0x1", "x", g), w("0x4", "d", g) }))
  end)

  it("re-groups a member the user dragged out", function()
    local g = { "0x1", "0x2" }
    assert.are.same({ add("0x3", "0x1") },
      plan(XYZ, { w("0x1", "x", g), w("0x2", "y", g), w("0x3", "z") }))
  end)

  it("merges an accordion split over two groups into the first", function()
    local g1, g2 = { "0x1", "0x2" }, { "0x3", "0x9" }
    assert.are.same({ out("0x3"), add("0x3", "0x1") },
      plan(XYZ, { w("0x1", "x", g1), w("0x2", "y", g1), w("0x3", "z", g2), w("0x9", nil, g2) }))
  end)

  it("leaves a group of windows with no slot alone", function()
    local g = { "0x8", "0x9" }
    assert.are.same({}, plan(XYZ, { w("0x8", nil, g), w("0x9", nil, g) }))
  end)

  it("adopts a group a member is in, taking the stranger out", function()
    local g = { "0x9", "0x1" }
    assert.are.same({ out("0x9"), add("0x2", "0x1") },
      plan(XYZ, { w("0x9", nil, g), w("0x1", "x", g), w("0x2", "y") }))
  end)

  it("keeps two accordions in two groups", function()
    local acc = { { "x", "y" }, { "p", "q" } }
    assert.are.same({ out("0x3"), create("0x3"), add("0x4", "0x3") },
      plan(acc, {
        w("0x1", "x", { "0x1", "0x2", "0x3" }), w("0x2", "y", { "0x1", "0x2", "0x3" }),
        w("0x3", "p", { "0x1", "0x2", "0x3" }), w("0x4", "q"),
      }))
  end)

  it("plans nothing for a tree with no accordion", function()
    assert.are.same({}, plan({}, { w("0x1", "x"), w("0x2", "y") }))
  end)
end)
