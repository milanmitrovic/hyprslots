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
