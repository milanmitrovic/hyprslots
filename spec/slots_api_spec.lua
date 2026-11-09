-- Test seam S2: what the editor's Slots and Desk view need from
-- the api (docs/design.md §9): global slot edits (add, remove, rename across
-- every tree and workspace, describe), per-workspace specs (set, clear, take a
-- window's spec, the Assignment view's a), desk edits (add, rename, delete,
-- apply a layout) and layout edits (add, fork, rename,
-- delete). Every edit stays in memory until save, re-runs config.lua, and
-- re-routes.

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

describe("the Slots and Desk view' api", function()
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

  local function tree_of(s, layout, workspace, screen)
    local branch = s.layouts[layout].workspaces[tostring(workspace)]
    return branch and branch[tostring(screen)] and branch[tostring(screen)].tree
  end

  local function setup(slots, config)
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl.monitors[1].description = "Dell U2723QE ABC123"
    hl.monitors[2].serial = "SER-3"
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    -- dual: screen 1 "h[main:2, right:1]", screen 2 "left"; single: screen 1 "h[left, main, right]"
    hyprslots = engine.setup(slots or engine.TWO_SCREENS, config)
  end

  before_each(function() setup() end)
  after_each(engine.cleanup)

  describe("state", function()
    it("lists the connected monitors with what selects each", function()
      assert.are.same({
        { name = "HEADLESS-2", description = "Dell U2723QE ABC123", serial = "", focused = true, x = 0, y = 0,
          internal = false, selector = "Dell U2723QE ABC123" },
        { name = "HEADLESS-3", description = "", serial = "SER-3", focused = false, x = 2400, y = 0,
          internal = false, selector = "SER-3" },
      }, state().monitors)
    end)

    it("lists the global slots with their descriptions, and each workspace's specs", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      local s = state()
      assert.are.same({ { name = "left" }, { name = "main", description = "the editor" }, { name = "right" } }, s.slots)
      assert.are.same({ ["3"] = { left = "t-left", main = "t-main", right = "t-right" } }, s.specs)
      assert.is_nil(s.descriptions)
    end)
  end)

  describe("add_slot", function()
    it("defines a global slot, with its description, that every workspace's trees may then place", function()
      local reply = ok("add_slot", { slot = "chat", description = "team chat" })
      assert.are.equal("chat", reply.slot)
      local s = state()
      assert.are.same({ name = "chat", description = "team chat" }, s.slots[1])
      assert.is_true(s.dirty)
      ok("set_tree", { layout = "single", workspace = 5, screen = 1, tree = "chat" })
    end)

    it("refuses a taken or malformed name", function()
      assert.matches("there is a slot 'main' already", call("add_slot", { slot = "main" }).error)
      assert.matches("slot name", call("add_slot", { slot = "a b" }).error)
    end)

    it("refuses a slot list config.lua builds in code", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
local slots = { left = {}, main = {}, right = {}, extra = {} }
return { slots = slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]])
      local reply = call("add_slot", { slot = "chat" })
      assert.is_false(reply.ok)
      assert.matches("slots are set by code in your config", reply.error)
    end)
  end)

  describe("remove_slot", function()
    it("refuses a slot that workspaces have specs for, saying which", function()
      local reply = call("remove_slot", { slot = "right" })
      assert.is_false(reply.ok)
      assert.matches("slot 'right' is filled on workspace 3", reply.error)
      assert.matches("force", reply.error)
      assert.are.equal(3, #state().slots)
    end)

    it("with force, takes it out of every tree of every workspace and every workspace's specs", function()
      local right = open(1, "t-right", 1)
      local reply = ok("remove_slot", { slot = "right", force = true })
      assert.are.same({ "dual/3/1", "single/3/1" }, reply.trees)
      assert.are.same({ 3 }, reply.specs)
      local s = state()
      assert.are.same({ { name = "left" }, { name = "main" } }, s.slots)
      assert.is_nil(s.specs["3"].right)
      assert.are.equal("main", tree_of(s, "dual", 3, 1))
      assert.are.equal("h[left, main]", tree_of(s, "single", 3, 1))
      assert.is_nil(s.assignments[right.address])
    end)

    it("removes a slot no workspace fills without force, though every tree holds it", function()
      ok("add_slot", { slot = "chat" })
      ok("remove_slot", { slot = "chat" })
      assert.are.equal(3, #state().slots)
    end)
  end)

  describe("rename_slot", function()
    it("renames a slot everywhere: every tree, every workspace's spec, its description", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      ok("set_spec", { workspace = 5, slot = "main", spec = "kitty" })
      local reply = ok("rename_slot", { slot = "main", to = "editor" })
      assert.are.equal("editor", reply.to)
      assert.are.equal(2, reply.trees)
      assert.are.same({ 3, 5 }, reply.specs)
      local s = state()
      assert.are.same({ name = "editor", description = "the editor" }, s.slots[1])
      assert.are.equal("t-main", s.specs["3"].editor)
      assert.are.equal("kitty", s.specs["5"].editor)
      assert.is_nil(s.specs["3"].main)
      assert.are.equal("h[editor:2, right]", tree_of(s, "dual", 3, 1))
      assert.are.equal("h[left, editor, right]", tree_of(s, "single", 3, 1))
    end)

    it("keeps the window in its slot, a hand-made assignment too", function()
      local main = open(1, "t-main", 1)
      local stranger = open(2, "firefox", 1)
      ok("assign", { address = stranger.address, workspace = 3, slot = "right" })
      ok("rename_slot", { slot = "main", to = "editor" })
      ok("rename_slot", { slot = "right", to = "aside" })
      local s = state()
      assert.are.same({ workspace = 3, slot = "editor" }, s.assignments[main.address])
      assert.are.same({ workspace = 3, slot = "aside", manual = true }, s.assignments[stranger.address])
    end)

    it("carries a keyboard-resized tree along", function()
      local main = open(1, "t-main", 3)
      local right = open(2, "t-right", 3)
      hl.active_window = main
      local ctx = hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { main, right })
      assert.is_true(hl.layouts.slots.layout_msg(ctx, "nudge r 0.1"))
      local nudged = state().resized["dual/3/1"].tree
      assert.matches("^h%[main:%d+, right:%d+%]$", nudged)
      ok("rename_slot", { slot = "main", to = "editor" })
      local s = state()
      local expected = (nudged:gsub("main", "editor"))
      assert.are.equal(expected, s.resized["dual/3/1"].tree)
      assert.are.equal(expected, tree_of(s, "dual", 3, 1))
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
      assert.matches('%[1%] = "h%[editor:2, right%]"', saved)
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
    it("sets the app that fills a global slot on a workspace, in memory, and the window it names takes the slot", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      local reply = ok("set_spec", { workspace = 3, slot = "main", spec = " kitty/deltaf " })
      assert.are.same({ workspace = 3, slot = "main", spec = "kitty/deltaf" }, { workspace = reply.workspace, slot = reply.slot, spec = reply.spec })
      local s = state()
      assert.are.equal("kitty/deltaf", s.specs["3"].main)
      assert.is_true(s.dirty)
      assert.are.same({ workspace = 3, slot = "main" }, s.assignments[editor.address])
      assert.are.equal(3, editor.workspace.id)
    end)

    it("gives a workspace with no specs its first, for a global slot", function()
      ok("set_spec", { workspace = 7, slot = "main", spec = "spotify" })
      assert.are.same({ main = "spotify" }, state().specs["7"])
      assert.are.same({ 3, 7 }, state().used_workspaces)
    end)

    it("refuses a spec the grammar rejects, or a slot that is not defined, changing nothing", function()
      local seq = state().seq
      local reply = call("set_spec", { workspace = 3, slot = "main", spec = "[Tag" })
      assert.is_false(reply.ok)
      assert.matches("closing ']'", reply.error)
      assert.matches("no slot 'zz'", call("set_spec", { workspace = 3, slot = "zz", spec = "x" }).error)
      assert.are.equal("t-main", state().specs["3"].main)
      assert.are.equal(seq, state().seq)
    end)

    it("announces the change", function()
      local seq = state().seq
      ok("set_spec", { workspace = 3, slot = "main", spec = "foo" })
      local events = hl.dispatched_of("event")
      assert.are.equal("hyprslots changed " .. state().seq, events[#events])
      assert.is_true(state().seq > seq)
    end)

    it("refuses a workspace whose specs config.lua builds in code", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
local specs = { [3] = data.specs[3], [4] = { main = "thunderbird" } }
return { slots = data.slots, specs = specs, desks = data.desks, layouts = data.layouts }
]])
      local reply = call("set_spec", { workspace = 4, slot = "main", spec = "x" })
      assert.is_false(reply.ok)
      assert.matches("workspace 4's specs are set by code in your config", reply.error)
    end)
  end)

  describe("clear_spec", function()
    it("drops a workspace's spec for a slot: its window leaves the slot, the slot stays", function()
      local right = open(1, "t-right", 1)
      assert.are.same({ workspace = 3, slot = "right" }, state().assignments[right.address])
      local reply = ok("clear_spec", { workspace = 3, slot = "right" })
      assert.are.same({ 3, "right" }, { reply.workspace, reply.slot })
      local s = state()
      assert.is_nil(s.specs["3"].right)
      assert.are.equal(3, #s.slots)
      assert.is_nil(s.assignments[right.address])
      assert.are.equal("h[main:2, right]", tree_of(s, "dual", 3, 1))
    end)

    it("refuses a workspace with no spec for the slot", function()
      assert.matches("workspace 4 has no spec for 'main'", call("clear_spec", { workspace = 4, slot = "main" }).error)
    end)
  end)

  describe("take_spec (the Assignment view's a)", function()
    it("writes the window's spec into the workspace's slot and puts the window there", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { workspace = 3, slot = "right", address = editor.address })
      assert.are.equal("kitty/deltaf", reply.spec)
      assert.are.equal("t-right", reply.replaced)
      local s = state()
      assert.are.equal("kitty/deltaf", s.specs["3"].right)
      assert.are.same({ workspace = 3, slot = "right" }, s.assignments[editor.address], "a spec assignment, not by hand")
      assert.are.equal(3, editor.workspace.id)
      assert.is_true(s.dirty)
    end)

    it("gives the slot to that window over an older one the new spec also matches", function()
      local older = open(1, "kitty", 1, "deltaf | logs")
      local chosen = open(2, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { workspace = 5, slot = "main", address = chosen.address })
      assert.are.equal("kitty/deltaf", reply.spec)
      local s = state()
      assert.are.same({ workspace = 5, slot = "main" }, s.assignments[chosen.address])
      assert.is_nil(s.assignments[older.address])
    end)

    it("displaces the window that held the slot", function()
      local right = open(1, "t-right", 1)
      local editor = open(2, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { workspace = 3, slot = "right", address = editor.address })
      assert.are.equal(right.address, reply.displaced)
      assert.is_nil(state().assignments[right.address])
    end)

    it("refuses a window that is not open, or a slot that is not defined, changing nothing", function()
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      assert.are.equal("no open window 0xdead", call("take_spec", { workspace = 3, slot = "right", address = "0xdead" }).error)
      assert.matches("no slot 'zz'", call("take_spec", { workspace = 3, slot = "zz", address = editor.address }).error)
      assert.is_nil(state().assignments[editor.address])
      assert.is_false(state().dirty)
    end)
  end)

  describe("a new slot (every tree holds every slot)", function()
    it("goes into every tree at once, at the end, and take_spec just assigns it", function()
      ok("add_slot", { slot = "chat" })
      local s = state()
      assert.are.equal("h[main:2, right, chat]", tree_of(s, "dual", 3, 1), "the left-most screen's tree")
      assert.are.equal("left", tree_of(s, "dual", 3, 2))
      assert.are.equal("h[left, main, right, chat]", tree_of(s, "single", 3, 1))
      local editor = open(1, "kitty", 1, "deltaf | nvim")
      local reply = ok("take_spec", { workspace = 3, slot = "chat", address = editor.address })
      assert.is_nil(reply.placed)
      assert.are.same({ workspace = 3, slot = "chat" }, state().assignments[editor.address])
      ok("save")
      assert.matches('"h%[main:2, right, chat%]"', read(state().config.data_file))
    end)
  end)

  describe("add_desk", function()
    it("adds a desk for monitor selectors, using a layout for as many screens", function()
      local reply = ok("add_desk", { name = "office", monitors = { "DP-1", "DP-2" }, layout = "dual" })
      assert.are.same({ ok = true, desk = "office", monitors = { "DP-1", "DP-2" }, layout = "dual", active = "dual",
        seq = state().seq }, reply)
      local s = state()
      assert.are.same({ monitors = { "DP-1", "DP-2" }, connected = { false, false }, layout = "dual",
        active = false, read_only = false }, s.desks.office)
      assert.are.same({ "dual", "office" }, s.layouts.dual.used_by)
      assert.are.equal("dual", s.desk)
      assert.is_true(s.dirty)
    end)

    it("selects monitors by description, serial or connector, and runs a desk that sorts first for them", function()
      local reply = ok("add_desk", { name = "aaa", monitors = { "SER-3", "Dell U2723QE ABC123" }, layout = "dual" })
      assert.are.equal("aaa", reply.active)
      local s = state()
      assert.are.equal("aaa", s.desk)
      assert.are.equal("dual", s.layout)
      assert.are.same({ true, true }, s.desks.aaa.connected)
      assert.are.same({ "HEADLESS-2", "HEADLESS-3" }, s.desks.aaa.screens, "screens left to right, not in list order")
      assert.is_false(s.desks.dual.active)
    end)

    it("refuses a taken name, no monitors, and a layout for another number of screens", function()
      assert.matches("a desk called 'dual' already exists",
        call("add_desk", { name = "dual", monitors = { "DP-1" }, layout = "single" }).error)
      assert.matches("at least one monitor", call("add_desk", { name = "x", monitors = {}, layout = "single" }).error)
      assert.matches("'DP-1' is listed twice",
        call("add_desk", { name = "x", monitors = { "DP-1", "DP-1" }, layout = "dual" }).error, 1, true)
      assert.matches("layout 'dual' is for 2 screens, and the desk has 1 monitor",
        call("add_desk", { name = "x", monitors = { "DP-1" }, layout = "dual" }).error)
      assert.matches("no layout 'nope'", call("add_desk", { name = "x", monitors = { "DP-1" }, layout = "nope" }).error)
      assert.is_false(state().dirty)
    end)
  end)

  describe("rename_desk", function()
    it("renames it; the active one stays active under its new name", function()
      local reply = ok("rename_desk", { desk = "dual", to = "office" })
      assert.are.same({ "dual", "office", "office" }, { reply.desk, reply.to, reply.active })
      local s = state()
      assert.are.equal("office", s.desk)
      assert.is_nil(s.desks.dual)
      assert.are.equal("dual", s.desks.office.layout, "the layout keeps its name")
      assert.are.same({ "office" }, s.layouts.dual.used_by)
    end)

    it("needs the desk named, and refuses a taken name", function()
      assert.matches("name the desk", call("rename_desk", { to = "x" }).error)
      assert.matches("a desk called 'single' already exists", call("rename_desk", { desk = "dual", to = "single" }).error)
      assert.matches("no desk 'nope'", call("rename_desk", { desk = "nope", to = "x" }).error)
    end)
  end)

  describe("delete_desk", function()
    it("deletes one; the active one's monitors get a new desk after a second", function()
      ok("delete_desk", { desk = "single" })
      assert.is_nil(state().desks.single)
      local reply = ok("delete_desk", { desk = "dual" })
      assert.is_nil(reply.active)
      assert.is_nil(state().desk)
      assert.are.same({}, state().layouts.dual.used_by, "the layout stays")
      hl.run_timers()
      local s = state()
      assert.are.equal("abc123+headless-3", s.desk)
      assert.are.equal("dual", s.layout, "the 2-screen layout used last")
      assert.is_true(s.desks[s.desk].auto)
    end)

    it("needs the desk named", function()
      assert.matches("name the desk", call("delete_desk", {}).error)
    end)
  end)

  describe("apply_layout", function()
    it("points the active desk at another layout for as many screens", function()
      ok("add_layout", { name = "wide", screens = 2 })
      ok("set_tree", { layout = "wide", workspace = 3, screen = 2, tree = "h[left, main, right]" })
      local main = open(1, "t-main", 1)
      assert.are.equal(3, main.workspace.id)
      local reply = ok("apply_layout", { layout = "wide" })
      assert.are.same({ "dual", "wide", "dual" }, { reply.desk, reply.layout, reply.active })
      local s = state()
      assert.are.equal("wide", s.layout)
      assert.are.equal("wide", s.desks.dual.layout)
      assert.are.same({ "dual" }, s.layouts.wide.used_by)
      assert.are.same({}, s.layouts.dual.used_by)
      assert.is_true(s.layouts.wide.active)
      assert.is_false(s.layouts.dual.active)
      assert.are.equal(13, main.workspace.id, "re-routed to the screen that now holds its slot")
    end)

    it("takes another desk, and refuses a layout for another number of screens", function()
      ok("add_layout", { name = "one", screens = 1 })
      assert.are.equal("dual", ok("apply_layout", { desk = "single", layout = "one" }).active)
      assert.are.equal("one", state().desks.single.layout)
      assert.matches("layout 'single' is for 1 screen, and the desk has 2 monitors",
        call("apply_layout", { layout = "single" }).error)
      assert.matches("no layout 'nope'", call("apply_layout", { layout = "nope" }).error)
    end)
  end)

  describe("a desk config.lua builds in code", function()
    it("is read only", function()
      setup(engine.TWO_SCREENS, [[
local data = load_data("slots.lua")
local desks = { dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" }, single = data.desks.single }
return { slots = data.slots, specs = data.specs, desks = desks, layouts = data.layouts }
]])
      assert.are.same({ "desks.dual" }, state().config.read_only)
      assert.is_true(state().desks.dual.read_only)
      assert.is_false(state().desks.single.read_only)
      assert.matches("desk 'dual' is set by code", call("rename_desk", { desk = "dual", to = "x" }).error)
    end)
  end)

  describe("pinned screens (gone)", function()
    it("are no call and no state", function()
      assert.matches("unknown", call("set_pinned", { pinned = { 2 } }).error)
      assert.is_nil(state().pinned)
      assert.is_nil(state().desks.dual.pinned)
    end)

    it("are dropped from slots.lua without a word, the engine dirty until saved", function()
      setup((engine.TWO_SCREENS:gsub('layout = "dual" }', 'layout = "dual", pinned = { 2 } }', 1)))
      local s = state()
      assert.is_nil(s.config_error)
      assert.is_nil(s.desks.dual.pinned)
      assert.is_true(s.dirty)
      ok("save")
      assert.is_nil(read(s.config.data_file):find("pinned", 1, true))
      assert.is_false(state().dirty)
    end)
  end)

  describe("add_layout", function()
    it("adds an empty layout for a number of screens", function()
      local reply = ok("add_layout", { name = "wide", screens = 2 })
      assert.are.same({ "wide", 2 }, { reply.layout, reply.screens })
      assert.are.same({ screens = 2, default = {}, workspaces = {}, own = {}, used_by = {}, active = false,
        read_only = false }, state().layouts.wide)
      assert.is_true(state().dirty)
    end)

    it("with default: true, gives it the default trees, which every workspace then shows", function()
      ok("add_layout", { name = "home", screens = 2, default = true })
      local home = state().layouts.home
      assert.are.equal("h[left, main, right]", home.default["1"].tree)
      assert.is_nil(home.default["2"])
      assert.are.same({}, home.own)
      for n = 1, 10 do
        assert.are.equal("h[left, main, right]", home.workspaces[tostring(n)]["1"].tree, n)
      end
      ok("add_layout", { name = "trio", screens = 3, default = true })
      assert.are.equal("h[left, main, right]", state().layouts.trio.default["1"].tree)
    end)

    it("refuses a taken name, a bad name and a number of screens out of range", function()
      assert.matches("a layout called 'dual' already exists", call("add_layout", { name = "dual", screens = 2 }).error)
      assert.matches("no '/'", call("add_layout", { name = "a/b", screens = 2 }).error)
      assert.matches("a layout is for 1 to 10 screens, got 0", call("add_layout", { name = "x", screens = 0 }).error)
      assert.matches("got 11", call("add_layout", { name = "x", screens = 11 }).error)
    end)
  end)

  describe("a layout's default trees", function()
    before_each(function()
      ok("add_layout", { name = "home", screens = 2, default = true })
      ok("apply_layout", { layout = "home" })
    end)

    it("set_tree on a workspace that shows them gives it its own copy; the others keep the default", function()
      local reply = ok("set_tree", { workspace = 5, screen = 2, tree = "*" })
      assert.are.same({ "home", 5, 2, "*" }, { reply.layout, reply.workspace, reply.screen, reply.tree })
      local home = state().layouts.home
      assert.are.same({ 5 }, home.own)
      assert.are.equal("h[left, main, right]", home.workspaces["5"]["1"].tree, "copied from the default")
      assert.are.equal("*", home.workspaces["5"]["2"].tree)
      assert.is_nil(home.workspaces["4"]["2"])
      assert.are.equal("h[left, main, right]", home.workspaces["4"]["1"].tree)
      assert.is_nil(home.default["2"])
    end)

    it("set_tree on \"default\" changes them for every workspace with none of its own", function()
      ok("set_tree", { workspace = 4, screen = 1, tree = "h[main, right]" })
      local reply = ok("set_tree", { workspace = "default", screen = 1, tree = "v[left, main, right]" })
      assert.are.equal("default", reply.workspace)
      local home = state().layouts.home
      assert.are.equal("v[left, main, right]", home.default["1"].tree)
      assert.are.equal("v[left, main, right]", home.workspaces["3"]["1"].tree)
      assert.are.equal("h[main, right, left]", home.workspaces["4"]["1"].tree, "its own trees replace the default ones")
      assert.are.same({ 4 }, home.own)
    end)

    it("are written by save as default", function()
      local path = ok("save").path
      local saved = assert(loadfile(path, "t", {}))()
      assert.are.same({ screens = 2, default = { [1] = "h[left, main, right]" } }, saved.layouts.home)
      assert.are.equal("home", saved.desks.dual.layout)
      assert.matches('%[1%] = "h%[left, main, right%]"', read(path))
    end)
  end)

  describe("two desks sharing one layout", function()
    it("see one edit: the layout lists both, and a tree set on the active desk's is the other's too", function()
      ok("add_desk", { name = "office", monitors = { "DP-1", "DP-2" }, layout = "dual" })
      ok("set_tree", { workspace = 3, screen = 1, tree = "h[right, main]" })
      local s = state()
      assert.are.same({ "dual", "office" }, s.layouts.dual.used_by)
      assert.are.equal("dual", s.desks.office.layout)
      assert.are.equal("h[right, main]", tree_of(s, s.desks.office.layout, 3, 1))
    end)

    it("the other desk runs the edited layout when its monitors are the connected ones", function()
      ok("add_desk", { name = "office", monitors = { "HEADLESS-3" }, layout = "single" })
      ok("set_tree", { layout = "single", workspace = 3, screen = 1, tree = "v[left, main, right]" })
      local gone = hl.monitors[1]
      hl.monitors = { hl.monitors[2] }
      hl.emit("monitor.removed", gone)
      hl.run_timers()
      local s = state()
      assert.are.equal("office", s.desk)
      assert.are.equal("single", s.layout)
      assert.are.same({ "HEADLESS-3" }, s.screens)
      assert.are.equal("v[left, main, right]", tree_of(s, "single", 3, 1))
      assert.are.same({ workspace = 3, screen = 1, monitor = "HEADLESS-3", layout = "lua:slots" }, s.workspaces["13"])
    end)
  end)

  describe("fork_layout", function()
    it("copies the active desk's layout and points the desk at the copy", function()
      local reply = ok("fork_layout", { to = "dual-2" })
      assert.are.same({ "dual", "dual-2", "dual", "dual-2" }, { reply.layout, reply.to, reply.desk, reply.active })
      local s = state()
      assert.are.equal("dual-2", s.layout)
      assert.are.equal("h[main:2, right]", tree_of(s, "dual-2", 3, 1))
      assert.are.equal("left", tree_of(s, "dual-2", 3, 2))
      assert.are.same({ "dual" }, s.layouts["dual-2"].used_by)
      assert.are.same({}, s.layouts.dual.used_by)
    end)

    it("copies the unsaved keyboard-resized trees too", function()
      local main = open(1, "t-main", 3)
      local right = open(2, "t-right", 3)
      hl.active_window = main
      local ctx = hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { main, right })
      assert.is_true(hl.layouts.slots.layout_msg(ctx, "nudge r 0.1"))
      local nudged = state().resized["dual/3/1"].tree
      assert.are_not.equal("h[main:2, right]", nudged)
      ok("fork_layout", { to = "dual-2" })
      local s = state()
      assert.are.same({ layout = "dual-2", workspace = 3, screen = 1, tree = nudged,
        ratio = s.resized["dual/3/1"].ratio }, s.resized["dual-2/3/1"])
      assert.are.equal(nudged, tree_of(s, "dual-2", 3, 1))
      assert.is_true(s.layouts["dual-2"].workspaces["3"]["1"].resized)
      local placed = hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { main, right })
      hl.layouts.slots.recalculate(placed)
      assert.are_not.equal(1600, hl_stub.placed_by_class(placed)["t-main"].w, "the copy runs the resized tree")

      local saved = read(ok("save").path)
      assert.matches('%["dual%-2"%] = {', saved)
      assert.are.same({}, state().resized)
      assert.are.equal(nudged, tree_of(state(), "dual-2", 3, 1))
    end)

    it("leaves a desk with another number of monitors on its layout", function()
      local reply = ok("fork_layout", { layout = "single", to = "single-2" })
      assert.is_nil(reply.desk)
      assert.are.equal("dual", reply.active)
      assert.are.equal("h[left, main, right]", tree_of(state(), "single-2", 3, 1))
      assert.are.equal("single", state().desks.single.layout)
      reply = ok("fork_layout", { layout = "single", to = "single-3", desk = "single" })
      assert.are.equal("single", reply.desk)
      assert.are.equal("single-3", state().desks.single.layout)
    end)

    it("refuses a desk named for it whose monitor count the layout does not fit", function()
      local reply = call("fork_layout", { layout = "single", to = "single-2", desk = "dual" })
      assert.matches("desk 'dual' has 2 monitors, and layout 'single' is for 1 screen", reply.error)
      assert.is_nil(state().layouts["single-2"])
    end)

    it("refuses a taken name", function()
      assert.matches("a layout called 'single' already exists", call("fork_layout", { to = "single" }).error)
      assert.are.equal("dual", state().layout)
    end)
  end)

  describe("rename_layout", function()
    it("renames it; the desks using it follow", function()
      local reply = ok("rename_layout", { layout = "dual", to = "duo" })
      assert.are.same({ "dual", "duo", "duo" }, { reply.layout, reply.to, reply.active })
      local s = state()
      assert.are.equal("duo", s.layout)
      assert.are.equal("dual", s.desk)
      assert.are.equal("duo", s.desks.dual.layout)
      assert.is_nil(s.layouts.dual)
      assert.are.equal("h[main:2, right]", tree_of(s, "duo", 3, 1))
    end)

    it("needs the layout named, and refuses a taken name", function()
      assert.matches("name the layout", call("rename_layout", { to = "x" }).error)
      assert.matches("a layout called 'single' already exists", call("rename_layout", { layout = "dual", to = "single" }).error)
    end)
  end)

  describe("delete_layout", function()
    it("is refused while desks use it", function()
      local reply = call("delete_layout", { layout = "dual" })
      assert.is_false(reply.ok)
      assert.matches("layout 'dual' is used by desk dual; delete it with remap: <another layout for 2 screens>", reply.error,
        1, true)
      assert.is_truthy(state().layouts.dual)
    end)

    it("with remap, the desks that used it use that one", function()
      ok("add_layout", { name = "wide", screens = 2 })
      local reply = ok("delete_layout", { layout = "dual", remap = "wide" })
      assert.are.same({ "dual", "wide", { "dual" }, "wide" }, { reply.layout, reply.remap, reply.desks, reply.active })
      local s = state()
      assert.is_nil(s.layouts.dual)
      assert.are.equal("wide", s.desks.dual.layout)
      assert.are.equal("wide", s.layout)
    end)

    it("refuses a remap for another number of screens, or to itself", function()
      assert.matches("layout 'single' is for 1 screen, and 'dual' for 2 screens",
        call("delete_layout", { layout = "dual", remap = "single" }).error)
      assert.matches("to itself", call("delete_layout", { layout = "dual", remap = "dual" }).error)
    end)

    it("deletes an unused one without remap, and its keyboard-resized trees with it", function()
      ok("add_layout", { name = "spare", screens = 1 })
      local reply = ok("delete_layout", { layout = "spare" })
      assert.are.same({}, reply.desks)
      assert.is_nil(state().layouts.spare)
      assert.matches("name the layout", call("delete_layout", {}).error)
    end)
  end)

  describe("edits on a config with no data file", function()
    it("are refused", function()
      setup(engine.TWO_SCREENS, [[
return { slots = { main = {} }, specs = { [3] = { main = "t-main" } }, desks = {}, layouts = {} }
]])
      for _, name in ipairs({ "set_spec", "clear_spec", "add_slot", "rename_slot", "remove_slot", "describe_slot",
        "add_desk", "add_layout" }) do
        local reply = call(name, { workspace = 3, slot = "main", spec = "x", to = "y", name = "n", monitors = { "X" },
          layout = "x", screens = 1 })
        assert.is_false(reply.ok, name)
        assert.matches("loads no editor data", reply.error, nil, name)
      end
    end)
  end)
end)
