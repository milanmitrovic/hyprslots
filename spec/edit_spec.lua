-- Edits to the editor-owned data (slots.lua), and which parts of the config
-- the editor may change at all.

local edit = require("hyprslots.edit")

local function data()
  return {
    slots = { a = {}, b = {}, c = {} },
    specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
    desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
    layouts = { solo = { screens = 1, workspaces = { [3] = { [1] = "h[a:1, b:2, c:1]" } } } },
  }
end

describe("edit.read_only", function()
  it("finds nothing read-only when config.lua passes the data straight through", function()
    local given = data()
    local raw = { slots = given.slots, specs = given.specs, desks = given.desks, layouts = given.layouts }
    assert.are.same({}, edit.read_only(raw, given))
  end)

  it("reports a field config.lua sets by code", function()
    local given = data()
    local raw = { slots = given.slots, specs = given.specs, desks = given.desks, layouts = given.layouts,
      title_matching = {} }
    assert.are.same({ "title_matching" }, edit.read_only(raw, given))
  end)

  it("reports a desk and a layout built in code among ones from the data", function()
    local given = data()
    local desks = { solo = given.desks.solo, work = { monitors = { "DP-1" }, layout = "work" } }
    local layouts = { solo = given.layouts.solo, work = { screens = 1 } }
    local raw = { slots = given.slots, specs = given.specs, desks = desks, layouts = layouts }
    assert.are.same({ "desks.work", "layouts.work" }, edit.read_only(raw, given))
  end)

  it("reports a desk or layout config.lua rebuilt from the data's as code's", function()
    local given = data()
    local desks = { solo = { monitors = given.desks.solo.monitors, layout = "solo", pinned = { 1 } } }
    local raw = { slots = given.slots, specs = given.specs, desks = desks, layouts = given.layouts }
    assert.are.same({ "desks.solo" }, edit.read_only(raw, given))
  end)

  it("reports a workspace's specs set by code", function()
    local given = data()
    local raw = { slots = given.slots, specs = { [3] = given.specs[3], [4] = { a = "foo" } },
      desks = given.desks, layouts = given.layouts }
    assert.are.same({ "specs.4" }, edit.read_only(raw, given))
  end)

  it("reports the global slots as one field: a list built in code is read-only whole", function()
    local given = data()
    local raw = { slots = { a = given.slots.a, b = {}, c = {} }, specs = given.specs, desks = given.desks,
      layouts = given.layouts }
    assert.are.same({ "slots" }, edit.read_only(raw, given))
  end)

  it("reports everything when there is no data file", function()
    local raw = { slots = {}, specs = {}, desks = {}, layouts = {} }
    assert.are.same({ "desks", "layouts", "slots", "specs" }, edit.read_only(raw, nil))
  end)
end)

describe("edit.editable", function()
  it("allows a desk or layout that comes from the data", function()
    assert.is_true(edit.editable({}, "desks", "solo"))
    assert.is_true(edit.editable({ "desks.work" }, "layouts", "work"))
  end)

  it("refuses one under a read-only path", function()
    assert.is_false(edit.editable({ "layouts.work" }, "layouts", "work"))
    assert.is_false(edit.editable({ "desks" }, "desks", "solo"))
  end)
end)

-- Global slots a, b, c, mail; workspaces 3 and 4 say which app fills which;
-- two layouts place them (dual with default trees), and three desks use them
-- (solo and laptop share one).
local function two()
  return {
    slots = { a = {}, b = { description = "middle" }, c = {}, mail = {} },
    specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" }, [4] = { mail = "thunderbird", b = "t-b4" } },
    desks = {
      solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
      laptop = { monitors = { "eDP-1" }, layout = "solo" },
      dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual", pinned = { 2 } },
    },
    layouts = {
      solo = { screens = 1, workspaces = { [3] = { [1] = "h[a:1, b:2, c:1]" }, [4] = { [1] = "h[mail, b]" } } },
      dual = { screens = 2, default = { [1] = "h[mail, b]" },
        workspaces = { [3] = { [1] = "h[a:2, v[b, *]]", [2] = "c" } } },
    },
  }
end

