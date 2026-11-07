local hl_stub = require("helpers.hl_stub")

describe("hl stub", function()
  it("reports the monitors it was given", function()
    local hl = hl_stub.new({ monitors = { { name = "HEADLESS-2" } } })

    assert.are.same({ { name = "HEADLESS-2" } }, hl.get_monitors())
  end)

  it("delivers emitted events to registered handlers", function()
    local hl = hl_stub.new()
    local seen = nil
    hl.on("monitor.added", function(monitor) seen = monitor.name end)

    hl.emit("monitor.added", { name = "HEADLESS-3" })

    assert.are.equal("HEADLESS-3", seen)
  end)
end)

describe("hl stub timers and omarchy", function()
  it("fires a oneshot timer once", function()
    local hl = hl_stub.new()
    local fired = 0
    hl.timer(function() fired = fired + 1 end, { type = "oneshot", timeout = 1 })

    hl.run_timers()
    hl.run_timers()

    assert.are.equal(1, fired)
  end)

  it("numbers desk workspaces by monitor block", function()
    local o = hl_stub.omarchy({ ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 })

    assert.are.equal(3, o.workspaces.workspace_id({ name = "HEADLESS-2" }, 3))
    assert.are.equal(13, o.workspaces.workspace_id({ name = "HEADLESS-3" }, 3))
  end)

  it("runs and records dispatched functions", function()
    local hl = hl_stub.new()
    local o = hl_stub.omarchy({})

    hl.dispatch(o.workspaces.focus(3, "HEADLESS-2"))

    assert.are.same({ { desk = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
  end)
end)
