-- The opt-in workspace bookkeeping of the hl stub (spec/helpers/hl_stub.lua).

local hl_stub = require("helpers.hl_stub")

describe("hl_stub.simulate", function()
  local hl, window

  before_each(function()
    window = hl_stub.window(1, "t-a", { workspace = 1 })
    hl = hl_stub.simulate(hl_stub.new({
      monitors = { hl_stub.monitor("A", { focused = true }), hl_stub.monitor("B") },
      windows = { window },
    }))
    hl.add_workspace(1, "A")
  end)

  it("creates the target of a window move on the focused monitor", function()
    hl.dispatch(hl.dsp.window.move({ workspace = "13", window = "address:" .. window.address, follow = false }))
    assert.are.equal(13, window.workspace.id)
    assert.are.equal("A", hl.get_workspace(13).monitor.name)
    assert.are.equal(1, hl.get_workspace("13").windows)
    assert.are.equal(0, hl.get_workspace(1).windows)
  end)

  it("counts the windows already on a workspace it adds", function()
    assert.are.equal(1, hl.get_workspace(1).windows)
    assert.are.equal(hl.get_workspace(1), window.workspace)
  end)

  it("moves a workspace to another monitor", function()
    hl.add_workspace(13, "A")
    hl.dispatch(hl.dsp.workspace.move({ workspace = "13", monitor = "B" }))
    assert.are.equal("B", hl.get_workspace(13).monitor.name)
  end)

  it("still records every dispatch", function()
    hl.dispatch(hl.dsp.workspace.move({ workspace = "1", monitor = "B" }))
    assert.are.equal(1, #hl.dispatched_of("workspace.move"))
  end)
end)
