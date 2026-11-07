local arrangement = require("hyprslots.arrangement")
local config = require("hyprslots.config")

local function cfg_with(arrangements)
  local slots = { [3] = { a = "a" } }
  return assert(config.validate({ slots = slots, arrangements = arrangements }))
end

local function monitor(name, description, serial)
  return { name = name, description = description or "", serial = serial or "" }
end

local ODYSSEY = "Samsung Electric Company Odyssey G95NC H1AK500000"

describe("arrangement.select", function()
  local cfg = cfg_with({
    dual = { screens = { big = "HEADLESS-2", side = "HEADLESS-3" } },
    single = { screens = { big = "HEADLESS-2" } },
  })

  it("picks the arrangement whose screens are exactly the connected monitors", function()
    local active = arrangement.select(cfg, { monitor("HEADLESS-2"), monitor("HEADLESS-3") })
    assert.are.equal("dual", active.name)
    assert.are.same({ big = "HEADLESS-2", side = "HEADLESS-3" }, active.monitors)
    assert.are.same({ ["HEADLESS-2"] = "big", ["HEADLESS-3"] = "side" }, active.roles)
  end)

  it("switches to the smaller arrangement when a screen is gone", function()
    assert.are.equal("single", arrangement.select(cfg, { monitor("HEADLESS-2") }).name)
  end)

  it("picks nothing when a monitor is left over", function()
    assert.is_nil(arrangement.select(cfg, { monitor("HEADLESS-2"), monitor("HEADLESS-4") }))
  end)

  it("picks nothing when a role finds no monitor", function()
    assert.is_nil(arrangement.select(cfg, { monitor("HEADLESS-3") }))
  end)

  it("picks nothing with no monitors", function()
    assert.is_nil(arrangement.select(cfg, {}))
  end)

  it("matches a screen by description", function()
    local c = cfg_with({ home = { screens = { big = ODYSSEY } } })
    assert.are.equal("DP-1", arrangement.select(c, { monitor("DP-1", ODYSSEY, "H1AK500000") }).monitors.big)
  end)

  it("matches a screen by serial", function()
    local c = cfg_with({ home = { screens = { big = "H1AK500000" } } })
    assert.are.equal("DP-1", arrangement.select(c, { monitor("DP-1", ODYSSEY, "H1AK500000") }).monitors.big)
  end)

  it("matches the laptop panel by connector, since eDP-1 has no description", function()
    local c = cfg_with({ laptop = { screens = { laptop = "eDP-1" } } })
    assert.are.equal("eDP-1", arrangement.select(c, { monitor("eDP-1") }).monitors.laptop)
  end)

  it("prefers a description match over a connector match", function()
    -- A monitor described as "DP-2" beats the one plugged into DP-2.
    local c = cfg_with({ odd = { screens = { x = "DP-2", y = "DP-1" } } })
    local active = arrangement.select(c, { monitor("DP-1", "DP-2"), monitor("DP-2", "Other") })
    assert.is_nil(active, "x takes DP-1 by description, so y has nothing left")
  end)

  it("never matches an empty description or serial", function()
    local c = cfg_with({ x = { screens = { big = "HEADLESS-2" } } })
    local active = arrangement.select(c, { monitor("HEADLESS-2", "", "") })
    assert.are.equal("HEADLESS-2", active.monitors.big)
  end)

  it("needs a distinct monitor for every role", function()
    local c = cfg_with({ twice = { screens = { a = "HEADLESS-2", b = "HEADLESS-2" } } })
    assert.is_nil(arrangement.select(c, { monitor("HEADLESS-2") }))
  end)

  it("breaks a tie between equal arrangements by name", function()
    local c = cfg_with({
      zeta = { screens = { big = "HEADLESS-2" } },
      alpha = { screens = { main = "HEADLESS-2" } },
    })
    assert.are.equal("alpha", arrangement.select(c, { monitor("HEADLESS-2") }).name)
  end)

  it("hands back the arrangement itself", function()
    local active = arrangement.select(cfg, { monitor("HEADLESS-2") })
    assert.are.equal(cfg.arrangements.single, active.arrangement)
  end)
end)