describe("edit.set_tree", function()
  it("writes the tree, normalized, into a copy of the data", function()
    local before = data()
    local after = assert(edit.set_tree(before, "solo", 3, 1, "h[ a:2 ,b:1, c ]"))
    assert.are.equal("h[a:2, b, c]", after.layouts.solo.workspaces[3][1])
    assert.are.equal("h[a:1, b:2, c:1]", before.layouts.solo.workspaces[3][1], "the original is untouched")
  end)

  it("takes the screen as text, the way JSON object keys arrive", function()
    local after = assert(edit.set_tree(data(), "solo", 3, "1", "a"))
    assert.are.equal("a", after.layouts.solo.workspaces[3][1])
  end)

  it("adds a workspace the layout had no tree for", function()
    local after = assert(edit.set_tree(data(), "solo", 5, 1, "x"))
    assert.are.equal("x", after.layouts.solo.workspaces[5][1])
  end)

  it("gives a workspace that showed the default trees a copy of them, the others keeping the default", function()
    local after = assert(edit.set_tree(two(), "dual", 5, 2, "c"))
    assert.are.same({ [1] = "h[mail, b]", [2] = "c" }, after.layouts.dual.workspaces[5])
    assert.are.same({ [1] = "h[mail, b]" }, after.layouts.dual.default)
    assert.is_nil(after.layouts.dual.workspaces[6])
  end)

  it("sets a default tree with \"default\"", function()
    local after = assert(edit.set_tree(two(), "dual", "default", 2, "c"))
    assert.are.same({ [1] = "h[mail, b]", [2] = "c" }, after.layouts.dual.default)
    assert.are.same(two().layouts.dual.workspaces, after.layouts.dual.workspaces)
    after = assert(edit.set_tree(data(), "solo", "default", 1, "a"))
    assert.are.same({ [1] = "a" }, after.layouts.solo.default, "a layout with no default trees gets them")
  end)

  it("refuses an unknown layout", function()
    local after, err = edit.set_tree(data(), "nope", 3, 1, "a")
    assert.is_nil(after)
    assert.matches("no layout 'nope'", err)
  end)

  it("refuses a screen the layout does not have", function()
    local after, err = edit.set_tree(data(), "solo", 3, 2, "a")
    assert.is_nil(after)
    assert.matches("layout 'solo' has screens 1 to 1, got 2", err)
    assert.matches("got side", select(2, edit.set_tree(data(), "solo", 3, "side", "a")))
  end)

  it("refuses a workspace out of range", function()
    local after, err = edit.set_tree(data(), "solo", 11, 1, "a")
    assert.is_nil(after)
    assert.matches("workspace", err)
  end)

  it("refuses a tree that does not parse", function()
    local after, err = edit.set_tree(data(), "solo", 3, 1, "h[a, b")
    assert.is_nil(after)
    assert.matches("expected", err)
  end)
end)

describe("edit.set_trees", function()
  it("sets several screens of a workspace in one edit", function()
    local after = assert(edit.set_trees(two(), "dual", 3, { [1] = "h[a:2, c]", ["2"] = "v[b, *]" }))
    assert.are.same({ [1] = "h[a:2, c]", [2] = "v[b, *]" }, after.layouts.dual.workspaces[3])
  end)

  it("refuses no trees, and stops at the first refusal", function()
    assert.matches("no trees", select(2, edit.set_trees(two(), "dual", 3, {})))
    assert.matches("got 3", select(2, edit.set_trees(two(), "dual", 3, { [1] = "a", [3] = "b" })))
  end)
end)

