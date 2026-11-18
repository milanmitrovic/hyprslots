-- A monitor's display name (docs/design.md §8): a short name the editor
-- shows, never used to match a desk's monitors.

local monitor_name = require("hyprslots.monitor_name")

local function monitor(name, fields)
  local m = { name = name, description = "", serial = "" }
  for key, value in pairs(fields or {}) do
    m[key] = value
  end
  return m
end

-- The user's two monitors, as Hyprland reports them.
local PANEL = monitor("eDP-1")
local ODYSSEY = monitor("DP-1", { description = "Samsung Electric Company Odyssey G95NC HNTW700044",
  serial = "HNTW700044" })

describe("a monitor's automatic name", function()
  it("is Built-in for the laptop's own panel, whose description is empty", function()
    assert.are.equal("Built-in", monitor_name.auto(PANEL))
    assert.are.equal("Built-in", monitor_name.auto(monitor("LVDS-1")))
    assert.are.equal("Built-in", monitor_name.auto(monitor("DSI-1", { description = "Some Panel" })))
  end)

  it("is the model: the description without its make and its serial", function()
    assert.are.equal("Odyssey G95NC", monitor_name.auto(ODYSSEY))
    local dell = monitor("DP-2", { description = "Dell Inc. DELL U2720Q 1ABC", serial = "1ABC" })
    assert.are.equal("DELL U2720Q", monitor_name.auto(dell))
  end)

  it("knows the makes it is given (the PNP vendor names)", function()
    local acme = monitor("DP-3", { description = "Acme Displays Ltd Vista 27 S1", serial = "S1" })
    assert.are.equal("Vista 27", monitor_name.auto(acme, { ["Acme Displays Ltd"] = true }))
    assert.are.equal("Vista 27", monitor_name.auto(acme, { ["Acme"] = true, ["Acme Displays Ltd"] = true }),
      "the longest make that starts the description")
  end)

  it("keeps the description, less its serial, when no make it knows starts it", function()
    local acme = monitor("DP-3", { description = "Acme Displays Ltd Vista 27 S1", serial = "S1" })
    assert.are.equal("Acme Displays Ltd Vista 27", monitor_name.auto(acme, {}))
  end)

  it("takes the make and model Hyprland reports when it does", function()
    assert.are.equal("U2720Q", monitor_name.auto(monitor("DP-2", { description = "Dell Inc. U2720Q 1ABC",
      make = "Dell Inc.", model = "U2720Q" })))
    assert.are.equal("Dell Inc.", monitor_name.auto(monitor("DP-2", { description = "Dell Inc. 1ABC", serial = "1ABC",
      make = "Dell Inc.", model = "" })))
  end)

  it("falls back to the make when the description is the make alone, then to the connector", function()
    assert.are.equal("Dell Inc.", monitor_name.auto(monitor("DP-2", { description = "Dell Inc." })))
    assert.are.equal("Dell Inc.", monitor_name.auto(monitor("DP-2", { description = "Dell Inc. 1ABC", serial = "1ABC" })))
    assert.are.equal("HEADLESS-2", monitor_name.auto(monitor("HEADLESS-2")))
  end)
end)

describe("a monitor's display name", function()
  it("is the user's label for it when there is one, by description, serial or connector", function()
    local labels = { ["Samsung Electric Company Odyssey G95NC HNTW700044"] = "Samsung" }
    assert.are.equal("Samsung", monitor_name.display(ODYSSEY, labels))
    assert.are.equal("Wide", monitor_name.display(ODYSSEY, { HNTW700044 = "Wide" }))
    assert.are.equal("Laptop", monitor_name.display(PANEL, { ["eDP-1"] = "Laptop" }))
  end)

  it("is the automatic name otherwise", function()
    assert.are.equal("Built-in", monitor_name.display(PANEL, {}))
    assert.are.equal("Odyssey G95NC", monitor_name.display(ODYSSEY, nil))
  end)

  it("names a desk's selector whose monitor is not connected: its label, else from the selector alone", function()
    assert.are.equal("Samsung", monitor_name.of_selector("Samsung Electric Company Odyssey G95NC HNTW700044", nil,
      { ["Samsung Electric Company Odyssey G95NC HNTW700044"] = "Samsung" }))
    assert.are.equal("Built-in", monitor_name.of_selector("eDP-1", nil, {}))
    assert.are.equal("Odyssey G95NC",
      monitor_name.of_selector("Samsung Electric Company Odyssey G95NC HNTW700044", nil, {}),
      "the make goes, and a last word that looks like a serial")
    assert.are.equal("DELL U2720Q 1ABC", monitor_name.of_selector("Dell Inc. DELL U2720Q 1ABC", nil, {}),
      "a short last word may be the model's: kept")
    assert.are.equal("VG27AQ1A12", monitor_name.of_selector("ASUSTek COMPUTER INC VG27AQ1A12", nil, {}),
      "the model's only word is never taken for a serial")
    assert.are.equal("Odyssey G95NC", monitor_name.of_selector("Samsung Electric Company Odyssey G95NC HNTW700044",
      ODYSSEY, {}), "a connected one is named as it is")
  end)
end)

describe("the makes", function()
  it("are read from a PNP id table: three letters, a tab, the vendor's name", function()
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write("SAM\tSamsung Electric Company\nDEL\tDell Inc.\n\nbad line\n")
    file:close()
    local makes = monitor_name.read_makes(path)
    os.remove(path)
    assert.are.same({ ["Samsung Electric Company"] = true, ["Dell Inc."] = true }, makes)
  end)

  it("are a short list of common ones when the table cannot be read", function()
    local makes = monitor_name.read_makes("/nonexistent/pnp.ids")
    assert.is_true(makes["Samsung Electric Company"])
    assert.is_true(makes["Dell Inc."])
  end)
end)

describe("a monitor name as a desk name's part", function()
  it("is lowercase, words joined with '-'", function()
    assert.are.equal("built-in", monitor_name.slug("Built-in"))
    assert.are.equal("odyssey-g95nc", monitor_name.slug("Odyssey G95NC"))
    assert.are.equal("dell-u2720q", monitor_name.slug("DELL  U2720Q!"))
  end)
end)
