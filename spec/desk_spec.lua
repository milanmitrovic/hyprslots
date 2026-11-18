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

describe("a desk's geometry (its monitors' logical boxes)", function()
  it("is each selector's logical box, the desk's top-left at 0, 0", function()
    local laptop = monitor("eDP-1", { x = 0, y = 360, width = 2880, height = 1800, scale = 2, transform = 0 })
    local odyssey = monitor("DP-2", { description = ODYSSEY, x = 1440, y = 0, width = 5120, height = 1440, scale = 1,
      transform = 0 })
    assert.are.same({
      ["eDP-1"] = { x = 0, y = 360, w = 1440, h = 900 },
      [ODYSSEY] = { x = 1440, y = 0, w = 5120, h = 1440 },
    }, desk.geometry({ ODYSSEY, "eDP-1" }, { odyssey, laptop }))
  end)

  it("divides by the scale and swaps width and height for a monitor turned 90 or 270 degrees", function()
    local portrait = monitor("DP-1", { x = -1000, y = -200, width = 3840, height = 2160, scale = 1.5, transform = 1 })
    local turned = monitor("DP-3", { x = 440, y = -200, width = 1920, height = 1080, scale = 1, transform = 3 })
    local flipped = monitor("DP-4", { x = 1520, y = -200, width = 1920, height = 1080, scale = 1, transform = 2 })
    assert.are.same({
      ["DP-1"] = { x = 0, y = 0, w = 1440, h = 2560 },
      ["DP-3"] = { x = 1440, y = 0, w = 1080, h = 1920 },
      ["DP-4"] = { x = 2520, y = 0, w = 1920, h = 1080 },
    }, desk.geometry({ "DP-1", "DP-3", "DP-4" }, { portrait, turned, flipped }))
  end)

  it("rounds a fractional logical size to whole pixels", function()
    local m = monitor("DP-1", { width = 2560, height = 1440, scale = 1.25 })
    assert.are.same({ ["DP-1"] = { x = 0, y = 0, w = 2048, h = 1152 } }, desk.geometry({ "DP-1" }, { m }))
    local odd = monitor("DP-1", { width = 2880, height = 1920, scale = 1.6666667 })
    assert.are.same({ ["DP-1"] = { x = 0, y = 0, w = 1728, h = 1152 } }, desk.geometry({ "DP-1" }, { odd }))
  end)

  it("is nil when the selectors are not exactly the monitors, or a monitor's size is unknown", function()
    local a = monitor("DP-1", { width = 1920, height = 1080, scale = 1 })
    assert.is_nil(desk.geometry({ "DP-1", "DP-2" }, { a }))
    assert.is_nil(desk.geometry({ "DP-1" }, { monitor("DP-1") }))
    assert.is_nil(desk.geometry({ "DP-1" }, { monitor("DP-1", { width = 1920, height = 1080, scale = 0 }) }))
  end)

  it("reads a missing scale as 1 and a missing transform as none", function()
    local a = monitor("DP-1", { width = 1920, height = 1080 })
    assert.are.same({ ["DP-1"] = { x = 0, y = 0, w = 1920, h = 1080 } }, desk.geometry({ "DP-1" }, { a }))
  end)
end)

describe("a desk's map", function()
  it("numbers the screens as the layout does: left to right, then top to bottom", function()
    local left = monitor("DP-1", { x = 0, y = 0, width = 1920, height = 1080 })
    local right = monitor("DP-2", { x = 1920, y = 0, width = 2560, height = 1440 })
    local below = monitor("DP-3", { x = 1920, y = 1440, width = 1920, height = 1080 })
    local monitors = { below, right, left }
    local selectors = { "DP-3", "DP-1", "DP-2" }
    local map = desk.map(selectors, desk.geometry(selectors, monitors))
    assert.are.same({
      { x = 1920, y = 1440, w = 1920, h = 1080, screen = 3 },
      { x = 0, y = 0, w = 1920, h = 1080, screen = 1 },
      { x = 1920, y = 0, w = 2560, h = 1440, screen = 2 },
    }, map)
    -- the same numbers as the layout's screens
    local cfg = assert(config.validate({
      slots = { main = {} },
      desks = { trio = { monitors = selectors, layout = "trio" } },
      layouts = { trio = { screens = 3, default = { [1] = "main" } } },
    }))
    local active = desk.select(cfg, monitors)
    for i, selector in ipairs(selectors) do
      local found = desk.find(selector, monitors)
      assert.are.equal(active.screens[found.name], map[i].screen, selector)
    end
  end)

  it("is equal boxes side by side in selector order for a desk never seen", function()
    assert.are.same({
      { x = 0, y = 0, w = 1600, h = 900, screen = 1 },
      { x = 1600, y = 0, w = 1600, h = 900, screen = 2 },
    }, desk.map({ "DP-9", "eDP-1" }, nil))
  end)

  it("is the equal boxes too when the recorded geometry misses a selector", function()
    assert.are.same({
      { x = 0, y = 0, w = 1600, h = 900, screen = 1 },
      { x = 1600, y = 0, w = 1600, h = 900, screen = 2 },
    }, desk.map({ "DP-9", "eDP-1" }, { ["DP-9"] = { x = 0, y = 0, w = 1920, h = 1080 } }))
  end)

  it("breaks a tie of position by selector order", function()
    local same = { a = { x = 0, y = 0, w = 10, h = 10 }, b = { x = 0, y = 0, w = 10, h = 10 } }
    assert.are.same({ 1, 2 }, { desk.map({ "b", "a" }, same)[1].screen, desk.map({ "b", "a" }, same)[2].screen })
  end)
end)
