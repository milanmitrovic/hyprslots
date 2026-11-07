-- Edits to the editor-owned data (slots.lua), and which parts of the config
-- the editor may change at all.

local edit = require("hyprslots.edit")

local function data()
  return {
    slots = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
    arrangements = {
      solo = {
        screens = { main = "HEADLESS-2" },
        desks = { [3] = { main = "h[a:1, b:2, c:1]" } },
      },
    },
  }
end

describe("edit.read_only", function()
  it("finds nothing read-only when config.lua passes the data straight through", function()
    local given = data()
    local raw = { slots = given.slots, arrangements = given.arrangements }
    assert.are.same({}, edit.read_only(raw, given))
  end)

  it("reports a field config.lua sets by code", function()
    local given = data()
    local raw = { slots = given.slots, arrangements = given.arrangements, pinned = { "laptop" }, title_rules = {} }
    assert.are.same({ "pinned", "title_rules" }, edit.read_only(raw, given))
  end)

  it("reports an arrangement built in code among ones from the data", function()
    local given = data()
    local arrangements = { solo = given.arrangements.solo, work = { screens = { big = "DP-1" } } }
    local raw = { slots = given.slots, arrangements = arrangements }
    assert.are.same({ "arrangements.work" }, edit.read_only(raw, given))
  end)

  it("reports a desk's slots set by code", function()
    local given = data()
    local raw = { slots = { [3] = given.slots[3], [4] = { x = "foo" } }, arrangements = given.arrangements }
    assert.are.same({ "slots.4" }, edit.read_only(raw, given))
  end)

  it("reports everything when there is no data file", function()
    local raw = { slots = {}, arrangements = {} }
    assert.are.same({ "arrangements", "slots" }, edit.read_only(raw, nil))
  end)
end)

describe("edit.editable", function()
  it("allows an arrangement that comes from the data", function()
    assert.is_true(edit.editable({}, "arrangements", "solo"))
  end)

  it("refuses an arrangement under a read-only path", function()
    assert.is_false(edit.editable({ "arrangements.work" }, "arrangements", "work"))
    assert.is_false(edit.editable({ "arrangements" }, "arrangements", "solo"))
  end)
end)

describe("edit.set_tree", function()
  it("writes the tree, normalized, into a copy of the data", function()
    local before = data()
    local after = assert(edit.set_tree(before, "solo", 3, "main", "h[ a:2 ,b:1, c ]"))
    assert.are.equal("h[a:2, b, c]", after.arrangements.solo.desks[3].main)
    assert.are.equal("h[a:1, b:2, c:1]", before.arrangements.solo.desks[3].main, "the original is untouched")
  end)

  it("adds a desk the arrangement had no tree for", function()
    local after = assert(edit.set_tree(data(), "solo", 5, "main", "x"))
    assert.are.equal("x", after.arrangements.solo.desks[5].main)
  end)

  it("refuses an unknown arrangement", function()
    local after, err = edit.set_tree(data(), "nope", 3, "main", "a")
    assert.is_nil(after)
    assert.matches("nope", err)
  end)

  it("refuses an unknown screen role", function()
    local after, err = edit.set_tree(data(), "solo", 3, "side", "a")
    assert.is_nil(after)
    assert.matches("side", err)
  end)

  it("refuses a desk out of range", function()
    local after, err = edit.set_tree(data(), "solo", 11, "main", "a")
    assert.is_nil(after)
    assert.matches("desk", err)
  end)

  it("refuses a tree that does not parse", function()
    local after, err = edit.set_tree(data(), "solo", 3, "main", "h[a, b")
    assert.is_nil(after)
    assert.matches("expected", err)
  end)
end)

describe("edit.copy", function()
  it("copies deeply", function()
    local original = data()
    local copy = edit.copy(original)
    assert.are.same(original, copy)
    copy.slots[3].a = "changed"
    assert.are.equal("t-a", original.slots[3].a)
  end)
end)