describe("edit.place_slot", function()
  local function scrolled(text)
    return {
      slots = { left = {}, main = {}, right = {}, mail = {} },
      layouts = { laptop = { screens = 1, workspaces = { [8] = { [1] = text } } } },
    }
  end

  it("inserts the slot into a scroll branch in the global slot order", function()
    local after, screen = edit.place_slot(scrolled("scroll[main, right]"), "laptop", 8, "left", 1)
    assert.are.equal("scroll[left, main, right]", after.layouts.laptop.workspaces[8][1])
    assert.are.equal(1, screen)
    after = assert(edit.place_slot(scrolled("scroll[left, right]"), "laptop", 8, "main", 1))
    assert.are.equal("scroll[left, main, right]", after.layouts.laptop.workspaces[8][1])
    after = assert(edit.place_slot(scrolled("scroll[left, *]"), "laptop", 8, "right", 1))
    assert.are.equal("scroll[left, right, *]", after.layouts.laptop.workspaces[8][1], "after the last slot before it")
  end)

  it("appends the slot as a new child of a tiled tree's root split", function()
    local after = assert(edit.place_slot(scrolled("h[main:2, v[left, *]]"), "laptop", 8, "right", 1))
    assert.are.equal("h[main:2, v[left, *], right]", after.layouts.laptop.workspaces[8][1])
    after = assert(edit.place_slot(scrolled("main"), "laptop", 8, "right", 1))
    assert.are.equal("h[main, right]", after.layouts.laptop.workspaces[8][1], "a bare slot becomes a split")
  end)

  it("puts the slot on the screen given, a screen with no tree taking it bare", function()
    local after = assert(edit.place_slot(two(), "dual", 3, "mail", 2))
    assert.are.same({ [1] = "h[a:2, v[b, *]]", [2] = "h[c, mail]" }, after.layouts.dual.workspaces[3])
    local data = two()
    data.layouts.dual.workspaces[3][2] = nil
    after = assert(edit.place_slot(data, "dual", 3, "mail", 2))
    assert.are.equal("mail", after.layouts.dual.workspaces[3][2])
  end)

  it("puts the slot into the shared trees for a workspace with none of its own, making no copy", function()
    local before = two()
    local after, screen, into = edit.place_slot(before, "dual", 5, "a", 1)
    assert.are.same({ [1] = "h[mail, b, a]" }, after.layouts.dual.default)
    assert.is_nil(after.layouts.dual.workspaces[5], "no copy of its own")
    assert.are.same({ [1] = "h[a:2, v[b, *]]", [2] = "c" }, after.layouts.dual.workspaces[3], "an override is untouched")
    assert.are.equal(1, screen)
    assert.are.equal("default", into)
    assert.are.same({ [1] = "h[mail, b]" }, before.layouts.dual.default, "the original is untouched")
  end)

  it("puts the slot into a workspace's own trees when it has them", function()
    local _, _, into = edit.place_slot(two(), "dual", 3, "mail", 2)
    assert.are.equal(3, into)
  end)

  it("starts the shared trees of a layout that has none, on the screen given", function()
    local data = two()
    data.layouts.dual.default = nil
    local after = assert(edit.place_slot(data, "dual", 7, "a", 2))
    assert.are.same({ [2] = "a" }, after.layouts.dual.default)
    assert.is_nil(after.layouts.dual.workspaces[7])
  end)

  it("changes nothing when the workspace's trees already place the slot, on any screen", function()
    local after, screen = edit.place_slot(two(), "dual", 3, "c", 1)
    assert.are.same(two(), after)
    assert.is_nil(screen)
    after, screen = edit.place_slot(two(), "dual", 5, "b", 1)
    assert.are.same(two(), after, "placed by the default trees it shows")
    assert.is_nil(screen)
  end)

  it("refuses an unknown slot, layout, workspace or screen", function()
    assert.matches("no slot 'zz'", select(2, edit.place_slot(two(), "dual", 3, "zz", 1)))
    assert.matches("no layout 'nope'", select(2, edit.place_slot(two(), "nope", 3, "a", 1)))
    assert.matches("workspace", select(2, edit.place_slot(two(), "dual", 11, "a", 1)))
    assert.matches("workspace", select(2, edit.place_slot(two(), "dual", "default", "a", 1)))
    assert.matches("has screens 1 to 2, got 3", select(2, edit.place_slot(two(), "dual", 5, "a", 3)))
  end)
end)

describe("edit.redundant_with_default", function()
  local redundant = edit.redundant_with_default

  it("is the default tree itself, or it with some slots missing", function()
    assert.is_true(redundant("scroll[left, main, right]", "scroll[left, main, right]"))
    assert.is_true(redundant("scroll[main, right]", "scroll[left, main, right]"))
    assert.is_true(redundant("scroll[main]", "scroll[left, main, right]"))
    assert.is_true(redundant("h[left, right]", "h[left, main, right]"))
    assert.is_true(redundant("main", "h[left, main, right]"), "a split left with one slot is that slot")
  end)

  it("keeps the ratios pruning leaves behind, and only those", function()
    assert.is_true(redundant("h[main:2, right]", "h[left, main:2, right]"))
    assert.is_true(redundant("h[main:2, right:2]", "h[main, right]"), "the same shares in other numbers")
    assert.is_false(redundant("h[left, main:2, right]", "h[left, main, right]"), "main twice as wide")
    assert.is_false(redundant("h[main, right]", "h[left, main:2, right]"), "pruning keeps main at 2:1")
    assert.is_true(redundant("h[a, b:2]", "h[a, v[b, c]:2]"), "a nested split left with one slot keeps its share")
  end)

  it("is no override the default could stand for: another kind, nesting, order or slot", function()
    assert.is_false(redundant("h[left, main, right]", "scroll[left, main, right]"), "tiles, not scrolling")
    assert.is_false(redundant("v[left, main]", "h[left, main, right]"), "stacked, not side by side")
    assert.is_false(redundant("h[main, left]", "h[left, main, right]"), "another order")
    assert.is_false(redundant("h[left, v[main, right]]", "h[left, main, right]"), "nested otherwise")
    assert.is_false(redundant("h[left, main, mail]", "h[left, main, right]"), "a slot the default does not place")
  end)

  it("treats the overflow leaf as part of the shape, not a slot that closes up", function()
    assert.is_false(redundant("h[left, main]", "h[left, main, *]"))
    assert.is_false(redundant("h[left, main, *]", "h[left, main]"))
    assert.is_true(redundant("h[main, *]", "h[left, main, *]"))
  end)

  it("is a screen with no tree when the default has none there, or places nothing a slot could fill", function()
    assert.is_true(redundant(nil, nil))
    assert.is_true(redundant(nil, "h[left, main, right]"), "every slot missing: nothing left")
    assert.is_false(redundant("main", nil))
    assert.is_false(redundant(nil, "h[left, *]"), "the overflow leaf alone is still a tree")
  end)

  it("is no match for a tree that does not parse", function()
    assert.is_false(redundant("h[", "h[left, main]"))
    assert.is_false(redundant("main", "h["))
  end)
end)

