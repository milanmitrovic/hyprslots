-- Test seam S3: slots.lua's per-workspace shape of before (slots = workspace -> slot ->
-- spec, descriptions = workspace -> slot -> text) read as the global shape
-- (slots = name -> { description? }, specs = workspace -> slot -> spec).

local migrate = require("hyprslots.migrate")

describe("migrate.data", function()
  it("turns per-workspace slots into global slots and per-workspace specs", function()
    local out, migrated = migrate.data({
      slots = {
        [1] = { left = "[Left]", main = "[Main]" },
        [3] = { left = "[DeltaF]", main = "com.mitchellh.ghostty/deltaf", right = "antigravity/deltaf" },
      },
      arrangements = { solo = { screens = { big = "eDP-1" }, desks = { [3] = { big = "h[left, main, right]" } } } },
    })
    assert.is_true(migrated)
    assert.are.same({ left = {}, main = {}, right = {} }, out.slots)
    assert.are.same({
      [1] = { left = "[Left]", main = "[Main]" },
      [3] = { left = "[DeltaF]", main = "com.mitchellh.ghostty/deltaf", right = "antigravity/deltaf" },
    }, out.specs)
    assert.are.same({ solo = { screens = { big = "eDP-1" }, desks = { [3] = { big = "h[left, main, right]" } } } },
      out.arrangements)
  end)

  it("moves each slot's description onto the global slot", function()
    local out = migrate.data({
      slots = { [3] = { main = "kitty/deltaf", right = "firefox" } },
      descriptions = { [3] = { main = "the editor" } },
    })
    assert.are.same({ main = { description = "the editor" }, right = {} }, out.slots)
    assert.is_nil(out.descriptions)
  end)

  it("keeps every different description of one slot name, in workspace order", function()
    local out = migrate.data({
      slots = { [2] = { main = "a" }, [3] = { main = "b" }, [5] = { main = "c" } },
      descriptions = { [5] = { main = "editor" }, [2] = { main = "notes" }, [3] = { main = "editor" } },
    })
    assert.are.equal("notes; editor", out.slots.main.description)
  end)

  it("drops a description of a slot no workspace has", function()
    local out = migrate.data({ slots = { [3] = { main = "a" } }, descriptions = { [3] = { gone = "x" } } })
    assert.are.same({ main = {} }, out.slots)
  end)

  it("leaves data in the global shape as it is, a copy", function()
    local data = {
      slots = { main = { description = "the editor" }, right = {} },
      specs = { [3] = { main = "kitty" } },
      arrangements = {},
    }
    local out, migrated = migrate.data(data)
    assert.is_false(migrated)
    assert.are.same(data, out)
    assert.are_not.equal(data, out)
  end)

  it("leaves data with no slots alone", function()
    local out, migrated = migrate.data({ arrangements = {} })
    assert.is_false(migrated)
    assert.are.same({ arrangements = {} }, out)
  end)

  it("never changes the table it is given", function()
    local data = { slots = { [3] = { main = "a" } }, descriptions = { [3] = { main = "x" } } }
    migrate.data(data)
    assert.are.same({ slots = { [3] = { main = "a" } }, descriptions = { [3] = { main = "x" } } }, data)
  end)

  it("keeps what it cannot read for validation to report (a workspace that is no table)", function()
    local out = migrate.data({ slots = { [3] = "kitty" } })
    assert.are.same({ [3] = "kitty" }, out.specs)
  end)

  it("puts legacy slots under specs that are already there, the specs winning", function()
    local out = migrate.data({ slots = { [3] = { main = "old", right = "r" } }, specs = { [3] = { main = "new" } } })
    assert.are.same({ [3] = { main = "new", right = "r" } }, out.specs)
    assert.are.same({ main = {}, right = {} }, out.slots)
  end)

  it("moves descriptions given beside global slots onto them", function()
    local out, migrated = migrate.data({ slots = { main = {} }, descriptions = { [3] = { main = "the editor" } } })
    assert.is_true(migrated)
    assert.are.same({ main = { description = "the editor" } }, out.slots)
    assert.is_nil(out.descriptions)
  end)

  it("tells the per-workspace shape from the global one", function()
    assert.is_true(migrate.legacy({ slots = { [3] = { main = "a" } } }))
    assert.is_true(migrate.legacy({ descriptions = {} }))
    assert.is_false(migrate.legacy({ slots = { main = {} } }))
    assert.is_false(migrate.legacy({ slots = {} }))
    assert.is_false(migrate.legacy("not a table"))
  end)
end)
