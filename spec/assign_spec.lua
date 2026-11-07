local assign = require("hyprslots.assign")
local config = require("hyprslots.config")

local function cfg_with(slots)
  return assert(config.validate({ slots = slots }))
end

local function win(id, class)
  return { address = "0x" .. id, class = class, stable_id = id }
end

local cfg = cfg_with({
  [3] = { left = "t-left", main = "t-main", right = "t-right" },
  [4] = { notes = "t-main" },
})

describe("assign.solve", function()
  it("puts each window in the slot whose spec matches it", function()
    local result = assign.solve(cfg, { win(1, "t-right"), win(2, "t-left"), win(3, "t-main") })
    assert.are.same({
      ["0x1"] = { desk = 3, slot = "right" },
      ["0x2"] = { desk = 3, slot = "left" },
      ["0x3"] = { desk = 3, slot = "main" },
    }, result)
  end)

  it("leaves a window that matches nothing unassigned", function()
    assert.are.same({}, assign.solve(cfg, { win(1, "firefox") }))
  end)

  it("claims a slot only once, then tries the next desk's matching slot", function()
    local result = assign.solve(cfg, { win(1, "t-main"), win(2, "t-main"), win(3, "t-main") })
    assert.are.same({ desk = 3, slot = "main" }, result["0x1"])
    assert.are.same({ desk = 4, slot = "notes" }, result["0x2"])
    assert.is_nil(result["0x3"])
  end)

  it("gives a contested slot to the oldest window, whatever the input order", function()
    local a = assign.solve(cfg, { win(9, "t-main"), win(5, "t-main") })
    local b = assign.solve(cfg, { win(5, "t-main"), win(9, "t-main") })
    assert.are.same(a, b)
    assert.are.same({ desk = 3, slot = "main" }, a["0x5"])
  end)

  it("keeps a previous assignment that still holds (assignment is sticky)", function()
    local previous = { ["0x9"] = { desk = 3, slot = "main" } }
    local result = assign.solve(cfg, { win(5, "t-main"), win(9, "t-main") }, previous)
    assert.are.same({ desk = 3, slot = "main" }, result["0x9"])
    assert.are.same({ desk = 4, slot = "notes" }, result["0x5"])
  end)

  it("drops a previous assignment the config no longer supports", function()
    local previous = { ["0x1"] = { desk = 3, slot = "gone" }, ["0x2"] = { desk = 3, slot = "left" } }
    local result = assign.solve(cfg, { win(1, "t-main"), win(2, "t-main") }, previous)
    assert.are.same({ desk = 3, slot = "main" }, result["0x1"])
    assert.are.same({ desk = 4, slot = "notes" }, result["0x2"], "t-main no longer matches left")
  end)

  it("forgets windows that are gone", function()
    local previous = { ["0x7"] = { desk = 3, slot = "main" } }
    assert.are.same({}, assign.solve(cfg, {}, previous))
  end)

  it("does not change the previous table", function()
    local previous = { ["0x1"] = { desk = 3, slot = "main" } }
    assign.solve(cfg, { win(2, "t-main") }, previous)
    assert.are.same({ ["0x1"] = { desk = 3, slot = "main" } }, previous)
  end)
end)

describe("assign.claim", function()
  it("gives one new window the first free matching slot", function()
    local current = { ["0x1"] = { desk = 3, slot = "main" } }
    assert.are.same({ desk = 4, slot = "notes" }, assign.claim(cfg, current, win(2, "t-main")))
  end)

  it("returns the window's existing slot", function()
    local current = { ["0x1"] = { desk = 3, slot = "main" } }
    assert.are.same({ desk = 3, slot = "main" }, assign.claim(cfg, current, win(1, "t-main")))
  end)

  it("returns nil when every matching slot is taken", function()
    local current = { ["0x1"] = { desk = 3, slot = "left" } }
    assert.is_nil(assign.claim(cfg, current, win(2, "t-left")))
  end)
end)

describe("assign precedence with title specs", function()
  local titled = cfg_with({
    [2] = { term = "foot" },
    [3] = { main = "foot/deltaf", notes = "foot/notes" },
  })

  local function titled_win(id, title)
    return { address = "0x" .. id, class = "foot", title = title, stable_id = id }
  end

  it("gives a window matching several specs the first desk's slot, in config order", function()
    assert.are.same({ desk = 2, slot = "term" }, assign.claim(titled, {}, titled_win(1, "deltaf | zellij")))
  end)

  it("falls through to the next desk's matching spec when the first is taken", function()
    local current = { ["0x9"] = { desk = 2, slot = "term" } }
    assert.are.same({ desk = 3, slot = "main" }, assign.claim(titled, current, titled_win(1, "deltaf | zellij")))
    assert.are.same({ desk = 3, slot = "notes" }, assign.claim(titled, current, titled_win(2, "notes | x")))
    assert.is_nil(assign.claim(titled, current, titled_win(3, "other | x")))
  end)

  it("keeps an assignment when the title changes (claim never re-matches)", function()
    local current = { ["0x1"] = { desk = 3, slot = "main" } }
    assert.are.same({ desk = 3, slot = "main" }, assign.claim(titled, current, titled_win(1, "notes | x")))
  end)
end)
