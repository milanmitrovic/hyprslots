local log = require("hyprslots.log")

describe("log", function()
  it("keeps entries in order with a level and sequence number", function()
    local l = log.new()
    l:info("window %s -> %d", "t-main", 3)
    l:error("boom")
    assert.are.same({
      { seq = 1, level = "info", text = "window t-main -> 3" },
      { seq = 2, level = "error", text = "boom" },
    }, l:entries())
  end)

  it("keeps only the newest entries once full", function()
    local l = log.new({ capacity = 3 })
    for i = 1, 5 do
      l:info("entry %d", i)
    end
    local texts = {}
    for _, entry in ipairs(l:entries()) do
      texts[#texts + 1] = entry.text
    end
    assert.are.same({ "entry 3", "entry 4", "entry 5" }, texts)
    assert.are.equal(5, l:entries()[3].seq)
  end)

  it("formats lines for dump", function()
    local l = log.new()
    l:warn("careful")
    assert.are.same({ "#1 warn careful" }, l:lines())
  end)

  it("passes every entry to a sink", function()
    local seen = {}
    local l = log.new({ sink = function(entry) seen[#seen + 1] = entry.level .. ":" .. entry.text end })
    l:info("hello")
    assert.are.same({ "info:hello" }, seen)
  end)

  it("survives a bad format string", function()
    local l = log.new()
    l:info("%d", "not a number")
    assert.matches("not a number", l:entries()[1].text)
  end)

  it("survives a sink that fails", function()
    local l = log.new({ sink = function() error("sink broke") end })
    l:info("still logged")
    assert.are.equal("still logged", l:entries()[1].text)
  end)
end)
