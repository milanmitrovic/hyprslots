-- Test seam S3: which monitors a desk's selectors find, and the order its
-- screens are numbered in (docs/design.md §8).

local desk = require("hyprslots.desk")

local function monitor(name, fields)
  local m = { name = name, description = "", serial = "", x = 0, y = 0 }
  for key, value in pairs(fields or {}) do
    m[key] = value
  end
  return m
end

local ODYSSEY = "Samsung Electric Company Odyssey G95NC H1AK500000"

describe("desk.match", function()
  it("finds a monitor for every selector when they are exactly the connected ones", function()
    local a, b = monitor("HEADLESS-2"), monitor("HEADLESS-3")
    assert.are.same({ ["HEADLESS-3"] = b, ["HEADLESS-2"] = a }, desk.match({ "HEADLESS-3", "HEADLESS-2" }, { a, b }))
  end)

  it("finds nothing when a monitor is left over, a selector finds none, or nothing is connected", function()
    assert.is_nil(desk.match({ "HEADLESS-2" }, { monitor("HEADLESS-2"), monitor("HEADLESS-4") }))
    assert.is_nil(desk.match({ "HEADLESS-3" }, { monitor("HEADLESS-2") }))
    assert.is_nil(desk.match({}, {}))
  end)

  it("matches by description, by serial, and the laptop panel by connector", function()
    local odyssey = monitor("DP-1", { description = ODYSSEY, serial = "H1AK500000" })
    assert.are.equal(odyssey, desk.match({ ODYSSEY }, { odyssey })[ODYSSEY])
    assert.are.equal(odyssey, desk.match({ "H1AK500000" }, { odyssey })["H1AK500000"])
    assert.is_not_nil(desk.match({ "eDP-1" }, { monitor("eDP-1") }))
  end)

  it("prefers a description match over a connector match", function()
    -- A monitor described as "DP-2" beats the one plugged into DP-2.
    assert.is_nil(desk.match({ "DP-2", "DP-1" }, { monitor("DP-1", { description = "DP-2" }),
      monitor("DP-2", { description = "Other" }) }), "DP-2 takes DP-1 by description, so DP-1 has nothing left")
  end)

  it("needs a distinct monitor for every selector", function()
    assert.is_nil(desk.match({ "HEADLESS-2", "HEADLESS-2" }, { monitor("HEADLESS-2"), monitor("HEADLESS-3") }))
  end)
end)

describe("desk.order", function()
  it("numbers monitors left to right, then top to bottom, then by connector", function()
    local names = {}
    for i, m in ipairs(desk.order({ monitor("C", { x = 10 }), monitor("B", { y = 5 }), monitor("A", { y = 5 }),
      monitor("D") })) do
      names[i] = m.name
    end
    assert.are.same({ "D", "A", "B", "C" }, names)
  end)
end)

describe("desk.usable", function()
  it("leaves Hyprland's FALLBACK placeholder out", function()
    local list = desk.usable({ monitor("FALLBACK"), monitor("HEADLESS-2") })
    assert.are.equal(1, #list)
    assert.are.equal("HEADLESS-2", list[1].name)
  end)
end)
