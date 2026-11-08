-- Test seam S2: what the editor's Slots and Arrangements views need from the
-- api (docs/design.md §9): global slot edits (add, remove, rename across
-- every tree and desk, describe), per-desk specs (set, clear, take a
-- window's spec, the Assignment view's a) and arrangement edits (create from
-- the connected screens, rename, delete, screens, pinned, copy trees). Every
-- edit stays in memory until save, re-runs config.lua, and re-routes.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

describe("the Slots and Arrangements views' api", function()
  local hl, hyprslots

  local function open(id, class, workspace, title)
    local window = hl_stub.window(id, class, { title = title or class, workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.get_workspace(workspace).windows = hl.get_workspace(workspace).windows + 1
    hl.emit("window.open", window)
    return window
  end

  local function state()
    return engine.state(hyprslots)
  end

  local function call(name, args)
    return engine.call(hyprslots, name, json.encode(args or {}))
  end

  local function ok(name, args)
    local reply = call(name, args)
    assert.is_true(reply.ok, reply.error)
    return reply
  end

  local function tree_of(s, arrangement, desk, role)
    local branch = s.arrangements[arrangement].desks[tostring(desk)]
    return branch and branch[role] and branch[role].tree
  end

  local function setup(slots, config)
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl.monitors[1].description = "Dell U2723QE ABC123"
    hl.monitors[2].serial = "SER-3"
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    -- dual: side = "left", big = "h[main:2, right:1]"; single: big = "h[left, main, right]"
    hyprslots = engine.setup(slots or engine.TWO_SCREENS, config)
  end

  before_each(function() setup() end)
  after_each(engine.cleanup)

  describe("state", function()
    it("lists the connected monitors with what selects each", function()
      assert.are.same({
        { name = "HEADLESS-2", description = "Dell U2723QE ABC123", serial = "", focused = true },
        { name = "HEADLESS-3", description = "", serial = "SER-3", focused = false },
      }, state().monitors)
    end)

    it("lists the global slots with their descriptions, and each desk's specs", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      local s = state()
      assert.are.same({ { name = "left" }, { name = "main", description = "the editor" }, { name = "right" } }, s.slots)
      assert.are.same({ ["3"] = { left = "t-left", main = "t-main", right = "t-right" } }, s.specs)
      assert.is_nil(s.descriptions)
    end)
  end)

  describe("add_slot", function()
    it("defines a global slot, with its description, that every desk's trees may then place", function()
      local reply = ok("add_slot", { slot = "chat", description = "team chat" })
      assert.are.equal("chat", reply.slot)
      local s = state()
      assert.are.same({ name = "chat", description = "team chat" }, s.slots[1])
      assert.is_true(s.dirty)
      ok("set_tree", { arrangement = "single", desk = 5, role = "big", tree = "chat" })
    end)

    it("refuses a taken or malformed name", function()
      assert.matches("there is a slot 'main' already", call("add_slot", { slot = "main" }).error)
      assert.matches("slot name", call("add_slot", { slot = "a b" }).error)
    end)

    it("refuses a slot list config.lua builds in code", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
local slots = { left = {}, main = {}, right = {}, extra = {} }
return { slots = slots, specs = data.specs, arrangements = data.arrangements }
]])
      local reply = call("add_slot", { slot = "chat" })
      assert.is_false(reply.ok)
      assert.matches("slots are set by code in config.lua", reply.error)
    end)
  end)

  describe("remove_slot", function()
    it("refuses a slot that trees place or desks have specs for, saying where", function()
      local reply = call("remove_slot", { slot = "right" })
      assert.is_false(reply.ok)
      assert.matches("dual/3/big, single/3/big", reply.error)
      assert.matches("desk 3", reply.error)
      assert.matches("force", reply.error)
      assert.are.equal(3, #state().slots)
    end)

    it("with force, takes it out of every tree of every desk and every desk's specs", function()
      local right = open(1, "t-right", 1)
      local reply = ok("remove_slot", { slot = "right", force = true })
      assert.are.same({ "dual/3/big", "single/3/big" }, reply.trees)
      assert.are.same({ 3 }, reply.specs)
      local s = state()
      assert.are.same({ { name = "left" }, { name = "main" } }, s.slots)
      assert.is_nil(s.specs["3"].right)
      assert.are.equal("main", tree_of(s, "dual", 3, "big"))
      assert.are.equal("h[left, main]", tree_of(s, "single", 3, "big"))
      assert.is_nil(s.assignments[right.address])
    end)

    it("removes an unused slot without force", function()
      ok("add_slot", { slot = "chat" })
      ok("remove_slot", { slot = "chat" })
      assert.are.equal(3, #state().slots)
    end)
  end)

  describe("rename_slot", function()
    it("renames a slot everywhere: every tree, every desk's spec, its description", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      ok("set_spec", { desk = 5, slot = "main", spec = "kitty" })
      local reply = ok("rename_slot", { slot = "main", to = "editor" })
      assert.are.equal("editor", reply.to)
      assert.are.equal(2, reply.trees)
      assert.are.same({ 3, 5 }, reply.specs)
      local s = state()
      assert.are.same({ name = "editor", description = "the editor" }, s.slots[1])
      assert.are.equal("t-main", s.specs["3"].editor)
      assert.are.equal("kitty", s.specs["5"].editor)
      assert.is_nil(s.specs["3"].main)
      assert.are.equal("h[editor:2, right]", tree_of(s, "dual", 3, "big"))
      assert.are.equal("h[left, editor, right]", tree_of(s, "single", 3, "big"))
    end)

    it("keeps the window in its slot, a hand-made assignment too", function()
      local main = open(1, "t-main", 1)
      local stranger = open(2, "firefox", 1)
      ok("assign", { address = stranger.address, desk = 3, slot = "right" })
      ok("rename_slot", { slot = "main", to = "editor" })
      ok("rename_slot", { slot = "right", to = "aside" })
      local s = state()
      assert.are.same({ desk = 3, slot = "editor" }, s.assignments[main.address])
      assert.are.same({ desk = 3, slot = "aside", manual = true }, s.assignments[stranger.address])
    end)

    it("carries a keyboard-resized tree along", function()
      local main = open(1, "t-main", 3)
      local right = open(2, "t-right", 3)
      hl.active_window = main
      local ctx = hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { main, right })
      assert.is_true(hl.layouts.slots.layout_msg(ctx, "nudge r 0.1"))
      local nudged = state().resized["dual/3/big"].tree
      assert.matches("^h%[main:%d+, right:%d+%]$", nudged)
      ok("rename_slot", { slot = "main", to = "editor" })
      local s = state()
      local expected = (nudged:gsub("main", "editor"))
      assert.are.equal(expected, s.resized["dual/3/big"].tree)
      assert.are.equal(expected, tree_of(s, "dual", 3, "big"))
    end)

    it("refuses a name that is taken", function()
      assert.matches("there is a slot 'left' already", call("rename_slot", { slot = "main", to = "left" }).error)
    end)

    it("is written by save, in the global shape", function()
      ok("rename_slot", { slot = "main", to = "editor" })
      local path = ok("save").path
      local saved = read(path)
      assert.matches("slots = {\n    editor = {},\n    left = {},\n    right = {},\n  },", saved)
      assert.matches('editor = "t%-main"', saved)
      assert.matches('big = "h%[editor:2, right%]"', saved)
      assert.is_false(state().dirty)
    end)
  end)

  describe("describe_slot", function()
    it("sets a slot's description in memory; empty clears it", function()
      ok("describe_slot", { slot = "left", description = "notes" })
      assert.are.same({ name = "left", description = "notes" }, state().slots[1])
      assert.is_true(state().dirty)
      ok("describe_slot", { slot = "left", description = "" })
      assert.are.same({ name = "left" }, state().slots[1])
    end)

    it("refuses a slot that is not defined", function()
      assert.matches("no slot 'zz'", call("describe_slot", { slot = "zz", description = "x" }).error)
    end)
  end)

  describe("set_spec", function()
    it("sets the app that fills a global slot on a desk, in memory, and the window it names takes the slot", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      local reply = ok("set_spec", { desk = 3, slot = "main", spec = " kitty/deltaf " })
      assert.are.same({ desk = 3, slot = "main", spec = "kitty/deltaf" }, { desk = reply.desk, slot = reply.slot, spec = reply.spec })
      local s = state()
      assert.are.equal("kitty/deltaf", s.specs["3"].main)
      assert.is_true(s.dirty)
      assert.are.same({ desk = 3, slot = "main" }, s.assignments[editor.address])
      assert.are.equal(3, editor.workspace.id)
    end)

    it("gives a desk with no specs its first, for a global slot", function()
      ok("set_spec", { desk = 7, slot = "main", spec = "spotify" })
      assert.are.same({ main = "spotify" }, state().specs["7"])
      assert.are.same({ 3, 7 }, state().desks)
    end)

    it("refuses a spec the grammar rejects, or a slot that is not defined, changing nothing", function()
      local seq = state().seq
      local reply = call("set_spec", { desk = 3, slot = "main", spec = "[Tag" })
      assert.is_false(reply.ok)
      assert.matches("closing ']'", reply.error)
      assert.matches("no slot 'zz'", call("set_spec", { desk = 3, slot = "zz", spec = "x" }).error)
      assert.are.equal("t-main", state().specs["3"].main)
      assert.are.equal(seq, state().seq)
    end)

    it("announces the change", function()
      local seq = state().seq
      ok("set_spec", { desk = 3, slot = "main", spec = "foo" })
      local events = hl.dispatched_of("event")
      assert.are.equal("hyprslots changed " .. state().seq, events[#events])
      assert.is_true(state().seq > seq)
    end)

    it("refuses a desk whose specs config.lua builds in code", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
local specs = { [3] = data.specs[3], [4] = { main = "thunderbird" } }
return { slots = data.slots, specs = specs, arrangements = data.arrangements }
]])
      local reply = call("set_spec", { desk = 4, slot = "main", spec = "x" })
      assert.is_false(reply.ok)
      assert.matches("desk 4's specs are set by code in config.lua", reply.error)
    end)
  end)

  describe("clear_spec", function()
    it("drops a desk's spec for a slot: its window leaves the slot, the slot stays", function()
      local right = open(1, "t-right", 1)
      assert.are.same({ desk = 3, slot = "right" }, state().assignments[right.address])
      local reply = ok("clear_spec", { desk = 3, slot = "right" })
      assert.are.same({ 3, "right" }, { reply.desk, reply.slot })
      local s = state()
      assert.is_nil(s.specs["3"].right)
      assert.are.equal(3, #s.slots)
      assert.is_nil(s.assignments[right.address])
      assert.are.equal("h[main:2, right]", tree_of(s, "dual", 3, "big"))
    end)

    it("refuses a desk with no spec for the slot", function()
      assert.matches("desk 4 has no spec for 'main'", call("clear_spec", { desk = 4, slot = "main" }).error)
    end)
  end)

  describe("take_spec (the Assignment view's a)", function()
    it("writes the window's spec into the desk's slot and puts the window there", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { desk = 3, slot = "right", address = editor.address })
      assert.are.equal("kitty/deltaf", reply.spec)
      assert.are.equal("t-right", reply.replaced)
      local s = state()
      assert.are.equal("kitty/deltaf", s.specs["3"].right)
      assert.are.same({ desk = 3, slot = "right" }, s.assignments[editor.address], "a spec assignment, not by hand")
      assert.are.equal(3, editor.workspace.id)
      assert.is_true(s.dirty)
    end)

    it("gives the slot to that window over an older one the new spec also matches", function()
      local older = open(1, "kitty", 1, "deltaf | logs")
      local chosen = open(2, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { desk = 5, slot = "main", address = chosen.address })
      assert.are.equal("kitty/deltaf", reply.spec)
      local s = state()
      assert.are.same({ desk = 5, slot = "main" }, s.assignments[chosen.address])
      assert.is_nil(s.assignments[older.address])
    end)

    it("displaces the window that held the slot", function()
      local right = open(1, "t-right", 1)
      local editor = open(2, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { desk = 3, slot = "right", address = editor.address })
      assert.are.equal(right.address, reply.displaced)
      assert.is_nil(state().assignments[right.address])
    end)

    it("refuses a window that is not open, or a slot that is not defined, changing nothing", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      assert.are.equal("no open window 0xdead", call("take_spec", { desk = 3, slot = "right", address = "0xdead" }).error)
      assert.matches("no slot 'zz'", call("take_spec", { desk = 3, slot = "zz", address = editor.address }).error)
      assert.is_nil(state().assignments[editor.address])
      assert.is_false(state().dirty)
    end)
  end)

  describe("add_arrangement", function()
    it("creates an arrangement for the given screens, empty or with the default trees", function()
      ok("add_arrangement", { name = "work", screens = { wide = "Dell U2723QE ABC123", tall = "SER-3" } })
      ok("add_arrangement", { name = "home", screens = { a = "HEADLESS-2" }, default = true })
      local s = state()
      assert.are.same({ tall = "SER-3", wide = "Dell U2723QE ABC123" }, s.arrangements.work.screens)
      assert.are.same({}, s.arrangements.work.desks)
      assert.are.equal("h[left, main, right]", tree_of(s, "home", 3, "a"))
    end)

    it("copies another arrangement's trees, and these screens run it when it sorts first", function()
      local reply = ok("add_arrangement", { name = "aaa", screens = { big = "HEADLESS-2", side = "HEADLESS-3" }, from = "dual" })
      assert.are.equal("aaa", reply.active)
      local s = state()
      assert.are.equal("aaa", s.arrangement)
      assert.are.equal("h[main:2, right]", tree_of(s, "aaa", 3, "big"))
    end)

    it("says what runs when another arrangement still matches first", function()
      local reply = ok("add_arrangement", { name = "zzz", screens = { big = "HEADLESS-2", side = "HEADLESS-3" } })
      assert.are.equal("dual", reply.active)
    end)

    it("refuses a name that exists", function()
      assert.matches("already exists", call("add_arrangement", { name = "dual", screens = { a = "X" } }).error)
    end)
  end)

  describe("rename_arrangement", function()
    it("renames it; the active one stays active under its new name", function()
      ok("rename_arrangement", { arrangement = "dual", to = "desk" })
      local s = state()
      assert.are.equal("desk", s.arrangement)
      assert.is_nil(s.arrangements.dual)
    end)

    it("needs the arrangement named", function()
      assert.matches("name one", call("rename_arrangement", { to = "x" }).error)
    end)
  end)

  describe("delete_arrangement", function()
    it("deletes one, and deleting the active one leaves these screens running nothing", function()
      ok("delete_arrangement", { arrangement = "single" })
      assert.is_nil(state().arrangements.single)
      local reply = ok("delete_arrangement", { arrangement = "dual" })
      assert.is_nil(reply.active)
      assert.is_nil(state().arrangement)
    end)
  end)

  describe("set_screens", function()
    it("renames a role, carrying its trees, and changes a selector", function()
      ok("set_screens", { arrangement = "dual", screens = { main = "Dell U2723QE ABC123", side = "HEADLESS-3" },
        renames = { big = "main" } })
      local s = state()
      assert.are.equal("dual", s.arrangement)
      assert.are.same({ main = "Dell U2723QE ABC123", side = "HEADLESS-3" }, s.arrangements.dual.screens)
      assert.are.equal("h[main:2, right]", tree_of(s, "dual", 3, "main"))
      assert.are.same({ main = "HEADLESS-2", side = "HEADLESS-3" }, s.screens)
    end)

    it("defaults to the active arrangement", function()
      ok("set_screens", { screens = { big = "HEADLESS-2", side = "SER-3" } })
      assert.are.equal("SER-3", state().arrangements.dual.screens.side)
    end)
  end)

  describe("set_pinned", function()
    it("sets the pinned screen roles", function()
      ok("set_pinned", { pinned = { "side" } })
      assert.are.same({ "side" }, state().pinned)
    end)

    it("refuses when config.lua does not take pinned from slots.lua", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements }
]])
      local reply = call("set_pinned", { pinned = { "side" } })
      assert.is_false(reply.ok)
      assert.matches("config.lua", reply.error)
      assert.are.same({}, state().pinned)
    end)

    it("refuses when config.lua sets pinned in code", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements, pinned = { "side" } }
]])
      assert.matches("config.lua", call("set_pinned", { pinned = {} }).error)
    end)
  end)

  describe("copy_trees", function()
    it("replaces an arrangement's trees with another's, roles mapped", function()
      ok("copy_trees", { arrangement = "single", from = "dual", roles = { big = "big" } })
      assert.are.equal("h[main:2, right]", tree_of(state(), "single", 3, "big"))
    end)

    it("from the default, puts each desk's slots side by side on the first screen", function()
      ok("copy_trees", { arrangement = "dual", default = true })
      local s = state()
      assert.are.equal("h[left, main, right]", tree_of(s, "dual", 3, "big"))
      assert.is_nil(tree_of(s, "dual", 3, "side"))
    end)

    it("needs a source", function()
      assert.matches("from", call("copy_trees", { arrangement = "dual" }).error)
    end)
  end)

  describe("edits on a config with no data file", function()
    it("are refused", function()
      setup(engine.TWO_SCREENS, [[
return { slots = { main = {} }, specs = { [3] = { main = "t-main" } }, arrangements = {} }
]])
      for _, name in ipairs({ "set_spec", "clear_spec", "add_slot", "rename_slot", "remove_slot", "describe_slot",
        "add_arrangement", "set_pinned" }) do
        local reply = call(name, { desk = 3, slot = "main", spec = "x", to = "y", name = "n", screens = { a = "X" }, pinned = {} })
        assert.is_false(reply.ok, name)
        assert.matches("slots.lua", reply.error, nil, name)
      end
    end)
  end)
end)
