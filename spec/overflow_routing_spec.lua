-- Test seam S2: a window that matches a slot's spec while every such slot is
-- taken goes to that desk's overflow leaf (docs/design.md §3, §7): it is
-- routed to the desk workspace of the first slot that matches it, follows
-- that desk on hotplug, takes a slot when one frees up, and is re-matched on
-- a late title like any window with no slot.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("matched windows with no free slot", function()
  local hl, hyprslots

  local function open(id, class, workspace, title)
    local window = hl_stub.window(id, class, { title = title or class, workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.get_workspace(workspace).windows = hl.get_workspace(workspace).windows + 1
    hl.emit("window.open", window)
    return window
  end

  local function workspace_of(window)
    return window.workspace.id
  end

  local function assignment(window)
    return engine.state(hyprslots).assignments[window.address]
  end

  before_each(function()
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    -- dual: side = "left", big = "h[main:2, right:1]"
    hyprslots = engine.setup(engine.TWO_SCREENS)
  end)

  after_each(engine.cleanup)

  it("go to the desk workspace of the first slot that matches them", function()
    local first = open(1, "t-left", 1)
    local extra = open(2, "t-left", 1)
    assert.are.same({ desk = 3, slot = "left" }, assignment(first))
    assert.is_nil(assignment(extra))
    assert.are.same({ 13, 13 }, { workspace_of(first), workspace_of(extra) })
  end)

  it("are laid out in that desk's overflow leaf", function()
    open(1, "t-left", 1)
    local extra = open(2, "t-left", 1)
    local ctx = hl_stub.layout_ctx({ x = 2400, y = 0, w = 1920, h = 1080 }, hl.windows)
    hl.layouts.slots.recalculate(ctx)
    -- side is just "left", so the appended column takes a quarter.
    assert.are.equal(extra, ctx.targets[2].window)
    assert.are.same({ x = 2400, y = 0, w = 1440, h = 1080 }, ctx.targets[1].placed)
    assert.are.same({ x = 3840, y = 0, w = 480, h = 1080 }, ctx.targets[2].placed)
  end)

  it("follow their desk when the screens change", function()
    open(1, "t-left", 1)
    local extra = open(2, "t-left", 1)
    local side = hl.monitors[2]
    hl.monitors = { hl.monitors[1] }
    hl.get_workspace(13).monitor = hl.monitors[1]
    hl.emit("monitor.removed", side)
    for _ = 1, 4 do
      hl.run_timers()
    end
    assert.are.equal("single", engine.state(hyprslots).arrangement)
    assert.are.equal(3, workspace_of(extra))
  end)

  it("take the slot when it frees up", function()
    local first = open(1, "t-left", 1)
    local extra = open(2, "t-left", 1)
    for i, window in ipairs(hl.windows) do
      if window == first then
        table.remove(hl.windows, i)
      end
    end
    hl.emit("window.destroy", first)
    assert.are.same({ desk = 3, slot = "left" }, assignment(extra))
    assert.are.equal(13, workspace_of(extra))
  end)

  it("stay where they open when they match no slot at all", function()
    local stranger = open(1, "firefox", 1)
    assert.are.equal(1, workspace_of(stranger))
    assert.are.same({}, hl.dispatched_of("window.move"))
  end)
end)

describe("a late title on an overflowing window", function()
  local hl, hyprslots

  after_each(engine.cleanup)

  it("moves it into a title slot that the new title matches", function()
    hl = engine.stub({ "HEADLESS-2" }, { ["HEADLESS-2"] = 0 })
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hyprslots = engine.setup([[
return {
  slots = { [2] = { term = "foot" }, [3] = { main = "foot/deltaf" } },
  arrangements = {
    solo = { screens = { big = "HEADLESS-2" }, desks = { [2] = { big = "term" }, [3] = { big = "main" } } },
  },
}
]])
    local function open(id, title)
      local window = hl_stub.window(id, "foot", { title = title, workspace = hl.get_workspace(1) })
      hl.windows[#hl.windows + 1] = window
      hl.emit("window.open", window)
      return window
    end
    open(1, "shell")
    local late = open(2, "shell")
    assert.are.equal(2, late.workspace.id, "overflows on desk 2, where foot's first slot is")

    late.title = "deltaf | zellij"
    hl.emit("window.title", late)
    hl.run_timers()
    assert.are.same({ desk = 3, slot = "main" }, engine.state(hyprslots).assignments[late.address])
    assert.are.equal(3, late.workspace.id)
  end)
end)
