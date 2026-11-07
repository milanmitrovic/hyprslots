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
    local raw = { slots = given.slots, arrangements = given.arrangements, pinned = { "laptop" }, title_matching = {} }
    assert.are.same({ "pinned", "title_matching" }, edit.read_only(raw, given))
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

-- Slots view (D3): the data of two arrangements sharing desk 3's slots.
local function two()
  return {
    slots = { [3] = { a = "t-a", b = "t-b", c = "t-c" }, [4] = { mail = "thunderbird" } },
    arrangements = {
      solo = {
        screens = { main = "HEADLESS-2" },
        desks = { [3] = { main = "h[a:1, b:2, c:1]" }, [4] = { main = "mail" } },
      },
      dual = {
        screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
        desks = { [3] = { big = "h[a:2, v[b, *]]", side = "c" } },
      },
    },
  }
end

describe("edit.set_spec", function()
  it("writes a slot's spec, trimmed, into a copy", function()
    local before = two()
    local after = assert(edit.set_spec(before, 3, "a", "  kitty/deltaf "))
    assert.are.equal("kitty/deltaf", after.slots[3].a)
    assert.are.equal("t-a", before.slots[3].a)
  end)

  it("refuses a spec the grammar rejects, with why", function()
    local after, err = edit.set_spec(two(), 3, "a", "[Tag")
    assert.is_nil(after)
    assert.matches("closing ']'", err)
  end)

  it("refuses a slot the desk does not have", function()
    local after, err = edit.set_spec(two(), 3, "zz", "x")
    assert.is_nil(after)
    assert.matches("desk 3 has no slot 'zz'", err)
  end)
end)

describe("edit.add_slot", function()
  it("adds a slot with its spec, on a desk that had none too", function()
    local after = assert(edit.add_slot(two(), 3, "d", "t-d"))
    assert.are.equal("t-d", after.slots[3].d)
    local fresh = assert(edit.add_slot(two(), 7, "x", "foo"))
    assert.are.same({ x = "foo" }, fresh.slots[7])
  end)

  it("refuses a name that is taken, malformed, or a bad spec", function()
    assert.matches("already has a slot 'a'", select(2, edit.add_slot(two(), 3, "a", "x")))
    assert.matches("slot name", select(2, edit.add_slot(two(), 3, "1x", "x")))
    assert.matches("empty", select(2, edit.add_slot(two(), 3, "d", " ")))
    assert.matches("desk", select(2, edit.add_slot(two(), 0, "d", "x")))
  end)

  it("keeps a description when given one", function()
    local after = assert(edit.add_slot(two(), 3, "d", "t-d", "the fourth"))
    assert.are.equal("the fourth", after.descriptions[3].d)
  end)
end)

describe("edit.remove_slot", function()
  it("removes the slot and takes it out of every tree that places it", function()
    local after = assert(edit.remove_slot(two(), 3, "b"))
    assert.is_nil(after.slots[3].b)
    assert.are.equal("h[a, c]", after.arrangements.solo.desks[3].main)
    assert.are.equal("h[a:2, *]", after.arrangements.dual.desks[3].big)
  end)

  it("drops a branch the slot was all of, and the slot's description", function()
    local data = two()
    data.descriptions = { [3] = { c = "right column" } }
    local after = assert(edit.remove_slot(data, 3, "c"))
    assert.is_nil(after.arrangements.dual.desks[3].side)
    assert.is_nil(after.descriptions, "an empty descriptions table goes too")
  end)

  it("refuses a slot the desk does not have", function()
    assert.matches("no slot 'zz'", select(2, edit.remove_slot(two(), 3, "zz")))
  end)
end)

describe("edit.rename_slot", function()
  it("renames the slot and rewrites every tree of every arrangement that uses it", function()
    local data = two()
    data.descriptions = { [3] = { b = "middle" } }
    local after = assert(edit.rename_slot(data, 3, "b", "middle"))
    assert.is_nil(after.slots[3].b)
    assert.are.equal("t-b", after.slots[3].middle)
    assert.are.equal("h[a, middle:2, c]", after.arrangements.solo.desks[3].main)
    assert.are.equal("h[a:2, v[middle, *]]", after.arrangements.dual.desks[3].big)
    assert.are.same({ middle = "middle" }, after.descriptions[3])
  end)

  it("leaves other desks' slots of the same name alone", function()
    local data = two()
    data.slots[4].b = "x"
    data.arrangements.solo.desks[4].main = "h[mail, b]"
    local after = assert(edit.rename_slot(data, 3, "b", "z"))
    assert.are.equal("h[mail, b]", after.arrangements.solo.desks[4].main)
  end)

  it("refuses a name that is taken or malformed, and a missing slot", function()
    assert.matches("already has a slot 'c'", select(2, edit.rename_slot(two(), 3, "b", "c")))
    assert.matches("slot name", select(2, edit.rename_slot(two(), 3, "b", "a b")))
    assert.matches("no slot 'zz'", select(2, edit.rename_slot(two(), 3, "zz", "y")))
  end)
end)

describe("edit.describe_slot", function()
  it("sets a slot's description, and an empty one removes it", function()
    local after = assert(edit.describe_slot(two(), 3, "a", "the editor"))
    assert.are.equal("the editor", after.descriptions[3].a)
    local cleared = assert(edit.describe_slot(after, 3, "a", ""))
    assert.is_nil(cleared.descriptions)
  end)

  it("refuses a slot the desk does not have", function()
    assert.matches("no slot 'zz'", select(2, edit.describe_slot(two(), 3, "zz", "x")))
  end)
end)

describe("edit.rename_leaf / edit.remove_leaf", function()
  local tree = require("hyprslots.tree")
  local serialize = require("hyprslots.serialize")

  it("rename a slot in a parsed tree, without touching the original", function()
    local node = assert(tree.parse("h[a:2, a[b, c]]"))
    assert.are.equal("h[a:2, a[x, c]]", serialize.tree(edit.rename_leaf(node, "b", "x")))
    assert.are.equal("h[a:2, a[b, c]]", serialize.tree(node))
  end)

  it("removing a slot hoists a container's lone survivor with the container's weight", function()
    local node = assert(tree.parse("h[a, v[b, c]:3]"))
    assert.are.equal("h[a, c:3]", serialize.tree(edit.remove_leaf(node, "b")))
    assert.are.equal("v[b, c]", serialize.tree(edit.remove_leaf(node, "a")))
    assert.is_nil(edit.remove_leaf(assert(tree.parse("a")), "a"))
  end)
end)
