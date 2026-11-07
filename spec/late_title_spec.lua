-- Test seam S2: a window whose title changes after it opened is matched again
-- (debounced per window) while it has no slot, and routed like a new window
-- once it matches; an assigned window never moves because of its title.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local SLOTS = [[
return {
  slots = { [3] = { main = "foot/deltaf", side = "foot/notes" } },
  arrangements = {
    solo = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "h[main, side]" } },
    },
  },
}
]]

describe("late titles", function()
  local hl, hyprslots

  before_each(function()
    hl = engine.stub({ "HEADLESS-2" }, { ["HEADLESS-2"] = 0 })
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hyprslots = engine.setup(SLOTS)
  end)

  after_each(engine.cleanup)

  local function open(id, class, title)
    local window = hl_stub.window(id, class, { title = title, workspace = hl.get_workspace(1) })
    hl.windows[#hl.windows + 1] = window
    hl.emit("window.open", window)
    return window
  end

  local function retitle(window, title)
    window.title = title
    hl.emit("window.title", window)
  end

  local function assignment(window)
    return engine.state(hyprslots).assignments[window.address]
  end

  it("routes a window whose title comes to match a slot, after the debounce", function()
    local window = open(1, "foot", "foot")
    assert.is_nil(assignment(window), "a generic title matches nothing")
    assert.are.equal(1, window.workspace.id)

    retitle(window, "deltaf | zellij")
    assert.are.equal(1, window.workspace.id, "nothing moves before the debounce runs out")

    hl.run_timers()
    assert.are.same({ desk = 3, slot = "main" }, assignment(window))
    assert.are.equal(3, window.workspace.id)
  end)

  it("debounces per window: a burst of title changes leaves one pending match", function()
    local window = open(1, "foot", "foot")
    local before = #hl.timers
    retitle(window, "d")
    retitle(window, "de")
    retitle(window, "deltaf | zellij")
    local pending = 0
    for i = before + 1, #hl.timers do
      if hl.timers[i].pending then
        pending = pending + 1
        assert.is_true(hl.timers[i].opts.timeout >= 100, "debounced, not deferred by a tick")
      end
    end
    assert.are.equal(1, pending)
    hl.run_timers()
    assert.are.equal(3, window.workspace.id)
  end)

  it("matches the title the window has when the debounce runs out", function()
    local window = open(1, "foot", "foot")
    retitle(window, "deltaf | zellij")
    window.title = "something else"
    hl.run_timers()
    assert.is_nil(assignment(window))
    assert.are.equal(1, window.workspace.id)
  end)

  it("never moves an assigned window because its title changed", function()
    local window = open(1, "foot", "deltaf | zellij")
    assert.are.same({ desk = 3, slot = "main" }, assignment(window))
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. window.address, workspace = "1" }))

    retitle(window, "notes | zellij")
    hl.run_timers()
    assert.are.same({ desk = 3, slot = "main" }, assignment(window))
    assert.are.equal(1, window.workspace.id)
  end)

  it("ignores a window that closed before the debounce ran out", function()
    local window = open(1, "foot", "foot")
    retitle(window, "deltaf | zellij")
    hl.windows = {}
    hl.emit("window.destroy", window)
    hl.run_timers()
    assert.are.same({}, engine.state(hyprslots).assignments)
  end)
end)