describe("edit.fold_trees", function()
  -- The cutover's laptop layout: each workspace's own copy of one tree, cut
  -- down to the slots it had specs for, and one real difference.
  local function cutover()
    return {
      slots = { left = {}, main = {}, right = {}, mail = {} },
      specs = { [2] = { main = "t-main" }, [5] = { left = "t-l", right = "t-r" } },
      layouts = {
        wide = { screens = 1, default = { [1] = "h[left, main, right]" }, workspaces = {
          [1] = { [1] = "h[left, main, right]" },
          [2] = { [1] = "h[main, right]" },
          [3] = { [1] = "h[left, main:2, right]" },
          [4] = { [1] = "main" },
          [5] = { [1] = "h[left, right]" },
        } },
        other = { screens = 1, workspaces = { [1] = { [1] = "main" } } },
      },
    }
  end

  it("drops every workspace's trees that are the shared ones with slots missing, keeping the real overrides", function()
    local before = cutover()
    local after, report = edit.fold_trees(before, "wide")
    assert.are.same({ [3] = { [1] = "h[left, main:2, right]" } }, after.layouts.wide.workspaces)
    assert.are.same({ 1, 2, 4, 5 }, report.folded)
    assert.are.same({ { workspace = 3, reason = "screen 1's tree is not the shared one with slots left out" } },
      report.kept)
    assert.are.same(cutover(), before, "the data given is untouched")
    assert.are.same({ [1] = "main" }, after.layouts.other.workspaces[1], "another layout is not folded")
  end)

  it("compares every screen, a screen with no tree of its own matching one with no shared tree", function()
    local data = {
      slots = { left = {}, main = {}, right = {} },
      layouts = { dual = { screens = 2, default = { [2] = "h[left, main, right]" }, workspaces = {
        [1] = { [2] = "h[main, right]" },
        [2] = { [1] = "main", [2] = "h[left, right]" },
        [3] = {},
      } } },
    }
    local after, report = edit.fold_trees(data, "dual")
    assert.are.same({ [2] = { [1] = "main", [2] = "h[left, right]" } }, after.layouts.dual.workspaces)
    assert.are.same({ 1, 3 }, report.folded, "workspace 3 showed nothing: every shared slot is empty there")
  end)

  it("keeps an override whose workspace has a spec the shared trees would start placing", function()
    local data = cutover()
    data.specs[4] = { main = "t-main", mail = "thunderbird" }
    data.layouts.wide.default[1] = "h[left, main, right, mail]"
    data.layouts.wide.workspaces[4][1] = "main"
    local after, report = edit.fold_trees(data, "wide")
    assert.are.same({ [1] = "main" }, after.layouts.wide.workspaces[4])
    assert.are.same({ workspace = 4, reason = "it has a spec for mail, which its own trees leave out and the shared ones place" },
      report.kept[2])
  end)

  it("takes the workspaces table away once nothing is left in it", function()
    local data = cutover()
    data.layouts.wide.workspaces[3] = nil
    local after, report = edit.fold_trees(data, "wide")
    assert.is_nil(after.layouts.wide.workspaces)
    assert.are.same({}, report.kept)
  end)

  it("refuses a layout that is not there", function()
    assert.matches("no layout 'nope'", select(2, edit.fold_trees(cutover(), "nope")))
  end)
end)

