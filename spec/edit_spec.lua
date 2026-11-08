-- Edits to the editor-owned data (slots.lua), and which parts of the config
-- the editor may change at all.

local edit = require("hyprslots.edit")

local function data()
  return {
    slots = { a = {}, b = {}, c = {} },
    specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
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
    local raw = { slots = given.slots, specs = given.specs, arrangements = given.arrangements }
    assert.are.same({}, edit.read_only(raw, given))
  end)

  it("reports a field config.lua sets by code", function()
    local given = data()
    local raw = { slots = given.slots, specs = given.specs, arrangements = given.arrangements, pinned = { "laptop" },
      title_matching = {} }
    assert.are.same({ "pinned", "title_matching" }, edit.read_only(raw, given))
  end)

  it("reports an arrangement built in code among ones from the data", function()
    local given = data()
    local arrangements = { solo = given.arrangements.solo, work = { screens = { big = "DP-1" } } }
    local raw = { slots = given.slots, specs = given.specs, arrangements = arrangements }
    assert.are.same({ "arrangements.work" }, edit.read_only(raw, given))
  end)

  it("reports a desk's specs set by code", function()
    local given = data()
    local raw = { slots = given.slots, specs = { [3] = given.specs[3], [4] = { a = "foo" } },
      arrangements = given.arrangements }
    assert.are.same({ "specs.4" }, edit.read_only(raw, given))
  end)

  it("reports the global slots as one field: a list built in code is read-only whole", function()
    local given = data()
    local raw = { slots = { a = given.slots.a, b = {}, c = {} }, specs = given.specs, arrangements = given.arrangements }
    assert.are.same({ "slots" }, edit.read_only(raw, given))
  end)

  it("reports everything when there is no data file", function()
    local raw = { slots = {}, specs = {}, arrangements = {} }
    assert.are.same({ "arrangements", "slots", "specs" }, edit.read_only(raw, nil))
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
    copy.specs[3].a = "changed"
    assert.are.equal("t-a", original.specs[3].a)
  end)
end)

-- Global slots a, b, c, mail; desks 3 and 4 say which app fills which; two
-- arrangements place them.
local function two()
  return {
    slots = { a = {}, b = { description = "middle" }, c = {}, mail = {} },
    specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" }, [4] = { mail = "thunderbird", b = "t-b4" } },
    arrangements = {
      solo = {
        screens = { main = "HEADLESS-2" },
        desks = { [3] = { main = "h[a:1, b:2, c:1]" }, [4] = { main = "h[mail, b]" } },
      },
      dual = {
        screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
        desks = { [3] = { big = "h[a:2, v[b, *]]", side = "c" } },
      },
    },
  }
end

describe("edit.add_slot", function()
  it("defines a global slot, with a description when given one", function()
    local after = assert(edit.add_slot(two(), "notes", "scratch"))
    assert.are.same({ description = "scratch" }, after.slots.notes)
    assert.are.same({}, assert(edit.add_slot(two(), "x")).slots.x)
    assert.are.same({ x = {} }, assert(edit.add_slot({}, "x")).slots, "data with no slots yet")
  end)

  it("refuses a name that is taken or malformed", function()
    assert.matches("there is a slot 'a' already", select(2, edit.add_slot(two(), "a")))
    assert.matches("slot name", select(2, edit.add_slot(two(), "1x")))
  end)

  it("never changes the data it is given", function()
    local before = two()
    edit.add_slot(before, "notes")
    assert.are.same(two(), before)
  end)
end)

