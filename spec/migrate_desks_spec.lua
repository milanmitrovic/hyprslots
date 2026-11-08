local migrate = require("hyprslots.migrate")

describe("migrate.desks: arrangements become desks and layouts", function()
  local function monitor(name, x, fields)
    local m = { name = name, description = "", serial = "", x = x or 0, y = 0 }
    for key, value in pairs(fields or {}) do
      m[key] = value
    end
    return m
  end

  -- The user's slots.lua before (docs/design.md §4), trimmed to two workspaces.
  local BEFORE = {
    slots = { left = {}, main = {}, right = {} },
    specs = { [3] = { main = "kitty/deltaf" } },
    arrangements = {
      laptop = { screens = { laptop = "eDP-1" }, desks = { [3] = { laptop = "scroll[left, main, right]" } } },
      ultrawide = { screens = { wide = "Odyssey" }, desks = { [3] = { wide = "h[left, main:2, right]" } } },
      docked = {
        screens = { laptop = "eDP-1", wide = "Odyssey" },
        desks = { [3] = { wide = "h[left, main:2, right]" }, [4] = { wide = "main" } },
      },
    },
  }

  it("makes each arrangement a desk of its monitors and a layout of its trees, by screen number", function()
    local out, changed = migrate.desks(BEFORE)
    assert.is_true(changed)
    assert.is_nil(out.arrangements)
    assert.are.same({ monitors = { "eDP-1" }, layout = "laptop" }, out.desks.laptop)
    assert.are.same({ screens = 1, workspaces = { [3] = { [1] = "scroll[left, main, right]" } } }, out.layouts.laptop)
    assert.are.same({ screens = 1, workspaces = { [3] = { [1] = "h[left, main:2, right]" } } }, out.layouts.ultrawide)
    assert.are.same(BEFORE.specs, out.specs)
    assert.are.same(BEFORE.slots, out.slots)
  end)

  it("orders screens by role name when the monitors are not connected", function()
    local out = migrate.desks(BEFORE)
    assert.are.same({ "eDP-1", "Odyssey" }, out.desks.docked.monitors)
    assert.are.same({ [3] = { [2] = "h[left, main:2, right]" }, [4] = { [2] = "main" } }, out.layouts.docked.workspaces)
  end)

  it("orders screens left to right when every monitor of the arrangement is connected", function()
    local out = migrate.desks(BEFORE, {
      monitor("DP-1", 0, { description = "Odyssey" }),
      monitor("eDP-1", 5120),
    })
    assert.are.same({ "Odyssey", "eDP-1" }, out.desks.docked.monitors)
    assert.are.same({ [3] = { [1] = "h[left, main:2, right]" }, [4] = { [1] = "main" } }, out.layouts.docked.workspaces)
  end)

  it("lets arrangements with the same trees share one layout, named after the first", function()
    local out = migrate.desks({
      slots = { main = {} },
      arrangements = {
        office = { screens = { big = "DP-1" }, desks = { [1] = { big = "main" } } },
        home = { screens = { wide = "HDMI-A-1" }, desks = { [1] = { wide = "main" } } },
      },
    })
    assert.are.equal("home", out.desks.home.layout)
    assert.are.equal("home", out.desks.office.layout)
    assert.is_nil(out.layouts.office)
  end)

  it("turns pinned roles into each desk's pinned screens", function()
    local out = migrate.desks({
      slots = { main = {} },
      pinned = { "side" },
      arrangements = {
        dual = { screens = { big = "A", side = "B" } },
        single = { screens = { big = "A" } },
      },
    })
    assert.are.same({ 2 }, out.desks.dual.pinned)
    assert.is_nil(out.desks.single.pinned)
    assert.is_nil(out.pinned)
  end)

  it("leaves desks and layouts alone", function()
    local data = { desks = { a = { monitors = { "A" }, layout = "x" } }, layouts = { x = { screens = 1 } } }
    local out, changed = migrate.desks(data)
    assert.is_false(changed)
    assert.are.same(data, out)
  end)

  it("never changes the table it is given", function()
    local copy = migrate.desks(BEFORE)
    migrate.desks(BEFORE, { monitor("DP-1", 0, { description = "Odyssey" }), monitor("eDP-1", 5120) })
    assert.is_not_nil(BEFORE.arrangements.docked)
    assert.is_nil(BEFORE.desks)
    assert.is_nil(copy.arrangements)
  end)
end)

describe("migrate.data", function()
  it("reads both shapes of before at once: per-workspace slots and arrangements", function()
    local out, changed = migrate.data({
      slots = { [3] = { main = "t-main" } },
      arrangements = { solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "main" } } } },
    })
    assert.is_true(changed)
    assert.are.same({ main = {} }, out.slots)
    assert.are.same({ [3] = { main = "t-main" } }, out.specs)
    assert.are.same({ monitors = { "HEADLESS-2" }, layout = "solo" }, out.desks.solo)
  end)

  it("says when nothing had to change", function()
    local _, changed = migrate.data({ slots = { main = {} }, layouts = { x = { screens = 1 } } })
    assert.is_false(changed)
  end)
end)