describe("edit.drop_override", function()
  it("sends a workspace back to the shared trees", function()
    local after = assert(edit.drop_override(two(), "dual", 3))
    assert.is_nil(after.layouts.dual.workspaces)
    assert.are.same({ [1] = "h[mail, b]" }, after.layouts.dual.default)
    after = assert(edit.drop_override(two(), "solo", 3))
    assert.are.same({ [4] = { [1] = "h[mail, b]" } }, after.layouts.solo.workspaces, "the other workspaces keep theirs")
  end)

  it("drops one screen of it, and the rest once that leaves it the shared trees", function()
    local data = two()
    data.layouts.dual.default[2] = "c"
    data.layouts.dual.workspaces[3][2] = "c"
    local after = assert(edit.drop_override(data, "dual", 3, 2))
    assert.are.same({ [1] = "h[a:2, v[b, *]]", [2] = "c" }, after.layouts.dual.workspaces[3], "screen 2 was the shared one")
    after = assert(edit.drop_override(after, "dual", 3, 1))
    assert.is_nil(after.layouts.dual.workspaces, "nothing of its own left")
  end)

  it("refuses a workspace on the shared trees, and an unknown layout, workspace or screen", function()
    assert.matches("workspace 5 uses the shared trees already", select(2, edit.drop_override(two(), "dual", 5)))
    assert.matches("no layout 'nope'", select(2, edit.drop_override(two(), "nope", 3)))
    assert.matches("workspace", select(2, edit.drop_override(two(), "dual", 11)))
    assert.matches("got 3", select(2, edit.drop_override(two(), "dual", 3, 3)))
  end)
end)

