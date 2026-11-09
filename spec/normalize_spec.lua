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

  it("leaves a workspace with no trees, and a layout with none, without any", function()
    local out, changed = migrate.normalize(data({
      solo = { screens = 1, workspaces = { [5] = {} } },
      bare = { screens = 1 },
    }))
    assert.is_false(changed)
    assert.are.same({}, out.layouts.solo.workspaces[5])
    assert.is_nil(out.layouts.solo.default)
    assert.is_nil(out.layouts.bare.default)
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

