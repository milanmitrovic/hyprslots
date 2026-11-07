-- Test seam S2: routing windows to the workspace of the screen whose branch
-- holds their slot (docs/design.md §7), across two screens.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("routing across screens", function()
  local hl, o, hyprslots

  before_each(function()
    hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(11, "HEADLESS-3")
    hyprslots = engine.setup(engine.TWO_SCREENS)
  end)

  after_each(engine.cleanup)

  local function open(id, class, workspace)
    local window = hl_stub.window(id, class, { workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.emit("window.open", window)
    return window
  end

  it("creates a missing workspace on the screen that holds the slot, not the focused one", function()
    local window = open(1, "t-left", 1)
    assert.are.equal(13, window.workspace.id)
    assert.are.equal("HEADLESS-3", hl.get_workspace(13).monitor.name)
  end)

  it("changes no focus and no screen's view while routing", function()
    open(1, "t-left", 1)
    assert.are.same({}, hl.dispatched_of("focus"))
    assert.are.same({}, o.workspaces.focused)
  end)

  it("leaves a workspace already on the right screen where it is", function()
    hl.add_workspace(13, "HEADLESS-3")
    open(1, "t-left", 1)
    assert.are.equal(13, hl.windows[1].workspace.id)
    assert.are.same({}, hl.dispatched_of("workspace.move"))
  end)

  it("puts a slot of the focused screen on its desk workspace there", function()
    local window = open(1, "t-main", 1)
    assert.are.equal(3, window.workspace.id)
    assert.are.equal("HEADLESS-2", hl.get_workspace(3).monitor.name)
    assert.are.same({}, hl.dispatched_of("workspace.move"))
  end)
  it("moves the workspace to its screen when a window rule opened the window on it elsewhere", function()
    -- A generated rule sends t-left to workspace 13; Hyprland creates it on
    -- the focused screen.
    hl.add_workspace(13, "HEADLESS-2")
    open(1, "t-left", 13)
    assert.are.equal(13, hl.windows[1].workspace.id)
    assert.are.equal("HEADLESS-3", hl.get_workspace(13).monitor.name)
    assert.are.same({}, hl.dispatched_of("window.move"))
  end)
end)
