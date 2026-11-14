-- Test seam S3: which workspace ids the active desk's screens take
-- (docs/design.md §5): screen i holds block i-1 (workspaces (i-1)*10+1 ..
-- (i-1)*10+10), and blocks.plan says how to bring the workspaces there.

local blocks = require("hyprslots.blocks")

local P = blocks.PARK

local function ws(id, monitor, windows)
  return { id = id, monitor = monitor, windows = windows == nil and 1 or windows }
end

describe("blocks.of_screens", function()
  it("gives screen i block i-1", function()
    assert.are.same({ ["eDP-1"] = 0, ["DP-2"] = 1 }, blocks.of_screens({ "eDP-1", "DP-2" }))
  end)
end)

describe("blocks.plan", function()
  it("leaves workspaces already in their screen's block as they are", function()
    assert.are.same({}, blocks.plan({ ws(3, "A"), ws(13, "B"), ws(11, "B", 0) }, { "A", "B" }))
  end)

  it("renumbers a lone screen's workspaces into block 0, keeping their number", function()
    assert.are.same({
      { op = "rename", id = 12, to = 2 },
      { op = "rename", id = 17, to = 7 },
      { op = "rename", id = 20, to = 10 },
    }, blocks.plan({ ws(17, "DP-2"), ws(12, "DP-2"), ws(20, "DP-2") }, { "DP-2" }))
  end)

  it("puts a workspace's windows into the one already holding its number", function()
    assert.are.same({ { op = "merge", id = 13, into = 3 } }, blocks.plan({ ws(3, "B"), ws(13, "B") }, { "B" }))
  end)

  it("brings workspaces from a monitor no screen is (turned off) to the screen of their block", function()
    -- The live case: eDP-1 off, its workspaces left on it; DP-2 alone was block 1.
    assert.are.same({
      { op = "move", id = 1, monitor = "DP-2" },
      { op = "move", id = 5, monitor = "DP-2" },
      { op = "merge", id = 11, into = 1 },
      { op = "rename", id = 12, to = 2 },
    }, blocks.plan({ ws(1, "eDP-1"), ws(5, "eDP-1", 2), ws(11, "DP-2", 3), ws(12, "DP-2") }, { "DP-2" }))
  end)

  it("sends workspaces whose block has no screen to screen 1", function()
    assert.are.same({
      { op = "move", id = 23, monitor = "A" },
      { op = "rename", id = 23, to = 3 },
    }, blocks.plan({ ws(23, nil) }, { "A" }))
  end)

  it("swaps two screens' blocks without mixing their windows", function()
    -- B moved left of A: B is screen 1 now.
    assert.are.same({
      { op = "rename", id = 1, to = P + 1 },
      { op = "rename", id = 11, to = P + 11 },
      { op = "rename", id = P + 11, to = 1 },
      { op = "rename", id = P + 1, to = 11 },
    }, blocks.plan({ ws(1, "A"), ws(11, "B") }, { "B", "A" }))
  end)

  it("puts a workspace holding a needed number on the screen first, even an empty one", function()
    -- eDP-1 is off and still shows an empty workspace 1.
    assert.are.same({
      { op = "move", id = 1, monitor = "DP-2" },
      { op = "merge", id = 11, into = 1 },
    }, blocks.plan({ ws(1, "eDP-1", 0), ws(11, "DP-2") }, { "DP-2" }))
  end)

  it("leaves empty workspaces and special ones alone", function()
    assert.are.same({}, blocks.plan({ ws(12, "DP-2", 0), ws(-98, "eDP-1") }, { "DP-2" }))
  end)

  it("plans nothing without screens", function()
    assert.are.same({}, blocks.plan({ ws(12, "DP-2") }, {}))
  end)
end)