describe("edit.remove_slot", function()
  it("removes the slot, takes it out of every tree of every desk, and drops every desk's spec for it", function()
    local after = assert(edit.remove_slot(two(), "b"))
    assert.is_nil(after.slots.b)
    assert.are.equal("h[a, c]", after.arrangements.solo.desks[3].main)
    assert.are.equal("mail", after.arrangements.solo.desks[4].main)
    assert.are.equal("h[a:2, *]", after.arrangements.dual.desks[3].big)
    assert.are.same({ a = "t-a", c = "t-c" }, after.specs[3])
    assert.are.same({ mail = "thunderbird" }, after.specs[4])
  end)

  it("drops a branch the slot was all of, and a desk's specs left empty", function()
    local after = assert(edit.remove_slot(two(), "mail"))
    assert.is_nil(after.specs[4].mail)
    after = assert(edit.remove_slot(after, "b"))
    assert.is_nil(after.specs[4], "desk 4 has no specs left")
    assert.is_nil(after.arrangements.solo.desks[4], "nor a tree")
    after = assert(edit.remove_slot(two(), "c"))
    assert.is_nil(after.arrangements.dual.desks[3].side)
  end)

  it("refuses a slot that is not defined", function()
    assert.matches("no slot 'zz'", select(2, edit.remove_slot(two(), "zz")))
  end)
end)

describe("edit.slot_uses", function()
  it("says which trees place a slot and which desks have a spec for it", function()
    assert.are.same({ trees = { "dual/3/big", "solo/3/main", "solo/4/main" }, specs = { 3, 4 } },
      edit.slot_uses(two(), "b"))
    assert.are.same({ trees = {}, specs = {} }, edit.slot_uses(assert(edit.add_slot(two(), "x")), "x"))
  end)
end)

describe("edit.rename_slot", function()
  it("renames the slot, every tree of every desk and arrangement, and every desk's spec for it", function()
    local after = assert(edit.rename_slot(two(), "b", "middle"))
    assert.is_nil(after.slots.b)
    assert.are.same({ description = "middle" }, after.slots.middle, "its description follows")
    assert.are.equal("h[a, middle:2, c]", after.arrangements.solo.desks[3].main)
    assert.are.equal("h[mail, middle]", after.arrangements.solo.desks[4].main)
    assert.are.equal("h[a:2, v[middle, *]]", after.arrangements.dual.desks[3].big)
    assert.are.same({ a = "t-a", middle = "t-b", c = "t-c" }, after.specs[3])
    assert.are.same({ mail = "thunderbird", middle = "t-b4" }, after.specs[4])
  end)

  it("renames to itself as a no-op", function()
    assert.are.same(two(), assert(edit.rename_slot(two(), "b", "b")))
  end)

  it("refuses a name that is taken or malformed, and a missing slot", function()
    assert.matches("there is a slot 'c' already", select(2, edit.rename_slot(two(), "b", "c")))
    assert.matches("slot name", select(2, edit.rename_slot(two(), "b", "a b")))
    assert.matches("no slot 'zz'", select(2, edit.rename_slot(two(), "zz", "y")))
  end)
end)

describe("edit.describe_slot", function()
  it("sets a slot's description, and an empty one removes it", function()
    local after = assert(edit.describe_slot(two(), "a", "the editor"))
    assert.are.same({ description = "the editor" }, after.slots.a)
    local cleared = assert(edit.describe_slot(after, "a", ""))
    assert.are.same({}, cleared.slots.a)
  end)

  it("refuses a slot that is not defined, and a description that is no text", function()
    assert.matches("no slot 'zz'", select(2, edit.describe_slot(two(), "zz", "x")))
    assert.matches("text", select(2, edit.describe_slot(two(), "a", 4)))
  end)
end)

describe("edit.set_spec", function()
  it("writes the app that fills a global slot on a desk, trimmed, into a copy", function()
    local before = two()
    local after = assert(edit.set_spec(before, 3, "a", "  kitty/deltaf "))
    assert.are.equal("kitty/deltaf", after.specs[3].a)
    assert.are.equal("t-a", before.specs[3].a)
  end)

  it("gives a desk that had no specs its first one, replacing nothing else", function()
    local after = assert(edit.set_spec(two(), 7, "mail", "thunderbird"))
    assert.are.same({ mail = "thunderbird" }, after.specs[7])
    assert.are.same(two().specs[3], after.specs[3])
    assert.are.same({ [5] = { a = "x" } }, assert(edit.set_spec({ slots = { a = {} } }, 5, "a", "x")).specs)
  end)

  it("refuses a spec the grammar rejects, with why", function()
    local after, err = edit.set_spec(two(), 3, "a", "[Tag")
    assert.is_nil(after)
    assert.matches("closing ']'", err)
  end)

  it("refuses a slot that is not defined, and a desk out of range", function()
    assert.matches("no slot 'zz' %(add it in the Slots view%)", select(2, edit.set_spec(two(), 3, "zz", "x")))
    assert.matches("desk", select(2, edit.set_spec(two(), 0, "a", "x")))
  end)
end)

