-- Test seam S2: the api calls the editor's Layout view adds (docs/design.md
-- §9): set_trees (every screen of a workspace at once, so a slot can move from one
-- screen to another) and reset (a branch back to what slots.lua says).

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local SLOTS = [[
return {
  slots = { a = {}, b = {}, c = {} },
  specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "h[a, b, c]" }, workspaces = { [3] = { [1] = "h[a:2, b]", [2] = "c" } } },
    single = { screens = 1, default = { [1] = "h[a, b, c]" }, workspaces = { [3] = { [1] = "h[a, b, c]" } } },
  },
}
]]

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]]

local function config_dir(files)
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  for name, content in pairs(files) do
    local file = assert(io.open(dir .. "/" .. name, "w"))
    file:write(content)
    file:close()
  end
  return dir
end

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local AREA = { x = 0, y = 0, w = 2400, h = 1350 }

describe("layout editing api", function()
  local hl, dir, hyprslots

  local function fresh_module()
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    return require("hyprslots")
  end

  local function setup(files)
    dir = config_dir(files or { ["config.lua"] = CONFIG, ["slots.lua"] = SLOTS })
    hyprslots = fresh_module()
    hyprslots.setup({ config_dir = dir })
  end

  local function call(name, args)
    local text = hyprslots.api.call(name, args and json.encode(args) or "{}")
    assert.is_string(text)
    return json.decode(text)
  end

  local function branch(layout, screen)
    return call("state").layouts[layout].workspaces["3"][tostring(screen)]
  end

  local function events()
    return hl.dispatched_of("event")
  end

  before_each(function()
    local big = hl_stub.monitor("HEADLESS-2", { focused = true })
    big.active_workspace = { id = 3, name = "3" }
    local side = hl_stub.monitor("HEADLESS-3", { id = 1, x = 2400 })
    side.active_workspace = { id = 13, name = "13" }
    hl = hl_stub.new({ monitors = { big, side } })
    _G.hl, _G.o = hl, hl_stub.omarchy({ ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 })
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    if dir then os.execute("rm -rf '" .. dir .. "'") end
    dir = nil
  end)

  describe("set_trees", function()
    it("moves a slot from one screen to another in one edit", function()
      setup()
      local reply = call("set_trees", { workspace = 3, trees = { ["1"] = "h[a:2, b, c]", ["2"] = "b" } })
      -- b cannot be on both screens, so the two trees go in together or not at all
      assert.is_false(reply.ok)
      assert.matches("both", reply.error)
      assert.are.equal("h[a:2, b]", branch("dual", 1).tree)

      reply = call("set_trees", { workspace = 3, trees = { ["1"] = "h[a:2, b, c]", ["2"] = "*" } })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("dual", reply.layout)
      assert.are.equal(3, reply.workspace)
      assert.are.same({ ["1"] = { tree = "h[a:2, b, c]", ratio = "2:1:1" }, ["2"] = { tree = "*", ratio = "" } },
        reply.trees)
      assert.are.equal("h[a:2, b, c]", branch("dual", 1).tree)
      assert.are.equal("*", branch("dual", 2).tree)
      assert.is_true(call("state").dirty)
    end)

    it("announces the edit once", function()
      setup()
      call("set_trees", { workspace = 3, trees = { ["1"] = "h[a, b, c]", ["2"] = "*" } })
      assert.are.same({ "hyprslots changed 1" }, events())
    end)

    it("edits a layout that is not the active one", function()
      setup()
      local reply = call("set_trees", { layout = "single", workspace = 3, trees = { ["1"] = "v[c, b, a]" } })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("v[c, b, a]", branch("single", 1).tree)
      assert.are.equal("h[a:2, b]", branch("dual", 1).tree)
    end)

    it("refuses an empty set of trees and a screen the layout lacks", function()
      setup()
      assert.matches("no trees", call("set_trees", { workspace = 3, trees = {} }).error)
      assert.matches("layout 'dual' has screens 1 to 2, got 3", call("set_trees", { workspace = 3, trees = { ["3"] = "a" } }).error)
      assert.matches("got nope", call("set_trees", { workspace = 3, trees = { nope = "a" } }).error)
      assert.matches("trees", call("set_trees", { workspace = 3, trees = "h[a, b]" }).error)
    end)

    it("replaces the keyboard-resized trees it sets, and keeps them when it fails", function()
      setup()
      local windows = {}
      for i, class in ipairs({ "t-a", "t-b" }) do
        windows[i] = hl_stub.window(i, class, { workspace = 3 })
        hl.emit("window.open", windows[i])
      end
      hl.windows = windows
      hl.active_window = windows[1]
      assert.is_true(hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "nudge r 0.1"))
      local resized = branch("dual", 1).tree
      assert.is_true(branch("dual", 1).resized)

      assert.is_false(call("set_trees", { workspace = 3, trees = { ["1"] = "h[a, zzz]" } }).ok)
      assert.are.equal(resized, branch("dual", 1).tree)

      assert.is_true(call("set_trees", { workspace = 3, trees = { ["1"] = "v[a, b]" } }).ok)
      assert.are.equal("v[a, b]", branch("dual", 1).tree)
      assert.is_nil(branch("dual", 1).resized)
      assert.are.same({}, call("state").resized)
    end)
  end)

  describe("reset", function()
    it("puts a branch back to the tree slots.lua holds, dropping the edit", function()
      setup()
      call("set_tree", { workspace = 3, screen = 1, tree = "v[b, a]" })
      call("set_tree", { workspace = 3, screen = 2, tree = "h[c, *]" })
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.same("h[a:2, b]", reply.tree)
      assert.are.equal("2:1", reply.ratio)
      assert.are.equal("h[a:2, b]", branch("dual", 1).tree)
      -- the other screen keeps its edit, so there is still something unsaved
      assert.are.equal("h[c, *]", branch("dual", 2).tree)
      assert.is_true(call("state").dirty)

      call("reset", { workspace = 3, screen = 2 })
      assert.is_false(call("state").dirty, "nothing differs from slots.lua any more")
    end)

    it("drops a keyboard-resized tree", function()
      setup()
      local windows = {}
      for i, class in ipairs({ "t-a", "t-b" }) do
        windows[i] = hl_stub.window(i, class, { workspace = 3 })
        hl.emit("window.open", windows[i])
      end
      hl.windows = windows
      hl.active_window = windows[1]
      hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "nudge r 0.1")
      assert.is_true(call("state").dirty)

      assert.is_true(call("reset", { workspace = 3, screen = 1 }).ok)
      assert.are.equal("h[a:2, b]", branch("dual", 1).tree)
      assert.are.same({}, call("state").resized)
      assert.is_false(call("state").dirty)
    end)

    it("goes back to the file as saved, not as first loaded", function()
      setup()
      call("set_tree", { workspace = 3, screen = 1, tree = "v[a, b]" })
      call("save")
      call("set_tree", { workspace = 3, screen = 1, tree = "h[b, a]" })
      assert.is_true(call("reset", { workspace = 3, screen = 1 }).ok)
      assert.are.equal("v[a, b]", branch("dual", 1).tree)
      assert.is_false(call("state").dirty)
    end)

    it("removes a branch slots.lua does not have", function()
      setup()
      write(dir .. "/slots.lua", (SLOTS:gsub('%[1%] = "h%[a:2, b%]", %[2%] = "c"', '[1] = "h[a:2, b, c]"')))
      assert.is_true(call("reload").ok)
      call("set_trees", { workspace = 3, trees = { ["1"] = "h[a, b]", ["2"] = "c" } })
      assert.are.equal("c", branch("dual", 2).tree)

      assert.is_true(call("reset", { workspace = 3, screen = 2 }).ok)
      assert.is_nil(branch("dual", 2))
      assert.matches("c", call("reset", { workspace = 3, screen = 1 }).tree)
      assert.is_false(call("state").dirty)
    end)

    it("refuses what the editor may not change, and a broken slots.lua", function()
      setup({
        ["config.lua"] = [[
local data = load_data("slots.lua")
local layouts = { dual = data.layouts.dual, single = data.layouts.single,
  work = { screens = 1, workspaces = { [3] = { [1] = "a" } } } }
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = layouts }
]],
        ["slots.lua"] = SLOTS,
      })
      assert.matches("layout 'work' is set by code in your config", call("reset", { layout = "work", workspace = 3, screen = 1 }).error)
      assert.matches("layout 'dual' has screens 1 to 2, got 3", call("reset", { workspace = 3, screen = 3 }).error)

      write(dir .. "/slots.lua", "return {")
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_false(reply.ok)
      assert.matches("slots.lua", reply.error)
    end)

    it("announces the reset", function()
      setup()
      call("set_tree", { workspace = 3, screen = 1, tree = "v[a, b]" })
      call("reset", { workspace = 3, screen = 1 })
      assert.are.same({ "hyprslots changed 1", "hyprslots changed 2" }, events())
    end)
  end)

  -- The Slots and Desk view rename what the Layout view's calls
  -- name: set_trees targets the renamed layout, and reset reads the tree
  -- slots.lua holds through the renames, copies and removals made since.
  -- The cutover's trees: each workspace a copy of the shared tree cut down
  -- to its slots, and workspace 3 a real override (b twice as wide).
  local FOLDING = [[
return {
  slots = { a = {}, b = {}, c = {} },
  specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" }, [5] = { a = "t-a" } },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "h[a, b, c]" }, workspaces = {
      [3] = { [1] = "h[a, b:2, c]" },
      [4] = { [1] = "h[a, b, c]" },
      [5] = { [1] = "h[a:2, b:2, c:2]" },
    } },
    single = { screens = 1, default = { [1] = "v[a, b, c]" }, workspaces = { [3] = { [1] = "h[a, b, c]" } } },
  },
}
]]

  describe("fold_trees", function()
    it("drops the workspaces' trees the shared ones lay out the same, keeping the real overrides", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      local reply = call("fold_trees", {})
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("dual", reply.layout)
      assert.are.same({ 4, 5 }, reply.folded)
      assert.are.same({ { workspace = 3, reason = "screen 1's tree is not the shared one with slots left out" } },
        reply.kept)
      local s = call("state")
      assert.are.same({ 3 }, s.layouts.dual.own)
      assert.are.equal("h[a, b, c]", s.layouts.dual.workspaces["4"]["1"].tree, "workspace 4 shows the shared tree")
      assert.are.equal("h[a, b:2, c]", s.layouts.dual.workspaces["3"]["1"].tree)
      assert.is_true(s.dirty)
      assert.are.same({ "hyprslots changed 1" }, events())

      assert.is_true(call("save").ok)
      local saved = read(dir .. "/slots.lua")
      assert.is_nil(saved:find('"h[a:2, b:2, c:2]"', 1, true), "slots.lua no longer has workspace 5's copy")
      assert.matches('[1] = "h[a, b:2, c]"', saved, 1, true)
    end)

    it("folds the layout named, and changes nothing when there is nothing to fold", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      local reply = call("fold_trees", { layout = "single" })
      assert.is_true(reply.ok, reply.error)
      assert.are.same({}, reply.folded, "single's shared tree lays workspace 3 out otherwise")
      assert.are.same({ { workspace = 3, reason = "screen 1's tree is not the shared one with slots left out" } },
        reply.kept)
      assert.is_false(call("state").dirty)
      assert.are.same({}, events())
      assert.matches("no layout 'nope'", call("fold_trees", { layout = "nope" }).error)
    end)
  end)

  describe("a keyboard-resized tree", function()
    it("keeps a keyboard-resized tree holding every slot when a slot is added or removed", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      local windows = {}
      for i, class in ipairs({ "t-a", "t-b" }) do
        windows[i] = hl_stub.window(i, class, { workspace = 3 })
        hl.emit("window.open", windows[i])
      end
      hl.windows = windows
      hl.active_window = windows[1]
      assert.is_true(hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "nudge r 0.1"))
      local nudged = branch("dual", 1).tree
      assert.is_true(call("add_slot", { slot = "d" }).ok)
      assert.are.equal(nudged:sub(1, -2) .. ", d]", branch("dual", 1).tree, "the nudge kept, the new slot in it")
      assert.is_true(branch("dual", 1).resized)
      assert.is_true(call("remove_slot", { slot = "d" }).ok)
      assert.are.equal(nudged, branch("dual", 1).tree)
    end)
  end)

  describe("drop_override", function()
    it("sends a workspace back to the shared trees", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      local reply = call("drop_override", { workspace = 3 })
      assert.is_true(reply.ok, reply.error)
      assert.are.same({ layout = "dual", workspace = 3, own = false, seq = 1, ok = true }, reply)
      local s = call("state")
      assert.are.same({ 4, 5 }, s.layouts.dual.own)
      assert.are.equal("h[a, b, c]", s.layouts.dual.workspaces["3"]["1"].tree)
      assert.is_true(s.dirty)
    end)

    it("drops a keyboard-resized tree of the workspace with it", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      local windows = {}
      for i, class in ipairs({ "t-a", "t-b" }) do
        windows[i] = hl_stub.window(i, class, { workspace = 3 })
        hl.emit("window.open", windows[i])
      end
      hl.windows = windows
      hl.active_window = windows[1]
      assert.is_true(hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "nudge r 0.1"))
      assert.is_true(call("drop_override", { workspace = 3 }).ok)
      assert.are.same({}, call("state").resized)
      assert.are.equal("h[a, b, c]", branch("dual", 1).tree)
    end)

    it("refuses a workspace on the shared trees already", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = FOLDING })
      assert.matches("workspace 6 uses the shared trees already", call("drop_override", { workspace = 6 }).error)
      assert.is_false(call("state").dirty)
    end)
  end)

  describe("after slot and layout edits", function()
    it("reset after rename_slot puts the saved tree back under the slot's new name", function()
      setup()
      call("set_tree", { workspace = 3, screen = 1, tree = "v[b, a]" })
      assert.is_true(call("rename_slot", { slot = "a", to = "x" }).ok)
      assert.are.equal("v[b, x]", branch("dual", 1).tree)

      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[x:2, b]", reply.tree)
      assert.are.equal("h[x:2, b]", branch("dual", 1).tree)
      assert.is_true(call("state").dirty, "the rename is still unsaved")
    end)

    it("follows a slot renamed twice, and one renamed after a save only from there", function()
      setup()
      call("rename_slot", { slot = "a", to = "x" })
      call("rename_slot", { slot = "x", to = "y" })
      assert.are.equal("h[y:2, b]", call("reset", { workspace = 3, screen = 1 }).tree)

      call("save")
      call("rename_slot", { slot = "y", to = "z" })
      call("set_tree", { workspace = 3, screen = 1, tree = "v[b, z]" })
      assert.are.equal("h[z:2, b]", call("reset", { workspace = 3, screen = 1 }).tree)
    end)

    it("reset after remove_slot leaves the removed slot out", function()
      setup()
      assert.is_true(call("remove_slot", { slot = "b", force = true }).ok)
      call("set_tree", { workspace = 3, screen = 1, tree = "v[a, *]" })
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("a", reply.tree)
    end)

    it("reset after rename_layout finds the tree saved under the old name", function()
      setup()
      assert.is_true(call("rename_layout", { layout = "dual", to = "duo" }).ok)
      call("set_tree", { layout = "duo", workspace = 3, screen = 1, tree = "v[b, a]" })
      local reply = call("reset", { layout = "duo", workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a:2, b]", reply.tree)
      assert.are.equal("h[a:2, b]", branch("duo", 1).tree)
      assert.is_nil(call("state").layouts.dual)
      assert.are.equal("duo", call("state").desks.dual.layout)
      assert.is_true(call("state").dirty, "the rename is still unsaved")
    end)

    it("reset after fork_layout finds the tree saved under the layout it was copied from", function()
      setup()
      assert.is_true(call("fork_layout", { to = "dual-2" }).ok)
      call("set_tree", { workspace = 3, screen = 1, tree = "v[b, a]" })
      assert.are.equal("v[b, a]", branch("dual-2", 1).tree)
      assert.are.equal("h[a:2, b]", branch("dual", 1).tree, "the source keeps its tree")
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("dual-2", reply.layout)
      assert.are.equal("h[a:2, b]", reply.tree)
      assert.are.equal("c", branch("dual-2", 2).tree)
    end)

    it("reset in a layout added since the save takes its own tree away: the shared one shows", function()
      setup()
      assert.is_true(call("add_layout", { name = "wide", screens = 2 }).ok)
      call("set_tree", { layout = "wide", workspace = 3, screen = 1, tree = "h[a, b]" })
      local reply = call("reset", { layout = "wide", workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      local wide = call("state").layouts.wide
      assert.are.equal(wide.default["1"].tree, reply.tree)
      assert.are.same({}, wide.own, "workspace 3 has no tree of its own any more")
      assert.are.equal(wide.default["1"].tree, wide.workspaces["3"]["1"].tree, "it shows the shared tree")
    end)

    it("forgets the edits once they are reloaded away", function()
      setup()
      call("rename_slot", { slot = "a", to = "x" })
      assert.is_true(call("reload").ok)
      call("set_tree", { workspace = 3, screen = 1, tree = "v[b, a]" })
      assert.are.equal("h[a:2, b]", call("reset", { workspace = 3, screen = 1 }).tree)
      assert.is_false(call("state").dirty)
    end)

    it("set_trees after rename_layout edits the renamed one and replaces its resized tree", function()
      setup()
      local windows = {}
      for i, class in ipairs({ "t-a", "t-b" }) do
        windows[i] = hl_stub.window(i, class, { workspace = 3 })
        hl.emit("window.open", windows[i])
      end
      hl.windows = windows
      hl.active_window = windows[1]
      assert.is_true(hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "nudge r 0.1"))
      assert.is_true(call("rename_layout", { layout = "dual", to = "duo" }).ok)
      assert.is_true(branch("duo", 1).resized, "the resized tree moved with the rename")

      local reply = call("set_trees", { layout = "duo", workspace = 3, trees = { ["1"] = "v[a, b, c]", ["2"] = "*" } })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("duo", reply.layout)
      assert.are.equal("v[a, b, c]", branch("duo", 1).tree)
      assert.is_nil(branch("duo", 1).resized)
      assert.are.same({}, call("state").resized)

      assert.is_true(call("save").ok)
      local saved = read(dir .. "/slots.lua")
      assert.matches('duo = {', saved, 1, true)
      assert.matches('[1] = "v[a, b, c]"', saved, 1, true)
      assert.matches('layout = "duo"', saved, 1, true)
      assert.is_nil(saved:find('layout = "dual"', 1, true))
    end)
  end)
end)
