-- Test seam S2: monitors no desk knows get a desk of their own (docs/design.md
-- §8): named after them, on the most recently used layout for as many
-- screens, else a new default layout; in memory until saved.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1, ["eDP-1"] = 2, ["HEADLESS-4"] = 3 }

local ONE_DESK = [[
return {
  slots = { left = {}, main = {}, right = {} },
  specs = { [3] = { main = "t-main" } },
  desks = { big = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, workspaces = { [3] = { [1] = "h[left, main]" } } } },
}
]]

describe("a new desk for unknown monitors", function()
  local hl, hyprslots

  local function plug(name, x)
    local monitor = hl_stub.monitor(name, { id = #hl.monitors, x = x or 0, y = 0 })
    hl.monitors[#hl.monitors + 1] = monitor
    hl.emit("monitor.added", monitor)
    hl.run_timers()
    hl.run_timers()
    hl.run_timers()
  end

  local function unplug(name)
    for i, monitor in ipairs(hl.monitors) do
      if monitor.name == name then
        table.remove(hl.monitors, i)
        hl.emit("monitor.removed", monitor)
      end
    end
    hl.run_timers()
    hl.run_timers()
    hl.run_timers()
  end

  after_each(engine.cleanup)

  it("is made for monitors no desk knows, on the most recently used layout for as many screens", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup(ONE_DESK)
    assert.are.equal("big", engine.state(hyprslots).desk)
    unplug("HEADLESS-2")
    plug("HEADLESS-3")
    local state = engine.state(hyprslots)
    assert.are.equal("headless-3", state.desk)
    assert.are.equal("solo", state.layout)
    assert.are.same({ "HEADLESS-3" }, state.desks["headless-3"].monitors)
    assert.is_true(state.desks["headless-3"].auto)
    assert.are.same({ "big", "headless-3" }, state.layouts.solo.used_by)
    assert.is_true(state.dirty, "an unsaved edit")
  end)

  it("gets a new layout with the default trees when no layout has as many screens", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup(ONE_DESK)
    plug("HEADLESS-3", 2400)
    local state = engine.state(hyprslots)
    assert.are.equal("headless-2+headless-3", state.desk)
    assert.are.equal("2-screen", state.layout, "named for what it arranges, not after the desk")
    assert.are.equal(2, state.layouts[state.layout].screens)
    assert.are.equal("h[left, main, right]", state.layouts[state.layout].default["1"].tree)
    assert.is_nil(state.layouts[state.layout].default["2"])
  end)

  it("scrolls when its left-most screen is a laptop panel", function()
    hl = engine.stub({ "eDP-1" }, BLOCKS)
    hyprslots = engine.setup([[
return { slots = { left = {}, main = {}, right = {} }, desks = {}, layouts = {} }
]])
    hl.run_timers()
    local state = engine.state(hyprslots)
    assert.are.equal("built-in", state.desk)
    assert.are.equal("scroll", state.layout)
    assert.are.equal("scroll[left, main, right]", state.layouts.scroll.default["1"].tree)
  end)

  it("is not made when another hotplug finds a known desk first", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup(ONE_DESK)
    local monitor = hl_stub.monitor("HEADLESS-3", { id = 1, x = 2400 })
    hl.monitors[2] = monitor
    hl.emit("monitor.added", monitor)
    hl.run_timers() -- the desk selection finds none: a new desk is wanted ...
    hl.monitors[2] = nil
    hl.emit("monitor.removed", monitor)
    hl.run_timers()
    hl.run_timers()
    hl.run_timers()
    local state = engine.state(hyprslots)
    assert.are.equal("big", state.desk, "... but HEADLESS-2 alone is big again")
    assert.is_nil(state.desks["headless-2+headless-3"])
  end)

  it("is saved like any edit, and is no longer new afterwards", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup(ONE_DESK)
    unplug("HEADLESS-2")
    plug("HEADLESS-3")
    assert.is_true(engine.call(hyprslots, "save", "{}").ok)
    local state = engine.state(hyprslots)
    assert.is_false(state.dirty)
    assert.is_nil(state.desks["headless-3"].auto)
    assert.are.equal("solo", state.desks["headless-3"].layout)
  end)
end)