describe("edit.clear_spec", function()
  it("drops a desk's spec for a slot, and the desk's specs when none is left", function()
    local after = assert(edit.clear_spec(two(), 4, "b"))
    assert.are.same({ mail = "thunderbird" }, after.specs[4])
    after = assert(edit.clear_spec(after, 4, "mail"))
    assert.is_nil(after.specs[4])
    assert.are.same({ description = "middle" }, after.slots.b, "the global slot stays")
    assert.are.equal("h[mail, b]", after.arrangements.solo.desks[4].main, "and so do the trees")
  end)

  it("refuses a desk with no spec for the slot", function()
    assert.matches("desk 7 has no spec for 'a'", select(2, edit.clear_spec(two(), 7, "a")))
  end)
end)

describe("edit.rename_leaf / edit.remove_leaf", function()
  local tree = require("hyprslots.tree")
  local serialize = require("hyprslots.serialize")

  it("rename a slot in a parsed tree, without touching the original", function()
    local node = assert(tree.parse("scroll[a, b, c]"))
    assert.are.equal("scroll[a, x, c]", serialize.tree(edit.rename_leaf(node, "b", "x")))
    assert.are.equal("scroll[a, b, c]", serialize.tree(node))
  end)

  it("removing a slot hoists a container's lone survivor with the container's weight", function()
    local node = assert(tree.parse("h[a, v[b, c]:3]"))
    assert.are.equal("h[a, c:3]", serialize.tree(edit.remove_leaf(node, "b")))
    assert.are.equal("v[b, c]", serialize.tree(edit.remove_leaf(node, "a")))
    assert.is_nil(edit.remove_leaf(assert(tree.parse("a")), "a"))
  end)

  it("removing a column keeps a scroll branch, down to its last column", function()
    local node = assert(tree.parse("scroll[a, b]"))
    assert.are.equal("scroll[b]", serialize.tree(edit.remove_leaf(node, "a")))
    assert.is_nil(edit.remove_leaf(assert(tree.parse("scroll[a]")), "a"))
  end)
end)

describe("edit.add_arrangement", function()
  it("adds an arrangement for these screens, with no trees yet", function()
    local after = assert(edit.add_arrangement(two(), "laptop", { lap = "eDP-1" }))
    assert.are.same({ screens = { lap = "eDP-1" }, desks = {} }, after.arrangements.laptop)
  end)

  it("refuses a name that is taken or empty, and screens that are no role -> selector map", function()
    assert.matches("already", select(2, edit.add_arrangement(two(), "solo", { a = "X" })))
    assert.matches("needs a name", select(2, edit.add_arrangement(two(), " ", { a = "X" })))
    assert.matches("at least one screen", select(2, edit.add_arrangement(two(), "n", {})))
    assert.matches("role name", select(2, edit.add_arrangement(two(), "n", { ["a b"] = "X" })))
    assert.matches("selector", select(2, edit.add_arrangement(two(), "n", { a = "" })))
    assert.matches("both", select(2, edit.add_arrangement(two(), "n", { a = "X", b = "X" })))
  end)
end)

describe("edit.rename_arrangement", function()
  it("renames it, trees and all", function()
    local before = two()
    local after = assert(edit.rename_arrangement(before, "solo", "one"))
    assert.is_nil(after.arrangements.solo)
    assert.are.same(before.arrangements.solo, after.arrangements.one)
  end)

  it("refuses a missing arrangement and a taken name", function()
    assert.matches("no arrangement 'nope'", select(2, edit.rename_arrangement(two(), "nope", "x")))
    assert.matches("already", select(2, edit.rename_arrangement(two(), "solo", "dual")))
  end)
end)