describe("edit.reset_tree", function()
  local saved = two

  it("puts a workspace's own tree back to the saved one", function()
    local edited = assert(edit.set_tree(two(), "solo", 3, 1, "a"))
    local after = assert(edit.reset_tree(edited, saved(), "solo", 3, 1))
    assert.are.equal("h[a:1, b:2, c:1]", after.layouts.solo.workspaces[3][1])
  end)

  it("sends a workspace back to the default trees once its copy is them again", function()
    local edited = assert(edit.set_tree(two(), "dual", 5, 2, "c"))
    local after = assert(edit.reset_tree(edited, saved(), "dual", 5, 2))
    assert.is_nil(after.layouts.dual.workspaces[5])
    assert.are.same({ [1] = "h[mail, b]" }, after.layouts.dual.default)
  end)

  it("keeps a workspace's copy while another of its screens differs from the default", function()
    local edited = assert(edit.set_tree(two(), "dual", 5, 2, "c"))
    edited = assert(edit.set_tree(edited, "dual", 5, 1, "mail"))
    local after = assert(edit.reset_tree(edited, saved(), "dual", 5, 2))
    assert.are.same({ [1] = "mail" }, after.layouts.dual.workspaces[5])
  end)

  it("puts a default tree back, and changes nothing on a workspace that shows the default ones", function()
    local edited = assert(edit.set_tree(two(), "dual", "default", 1, "mail"))
    local after = assert(edit.reset_tree(edited, saved(), "dual", "default", 1))
    assert.are.same({ [1] = "h[mail, b]" }, after.layouts.dual.default)
    after = assert(edit.reset_tree(two(), saved(), "dual", 7, 1))
    assert.are.same(two(), after)
  end)

  it("takes a tree the saved data does not have away", function()
    local edited = assert(edit.add_layout(two(), "wide", 2))
    edited = assert(edit.set_tree(edited, "wide", 3, 1, "a"))
    local after = assert(edit.reset_tree(edited, saved(), "wide", 3, 1))
    assert.is_nil(after.layouts.wide.workspaces)
  end)

  it("refuses an unknown layout, workspace or screen", function()
    assert.matches("no layout 'nope'", select(2, edit.reset_tree(two(), saved(), "nope", 3, 1)))
    assert.matches("workspace", select(2, edit.reset_tree(two(), saved(), "dual", 0, 1)))
    assert.matches("got 3", select(2, edit.reset_tree(two(), saved(), "dual", 3, 3)))
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
  it("removes the slot, takes it out of every tree of every workspace, and drops every workspace's spec for it", function()
    local after = assert(edit.remove_slot(two(), "b"))
    assert.is_nil(after.slots.b)
    assert.are.equal("h[a, c]", after.layouts.solo.workspaces[3][1])
    assert.are.equal("mail", after.layouts.solo.workspaces[4][1])
    assert.are.equal("h[a:2, *]", after.layouts.dual.workspaces[3][1])
    assert.are.equal("mail", after.layouts.dual.default[1], "the default trees too")
    assert.are.same({ a = "t-a", c = "t-c" }, after.specs[3])
    assert.are.same({ mail = "thunderbird" }, after.specs[4])
  end)

  it("drops a branch the slot was all of, and a workspace's specs left empty", function()
    local after = assert(edit.remove_slot(two(), "mail"))
    assert.is_nil(after.specs[4].mail)
    after = assert(edit.remove_slot(after, "b"))
    assert.is_nil(after.specs[4], "workspace 4 has no specs left")
    assert.are.same({}, after.layouts.solo.workspaces[4], "nor a tree (an empty set still replaces the default)")
    assert.is_nil(after.layouts.dual.default, "default trees left with none go")
    after = assert(edit.remove_slot(two(), "c"))
    assert.is_nil(after.layouts.dual.workspaces[3][2])
    assert.are.equal("h[a:2, v[b, *]]", after.layouts.dual.workspaces[3][1])
  end)

  it("refuses a slot that is not defined", function()
    assert.matches("no slot 'zz'", select(2, edit.remove_slot(two(), "zz")))
  end)
end)

describe("edit.slot_uses", function()
  it("says which trees place a slot and which workspaces have a spec for it", function()
    assert.are.same({ trees = { "dual/default/1", "dual/3/1", "solo/3/1", "solo/4/1" }, specs = { 3, 4 } },
      edit.slot_uses(two(), "b"))
    assert.are.same({ trees = {}, specs = {} }, edit.slot_uses(assert(edit.add_slot(two(), "x")), "x"))
  end)
end)

describe("edit.rename_slot", function()
  it("renames the slot, every tree of every workspace and layout, and every workspace's spec for it", function()
    local after = assert(edit.rename_slot(two(), "b", "middle"))
    assert.is_nil(after.slots.b)
    assert.are.same({ description = "middle" }, after.slots.middle, "its description follows")
    assert.are.equal("h[a, middle:2, c]", after.layouts.solo.workspaces[3][1])
    assert.are.equal("h[mail, middle]", after.layouts.solo.workspaces[4][1])
    assert.are.equal("h[a:2, v[middle, *]]", after.layouts.dual.workspaces[3][1])
    assert.are.equal("h[mail, middle]", after.layouts.dual.default[1])
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
  it("writes the app that fills a global slot on a workspace, trimmed, into a copy", function()
    local before = two()
    local after = assert(edit.set_spec(before, 3, "a", "  kitty/deltaf "))
    assert.are.equal("kitty/deltaf", after.specs[3].a)
    assert.are.equal("t-a", before.specs[3].a)
  end)

  it("gives a workspace that had no specs its first one, replacing nothing else", function()
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

  it("refuses a slot that is not defined, and a workspace out of range", function()
    assert.matches("no slot 'zz' %(add it in the editor's Layout tab, s then a%)", select(2, edit.set_spec(two(), 3, "zz", "x")))
    assert.matches("workspace", select(2, edit.set_spec(two(), 0, "a", "x")))
  end)
end)

describe("edit.clear_spec", function()
  it("drops a workspace's spec for a slot, and the workspace's specs when none is left", function()
    local after = assert(edit.clear_spec(two(), 4, "b"))
    assert.are.same({ mail = "thunderbird" }, after.specs[4])
    after = assert(edit.clear_spec(after, 4, "mail"))
    assert.is_nil(after.specs[4])
    assert.are.same({ description = "middle" }, after.slots.b, "the global slot stays")
    assert.are.equal("h[mail, b]", after.layouts.solo.workspaces[4][1], "and so do the trees")
  end)

  it("refuses a workspace with no spec for the slot", function()
    assert.matches("workspace 7 has no spec for 'a'", select(2, edit.clear_spec(two(), 7, "a")))
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

describe("edit.add_desk", function()
  it("adds a desk for monitor selectors using a layout for as many screens", function()
    local before = two()
    local after = assert(edit.add_desk(before, "office", { "Dell U2723QE", "SER-3" }, "dual"))
    assert.are.same({ monitors = { "Dell U2723QE", "SER-3" }, layout = "dual" }, after.desks.office)
    assert.is_nil(before.desks.office, "the original is untouched")
    assert.are.same({ desks = { x = { monitors = { "eDP-1" }, layout = "l" } }, layouts = { l = { screens = 1 } } },
      assert(edit.add_desk({ layouts = { l = { screens = 1 } } }, "x", { "eDP-1" }, "l")), "data with no desks yet")
  end)

  it("refuses a taken or bad name, no monitors, a selector twice, and a layout that does not fit", function()
    assert.matches("a desk called 'dual' already exists", select(2, edit.add_desk(two(), "dual", { "X" }, "solo")))
    assert.matches("needs a name", select(2, edit.add_desk(two(), " ", { "X" }, "solo")))
    assert.matches("no '/'", select(2, edit.add_desk(two(), "a/b", { "X" }, "solo")))
    assert.matches("at least one monitor", select(2, edit.add_desk(two(), "n", {}, "solo")))
    assert.matches("needs a selector", select(2, edit.add_desk(two(), "n", { "" }, "solo")))
    assert.matches("listed twice", select(2, edit.add_desk(two(), "n", { "X", "X" }, "dual")))
    assert.matches("no layout 'nope'", select(2, edit.add_desk(two(), "n", { "X" }, "nope")))
    assert.matches("layout 'dual' is for 2 screens, and the desk has 1 monitor",
      select(2, edit.add_desk(two(), "n", { "X" }, "dual")))
  end)
end)

describe("edit.rename_desk", function()
  it("renames it, monitors, layout and pinned screens and all", function()
    local before = two()
    local after = assert(edit.rename_desk(before, "dual", "office"))
    assert.is_nil(after.desks.dual)
    assert.are.same(before.desks.dual, after.desks.office)
    assert.are.same(two(), assert(edit.rename_desk(two(), "dual", "dual")), "to itself, a no-op")
  end)

  it("refuses a missing desk and a taken or bad name", function()
    assert.matches("no desk 'nope'", select(2, edit.rename_desk(two(), "nope", "x")))
    assert.matches("a desk called 'solo' already exists", select(2, edit.rename_desk(two(), "dual", "solo")))
    assert.matches("no '/'", select(2, edit.rename_desk(two(), "dual", " x")))
  end)
end)

describe("edit.delete_desk", function()
  it("deletes it; its layout stays", function()
    local after = assert(edit.delete_desk(two(), "dual"))
    assert.is_nil(after.desks.dual)
    assert.are.same(two().layouts, after.layouts)
  end)

  it("refuses a missing desk", function()
    assert.matches("no desk 'nope'", select(2, edit.delete_desk(two(), "nope")))
  end)
end)

describe("edit.set_desk_layout", function()
  it("points a desk at another layout for as many screens", function()
    local data = assert(edit.add_layout(two(), "wide", 2))
    local after = assert(edit.set_desk_layout(data, "dual", "wide"))
    assert.are.equal("wide", after.desks.dual.layout)
    assert.are.same({ 2 }, after.desks.dual.pinned, "pinned screens stay")
  end)

  it("refuses a missing desk, a missing layout and one for another number of screens", function()
    assert.matches("no desk 'nope'", select(2, edit.set_desk_layout(two(), "nope", "solo")))
    assert.matches("no layout 'nope'", select(2, edit.set_desk_layout(two(), "dual", "nope")))
    assert.matches("layout 'solo' is for 1 screen, and the desk has 2 monitors",
      select(2, edit.set_desk_layout(two(), "dual", "solo")))
  end)
end)

describe("edit.set_pinned", function()
  it("sets a desk's pinned screens, sorted and once each; none removes them", function()
    assert.are.same({ 1, 2 }, assert(edit.set_pinned(two(), "dual", { 2, 1, 2 })).desks.dual.pinned)
    assert.are.same({ 1 }, assert(edit.set_pinned(two(), "dual", { 1.0 })).desks.dual.pinned, "JSON numbers")
    assert.is_nil(assert(edit.set_pinned(two(), "dual", {})).desks.dual.pinned)
  end)

  it("refuses a screen the desk does not have, a list that is none, and a missing desk", function()
    assert.matches("desk 'solo' has screens 1 to 1, got 2", select(2, edit.set_pinned(two(), "solo", { 2 })))
    assert.matches("got 0", select(2, edit.set_pinned(two(), "solo", { 0 })))
    assert.matches("got side", select(2, edit.set_pinned(two(), "dual", { "side" })))
    assert.matches("must be a list", select(2, edit.set_pinned(two(), "dual", 2)))
    assert.matches("no desk 'nope'", select(2, edit.set_pinned(two(), "nope", {})))
  end)
end)

describe("edit.add_layout", function()
  it("adds a layout for a number of screens, empty or with default trees", function()
    assert.are.same({ screens = 2 }, assert(edit.add_layout(two(), "wide", 2)).layouts.wide)
    assert.are.same({ screens = 2 }, assert(edit.add_layout(two(), "wide", 2.0, {})).layouts.wide)
    local after = assert(edit.add_layout(two(), "home", 2, { [1] = "h[a, b]" }))
    assert.are.same({ screens = 2, default = { [1] = "h[a, b]" } }, after.layouts.home)
    assert.are.same({ x = { screens = 1 } }, assert(edit.add_layout({}, "x", 1)).layouts, "data with no layouts yet")
  end)

  it("refuses a taken or bad name and a number of screens out of range", function()
    assert.matches("a layout called 'dual' already exists", select(2, edit.add_layout(two(), "dual", 2)))
    assert.matches("needs a name", select(2, edit.add_layout(two(), "", 2)))
    assert.matches("a layout is for 1 to 10 screens, got 0", select(2, edit.add_layout(two(), "n", 0)))
    assert.matches("got 11", select(2, edit.add_layout(two(), "n", 11)))
    assert.matches("got 1.5", select(2, edit.add_layout(two(), "n", 1.5)))
  end)
end)

describe("edit.copy_layout", function()
  it("copies a layout, default trees and all, under a new name; no desk moves", function()
    local before = two()
    local after = assert(edit.copy_layout(before, "dual", "dual-2"))
    assert.are.same(before.layouts.dual, after.layouts["dual-2"])
    assert.are.equal("dual", after.desks.dual.layout)
    after.layouts["dual-2"].default[1] = "a"
    assert.are.equal("h[mail, b]", after.layouts.dual.default[1], "a copy, not the same table")
  end)

  it("refuses a missing source and a taken name", function()
    assert.matches("no layout 'nope'", select(2, edit.copy_layout(two(), "nope", "x")))
    assert.matches("a layout called 'solo' already exists", select(2, edit.copy_layout(two(), "dual", "solo")))
  end)
end)

describe("edit.rename_layout", function()
  it("renames it; every desk using it follows", function()
    local after = assert(edit.rename_layout(two(), "solo", "one"))
    assert.is_nil(after.layouts.solo)
    assert.are.same(two().layouts.solo, after.layouts.one)
    assert.are.same({ "one", "one", "dual" }, { after.desks.solo.layout, after.desks.laptop.layout, after.desks.dual.layout })
  end)

  it("refuses a missing layout and a taken name", function()
    assert.matches("no layout 'nope'", select(2, edit.rename_layout(two(), "nope", "x")))
    assert.matches("a layout called 'dual' already exists", select(2, edit.rename_layout(two(), "solo", "dual")))
  end)
end)

describe("edit.layout_users", function()
  it("lists the desks using a layout, sorted", function()
    assert.are.same({ "laptop", "solo" }, edit.layout_users(two(), "solo"))
    assert.are.same({}, edit.layout_users(two(), "nope"))
  end)
end)

describe("edit.delete_layout", function()
  it("deletes one no desk uses", function()
    local data = assert(edit.add_layout(two(), "spare", 1))
    local after = assert(edit.delete_layout(data, "spare"))
    assert.are.same(two(), after)
  end)

  it("is refused while desks use it, saying which", function()
    local after, err = edit.delete_layout(two(), "solo")
    assert.is_nil(after)
    assert.are.equal("layout 'solo' is used by desks laptop, solo; delete it with remap: <another layout for 1 screen>", err)
    assert.matches("used by desk dual;", select(2, edit.delete_layout(two(), "dual")))
  end)

  it("with remap, the desks that used it use that one", function()
    local data = assert(edit.add_layout(two(), "one", 1))
    local after = assert(edit.delete_layout(data, "solo", "one"))
    assert.is_nil(after.layouts.solo)
    assert.are.same({ "one", "one" }, { after.desks.solo.layout, after.desks.laptop.layout })
  end)

  it("refuses a remap that is missing, itself, or for another number of screens", function()
    assert.matches("no layout 'nope'", select(2, edit.delete_layout(two(), "solo", "nope")))
    assert.matches("cannot remap layout 'solo' to itself", select(2, edit.delete_layout(two(), "solo", "solo")))
    assert.matches("layout 'dual' is for 2 screens, and 'solo' for 1 screen", select(2, edit.delete_layout(two(), "solo", "dual")))
    assert.matches("no layout 'nope'", select(2, edit.delete_layout(two(), "nope")))
  end)
end)
