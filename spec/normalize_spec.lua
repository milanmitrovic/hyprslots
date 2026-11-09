-- Test seam S3: every tree holds every global slot (docs/design.md §3, §4).
-- migrate.normalize appends the global slots a tree set leaves out and
-- drops the slots that are not global; migrate.unpin drops pinned screens.

local migrate = require("hyprslots.migrate")

local function data(layouts, slots)
  return {
    slots = slots or { left = {}, main = {}, right = {} },
    specs = { [3] = { main = "kitty" } },
    desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
    layouts = layouts,
  }
end

describe("migrate.normalize", function()
  it("appends the global slots a tiled tree leaves out, by name, to its root split", function()
    local out, changed = migrate.normalize(data({ solo = { screens = 1, default = { [1] = "h[main:2, *]" } } }))
    assert.is_true(changed)
    assert.are.equal("h[main:2, *, left, right]", out.layouts.solo.default[1])
  end)

  it("appends them at the end of a scroll branch, before a trailing *", function()
    local out = migrate.normalize(data({
      solo = { screens = 1, default = { [1] = "scroll:0.5[main, *]" }, workspaces = { [3] = { [1] = "scroll[right]" } } },
    }))
    assert.are.equal("scroll:0.5[main, left, right, *]", out.layouts.solo.default[1])
    assert.are.equal("scroll[right, left, main]", out.layouts.solo.workspaces[3][1])
  end)

  it("drops the slots that are not global", function()
    local out, changed = migrate.normalize(data({
      solo = { screens = 1, default = { [1] = "h[left, gone, main, right]" } },
    }))
    assert.is_true(changed)
    assert.are.equal("h[left, main, right]", out.layouts.solo.default[1])
  end)

  it("puts a workspace's missing slots on the left-most screen with a tree, once per workspace", function()
    local out = migrate.normalize(data({
      dual = { screens = 2, default = { [2] = "h[left, main]" }, workspaces = { [3] = { [1] = "main", [2] = "left" } } },
    }))
    assert.is_nil(out.layouts.dual.default[1])
    assert.are.equal("h[left, main, right]", out.layouts.dual.default[2])
    assert.are.equal("h[main, right]", out.layouts.dual.workspaces[3][1])
    assert.are.equal("left", out.layouts.dual.workspaces[3][2])
  end)

  it("leaves trees that hold every slot as they are written, and says nothing changed", function()
    local given = data({ solo = { screens = 1, default = { [1] = "h[left,main , right:2]" } } })
    local out, changed = migrate.normalize(given)
    assert.is_false(changed)
    assert.are.equal("h[left,main , right:2]", out.layouts.solo.default[1])
  end)

  it("leaves a workspace with no trees of its own without any", function()
    local out, changed = migrate.normalize(data({
      solo = { screens = 1, default = { [1] = "h[left, main, right]" }, workspaces = { [5] = {} } },
    }))
    assert.is_false(changed)
    assert.are.same({}, out.layouts.solo.workspaces[5])
  end)

  describe("a layout with no tree", function()
    local function desks(list)
      local given = data({ bare = { screens = #list[1] } })
      given.desks = { bare = { monitors = list[1], layout = "bare" } }
      for i = 2, #list do
        given.desks["other" .. i] = { monitors = list[i], layout = "bare" }
      end
      return given
    end

    it("gets every global slot side by side on screen 1, left, main and right first", function()
      local given = data({ bare = { screens = 1 } }, { left = {}, main = {}, right = {}, notes = {} })
      local out, changed = migrate.normalize(given)
      assert.is_true(changed)
      assert.are.same({ [1] = "h[left, main, right, notes]" }, out.layouts.bare.default)
      assert.is_nil(given.layouts.bare.default, "the table given is untouched")
    end)

    it("an empty default set, or one every tree of which is dropped, counts as none", function()
      local out = migrate.normalize(data({
        empty = { screens = 1, default = {} },
        gone = { screens = 1, default = { [1] = "h[gone, also]" } },
      }))
      assert.are.same({ [1] = "h[left, main, right]" }, out.layouts.empty.default)
      assert.are.same({ [1] = "h[left, main, right]" }, out.layouts.gone.default)
    end)

    it("scrolls, full width, when screen 1 is a laptop panel a desk using it selects by connector", function()
      local out = migrate.normalize(desks({ { "eDP-1" } }))
      assert.are.same({ [1] = "scroll[left, main, right]" }, out.layouts.bare.default)
      for _, connector in ipairs({ "LVDS-1", "DSI-1" }) do
        assert.are.same({ [1] = "scroll[left, main, right]" },
          migrate.normalize(desks({ { connector } })).layouts.bare.default, connector)
      end
      assert.are.same({ [1] = "h[left, main, right]" },
        migrate.normalize(desks({ { "Dell U2723QE ABC" } })).layouts.bare.default)
    end)

    it("knows a connected desk's screen 1 as its left-most monitor, by what the desk selects it by", function()
      local monitors = {
        { name = "DP-1", description = "Dell U2723QE ABC", x = 0, y = 0 },
        { name = "eDP-1", description = "", x = 2560, y = 0 },
      }
      local given = desks({ { "eDP-1", "Dell U2723QE ABC" } })
      given.layouts.bare.screens = 2
      assert.are.same({ [1] = "h[left, main, right]" }, migrate.normalize(given, monitors).layouts.bare.default,
        "the laptop is on the right: screen 1 is the Dell")
      monitors[1].x, monitors[2].x = 1920, 0
      assert.are.same({ [1] = "scroll[left, main, right]" }, migrate.normalize(given, monitors).layouts.bare.default)
    end)

    it("a laptop panel selected by its description is known once connected", function()
      local given = desks({ { "BOE 0x0BCA" } })
      assert.are.same({ [1] = "h[left, main, right]" }, migrate.normalize(given).layouts.bare.default)
      local monitors = { { name = "eDP-1", description = "BOE 0x0BCA", x = 0, y = 0 } }
      assert.are.same({ [1] = "scroll[left, main, right]" }, migrate.normalize(given, monitors).layouts.bare.default)
    end)

    it("no desk using it: the connected monitors, when there are as many as it has screens", function()
      local given = data({ bare = { screens = 1 } })
      given.desks = {}
      local laptop = { { name = "eDP-1", x = 0, y = 0 } }
      assert.are.same({ [1] = "scroll[left, main, right]" }, migrate.normalize(given, laptop).layouts.bare.default)
      given.layouts.bare.screens = 2
      assert.are.same({ [1] = "h[left, main, right]" }, migrate.normalize(given, laptop).layouts.bare.default,
        "one monitor for two screens says nothing")
      assert.are.same({ [1] = "h[left, main, right]" }, migrate.normalize(given).layouts.bare.default)
    end)

    it("stays treeless with no global slot, or a screen count validation will refuse", function()
      local out, changed = migrate.normalize(data({ bare = { screens = 1 } }, {}))
      assert.is_false(changed)
      assert.is_nil(out.layouts.bare.default)
      assert.is_nil(migrate.normalize(data({ odd = { screens = "two" } })).layouts.odd.default)
    end)

    it("a workspace with trees of its own keeps them; the layout gets the shared one", function()
      local out = migrate.normalize(data({ bare = { screens = 1, workspaces = { [3] = { [1] = "v[main, left, right]" } } } }))
      assert.are.equal("v[main, left, right]", out.layouts.bare.workspaces[3][1])
      assert.are.same({ [1] = "h[left, main, right]" }, out.layouts.bare.default)
    end)
  end)

  it("drops a tree left with no slot, and its slots then go to the next screen", function()
    local out = migrate.normalize(data({ dual = { screens = 2, default = { [1] = "gone", [2] = "main" } } }))
    assert.is_nil(out.layouts.dual.default[1])
    assert.are.equal("h[main, left, right]", out.layouts.dual.default[2])
  end)

  it("leaves a tree set that does not parse for validation to report", function()
    local out, changed = migrate.normalize(data({ solo = { screens = 1, default = { [1] = "h[left, main" } } }))
    assert.is_false(changed)
    assert.are.equal("h[left, main", out.layouts.solo.default[1])
  end)

  it("never changes the table given", function()
    local given = data({ solo = { screens = 1, default = { [1] = "main" } } })
    migrate.normalize(given)
    assert.are.equal("main", given.layouts.solo.default[1])
  end)
end)

describe("migrate.data", function()
  it("reads a slots.lua with short trees as today's, and says it changed", function()
    local given = data({ solo = { screens = 1, default = { [1] = "scroll[main]" } } })
    local out, changed = migrate.data(given)
    assert.is_true(changed)
    assert.are.equal("scroll[main, left, right]", out.layouts.solo.default[1])
  end)
end)
describe("migrate.unpin", function()
  it("drops every desk's pinned screens and a top-level pinned", function()
    local given = data({ solo = { screens = 1, default = { [1] = "h[left, main, right]" } } })
    given.desks.solo.pinned = { 1 }
    given.pinned = { "laptop" }
    local out, changed = migrate.unpin(given)
    assert.is_true(changed)
    assert.is_nil(out.desks.solo.pinned)
    assert.is_nil(out.pinned)
    assert.are.same({ 1 }, given.desks.solo.pinned)
  end)

  it("says nothing changed when nothing was pinned", function()
    local _, changed = migrate.unpin(data({}))
    assert.is_false(changed)
  end)
end)