describe("edit.delete_arrangement", function()
  it("deletes it with its trees", function()
    local after = assert(edit.delete_arrangement(two(), "dual"))
    assert.is_nil(after.arrangements.dual)
    assert.is_table(after.arrangements.solo)
  end)

  it("refuses a missing arrangement", function()
    assert.matches("no arrangement 'nope'", select(2, edit.delete_arrangement(two(), "nope")))
  end)
end)

describe("edit.set_screens", function()
  it("changes a role's selector", function()
    local after = assert(edit.set_screens(two(), "dual", { big = "Dell U2723QE", side = "HEADLESS-3" }))
    assert.are.same({ big = "Dell U2723QE", side = "HEADLESS-3" }, after.arrangements.dual.screens)
    assert.are.equal("h[a:2, v[b, *]]", after.arrangements.dual.desks[3].big)
  end)

  it("renames a role, carrying its trees", function()
    local after = assert(edit.set_screens(two(), "dual", { main = "HEADLESS-2", side = "HEADLESS-3" }, { big = "main" }))
    assert.are.equal("h[a:2, v[b, *]]", after.arrangements.dual.desks[3].main)
    assert.is_nil(after.arrangements.dual.desks[3].big)
  end)

  it("drops the trees of a role it removes", function()
    local after = assert(edit.set_screens(two(), "dual", { big = "HEADLESS-2" }))
    assert.are.same({ big = "h[a:2, v[b, *]]" }, after.arrangements.dual.desks[3])
  end)

  it("refuses a rename onto a role that is not in the new screens", function()
    assert.matches("'main'", select(2, edit.set_screens(two(), "dual", { big = "X" }, { side = "main" })))
  end)
end)

describe("edit.set_pinned", function()
  it("sets the pinned roles, sorted and once each; none is an empty list", function()
    assert.are.same({ "laptop", "side" }, assert(edit.set_pinned(two(), { "side", "laptop", "side" })).pinned)
    assert.are.same({}, assert(edit.set_pinned(two(), {})).pinned)
  end)

  it("refuses a role that is no name", function()
    assert.matches("role name", select(2, edit.set_pinned(two(), { "a b" })))
  end)
end)

describe("edit.copy_trees", function()
  it("replaces an arrangement's trees with another's, role by role as mapped", function()
    local data = assert(edit.add_arrangement(two(), "work", { wide = "DP-1" }))
    data.arrangements.work.desks = { [9] = { wide = "x" } }
    local after = assert(edit.copy_trees(data, "work", "solo", { wide = "main" }))
    assert.are.same({ [3] = { wide = "h[a, b:2, c]" }, [4] = { wide = "h[mail, b]" } }, after.arrangements.work.desks)
  end)

  it("maps roles of the same name when no map is given", function()
    local data = assert(edit.add_arrangement(two(), "other", { big = "DP-1", side = "DP-2" }))
    local after = assert(edit.copy_trees(data, "other", "dual"))
    assert.are.same(two().arrangements.dual.desks, after.arrangements.other.desks)
  end)

  it("from the default, lays each desk's slots side by side on the first screen", function()
    local data = assert(edit.add_arrangement(two(), "new", { a = "DP-1", b = "DP-2" }))
    local after = assert(edit.copy_trees(data, "new", nil))
    assert.are.same({ [3] = { a = "h[a, b, c]" }, [4] = { a = "h[b, mail]" } }, after.arrangements.new.desks)
  end)

  it("refuses a missing arrangement on either side, and a map naming a role the source lacks", function()
    assert.matches("no arrangement 'nope'", select(2, edit.copy_trees(two(), "nope", "solo")))
    assert.matches("no arrangement 'nope'", select(2, edit.copy_trees(two(), "solo", "nope")))
    assert.matches("no screen role 'gone'", select(2, edit.copy_trees(two(), "solo", "dual", { main = "gone" })))
    assert.matches("no screen role 'x'", select(2, edit.copy_trees(two(), "solo", "dual", { x = "big" })))
  end)
end)
