-- Test seam S3: which monitors a desk's selectors find, and the order its
-- screens are numbered in (docs/design.md §8).

local config = require("hyprslots.config")
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

-- A validated config with these desks (name -> monitors list) and one
-- layout per screen count ("one", "two", ...) for them to use.
local COUNT_NAMES = { "one", "two", "three" }

local function cfg_with(desks)
  local layouts, raw_desks = {}, {}
  for name, monitors in pairs(desks) do
    local layout = COUNT_NAMES[#monitors]
    layouts[layout] = { screens = #monitors }
    raw_desks[name] = { monitors = monitors, layout = layout }
  end
  return assert(config.validate({ slots = { a = {} }, desks = raw_desks, layouts = layouts }))
end

describe("desk.select", function()
  local cfg = cfg_with({
    dual = { "HEADLESS-2", "HEADLESS-3" },
    single = { "HEADLESS-2" },
  })

  it("picks the desk whose monitors are exactly the connected ones", function()
    local active = desk.select(cfg, { monitor("HEADLESS-2"), monitor("HEADLESS-3", { x = 2400 }) })
    assert.are.equal("dual", active.desk)
    assert.are.equal("two", active.layout)
    assert.are.equal(cfg.layouts.two, active.entry)
  end)

  it("numbers the screens left to right by position, whatever order the desk lists them in", function()
    local c = cfg_with({ dual = { "HEADLESS-3", "HEADLESS-2" } })
    local active = desk.select(c, { monitor("HEADLESS-3", { x = 2400 }), monitor("HEADLESS-2", { x = 0 }) })
    assert.are.same({ "HEADLESS-2", "HEADLESS-3" }, active.monitors)
    assert.are.same({ ["HEADLESS-2"] = 1, ["HEADLESS-3"] = 2 }, active.screens)
  end)

  it("orders screens at the same x top to bottom", function()
    local c = cfg_with({ stack = { "A", "B" } })
    local active = desk.select(c, { monitor("A", { y = 1080 }), monitor("B", { y = 0 }) })
    assert.are.same({ "B", "A" }, active.monitors)
  end)

  it("switches to the smaller desk when a monitor is gone", function()
    assert.are.equal("single", desk.select(cfg, { monitor("HEADLESS-2") }).desk)
  end)

  it("picks nothing when a monitor is left over", function()
    assert.is_nil(desk.select(cfg, { monitor("HEADLESS-2"), monitor("HEADLESS-4") }))
  end)

  it("picks nothing when a selector finds no monitor", function()
    assert.is_nil(desk.select(cfg, { monitor("HEADLESS-3") }))
  end)

  it("picks nothing with no monitors, and leaves Hyprland's FALLBACK output out", function()
    assert.is_nil(desk.select(cfg, {}))
    assert.are.equal("single", desk.select(cfg, { monitor("HEADLESS-2"), monitor("FALLBACK") }).desk)
  end)

  it("matches a monitor by description, by serial, and the laptop panel by connector", function()
    local c = cfg_with({ home = { ODYSSEY }, serial = { "H1AK500001" }, laptop = { "eDP-1" } })
    assert.are.equal("home", desk.select(c, { monitor("DP-1", { description = ODYSSEY, serial = "H1AK500000" }) }).desk)
    assert.are.equal("serial", desk.select(c, { monitor("DP-2", { description = "Other", serial = "H1AK500001" }) }).desk)
    assert.are.equal("laptop", desk.select(c, { monitor("eDP-1") }).desk)
  end)

  it("prefers a description match over a connector match", function()
    -- A monitor described as "DP-2" beats the one plugged into DP-2.
    local c = cfg_with({ odd = { "DP-2", "DP-1" } })
    assert.is_nil(desk.select(c, { monitor("DP-1", { description = "DP-2" }), monitor("DP-2", { description = "Other" }) }),
      "DP-2 takes DP-1 by description, so DP-1 has nothing left")
  end)

  it("breaks a tie between desks of the same monitors by name", function()
    local c = cfg_with({ zeta = { "HEADLESS-2" }, alpha = { "HEADLESS-2" } })
    assert.are.equal("alpha", desk.select(c, { monitor("HEADLESS-2") }).desk)
  end)

end)

describe("a new desk for unknown monitors", function()
  it("selects each monitor by description, else serial, else connector", function()
    assert.are.equal(ODYSSEY, desk.selector(monitor("DP-1", { description = ODYSSEY, serial = "H1AK500000" })))
    assert.are.equal("S123", desk.selector(monitor("DP-1", { serial = "S123" })))
    assert.are.equal("eDP-1", desk.selector(monitor("eDP-1")))
  end)

  it("is named after its monitors' display names left to right: Built-in, a monitor's model, else its connector", function()
    local monitors = {
      monitor("DP-1", { description = ODYSSEY, serial = "H1AK500000", x = 1728 }),
      monitor("eDP-1", { x = 0 }),
    }
    assert.are.equal("built-in+odyssey-g95nc", desk.name_for(monitors, {}))
    assert.are.equal("headless-2", desk.name_for({ monitor("HEADLESS-2") }, {}))
  end)

  it("takes the user's label for a monitor", function()
    local monitors = { monitor("eDP-1", { x = 0 }), monitor("DP-1", { description = ODYSSEY, serial = "H1AK500000", x = 1728 }) }
    assert.are.equal("built-in+samsung", desk.name_for(monitors, {}, { [ODYSSEY] = "Samsung" }))
  end)

  it("takes a free name", function()
    assert.are.equal("built-in-3", desk.name_for({ monitor("eDP-1") }, { ["built-in"] = true, ["built-in-2"] = true }))
  end)

  it("lays left, main and right side by side on screen 1, scrolling on a laptop panel", function()
    local slots = { "left", "main", "notes", "right" }
    assert.are.same({ [1] = "h[left, main, right]" }, desk.default_trees({ monitor("DP-1") }, slots))
    assert.are.same({ [1] = "scroll[left, main, right]" }, desk.default_trees({ monitor("eDP-1") }, slots))
    assert.are.same({ [1] = "h[left, main, right]" },
      desk.default_trees({ monitor("eDP-1", { x = 3000 }), monitor("DP-1") }, slots), "screen 1 is the left one")
  end)

  it("names a new layout for what it arranges, not for a desk: scroll, else <N>-screen", function()
    assert.are.equal("scroll", desk.layout_name_for(1, { [1] = "scroll[left, main, right]" }))
    assert.are.equal("1-screen", desk.layout_name_for(1, { [1] = "h[left, main, right]" }))
    assert.are.equal("2-screen", desk.layout_name_for(2, { [1] = "scroll[left, main, right]" }))
    assert.are.equal("3-screen", desk.layout_name_for(3, {}))
  end)

  it("uses every slot when there is no left, main or right, and nothing when there are no slots", function()
    assert.are.same({ [1] = "h[a, b]" }, desk.default_trees({ monitor("DP-1") }, { "a", "b" }))
    assert.are.same({ [1] = "a" }, desk.default_trees({ monitor("DP-1") }, { "a" }))
    assert.are.same({}, desk.default_trees({ monitor("DP-1") }, {}))
  end)
end)
