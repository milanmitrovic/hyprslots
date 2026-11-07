-- Test seam S2: the api calls the editor's Layout view adds (docs/design.md
-- §9): set_trees (every screen of a desk at once, so a slot can move from one
-- screen to another) and reset (a branch back to what slots.lua says).

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local SLOTS = [[
return {
  slots = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = { [3] = { big = "h[a:2, b]", side = "c" } },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "h[a, b, c]" } },
    },
  },
}
]]

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, arrangements = data.arrangements }
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

  local function branch(arrangement, role)
    return call("state").arrangements[arrangement].desks["3"][role]
  end

  local function events()
    return hl.dispatched_of("event")
  end

  before_each(function()
    local big = hl_stub.monitor("HEADLESS-2", { focused = true })
    big.active_workspace = { id = 3, name = "3" }
    local side = hl_stub.monitor("HEADLESS-3", { id = 1 })
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
      local reply = call("set_trees", { desk = 3, trees = { big = "h[a:2, b, c]", side = "b" } })
      -- b cannot be on both screens, so the two trees go in together or not at all
      assert.is_false(reply.ok)
      assert.matches("both", reply.error)
      assert.are.equal("h[a:2, b]", branch("dual", "big").tree)

      reply = call("set_trees", { desk = 3, trees = { big = "h[a:2, b, c]", side = "*" } })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("dual", reply.arrangement)
      assert.are.equal(3, reply.desk)
      assert.are.same({ big = { tree = "h[a:2, b, c]", ratio = "2:1:1" }, side = { tree = "*", ratio = "" } },
        reply.trees)
      assert.are.equal("h[a:2, b, c]", branch("dual", "big").tree)
      assert.are.equal("*", branch("dual", "side").tree)
      assert.is_true(call("state").dirty)
    end)

    it("announces the edit once", function()
      setup()
      call("set_trees", { desk = 3, trees = { big = "h[a, b, c]", side = "*" } })
      assert.are.same({ "hyprslots changed 1" }, events())
    end)

    it("edits an arrangement that is not the active one", function()
      setup()
      local reply = call("set_trees", { arrangement = "single", desk = 3, trees = { big = "v[c, b, a]" } })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("v[c, b, a]", branch("single", "big").tree)
      assert.are.equal("h[a:2, b]", branch("dual", "big").tree)
    end)

    it("refuses an empty set of trees and a screen role the arrangement lacks", function()
      setup()
      assert.matches("no trees", call("set_trees", { desk = 3, trees = {} }).error)
      assert.matches("no screen role 'nope'", call("set_trees", { desk = 3, trees = { nope = "a" } }).error)
      assert.matches("trees", call("set_trees", { desk = 3, trees = "h[a, b]" }).error)
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
      local resized = branch("dual", "big").tree
      assert.is_true(branch("dual", "big").resized)

      assert.is_false(call("set_trees", { desk = 3, trees = { big = "h[a, zzz]" } }).ok)
      assert.are.equal(resized, branch("dual", "big").tree)

      assert.is_true(call("set_trees", { desk = 3, trees = { big = "v[a, b]" } }).ok)
      assert.are.equal("v[a, b]", branch("dual", "big").tree)
      assert.is_nil(branch("dual", "big").resized)
      assert.are.same({}, call("state").resized)
    end)
  end)

  describe("reset", function()
    it("puts a branch back to the tree slots.lua holds, dropping the edit", function()
      setup()
      call("set_tree", { desk = 3, role = "big", tree = "v[b, a]" })
      call("set_tree", { desk = 3, role = "side", tree = "h[c, *]" })
      local reply = call("reset", { desk = 3, role = "big" })
      assert.is_true(reply.ok, reply.error)
      assert.are.same("h[a:2, b]", reply.tree)
      assert.are.equal("2:1", reply.ratio)
      assert.are.equal("h[a:2, b]", branch("dual", "big").tree)
      -- the other screen keeps its edit, so there is still something unsaved
      assert.are.equal("h[c, *]", branch("dual", "side").tree)
      assert.is_true(call("state").dirty)

      call("reset", { desk = 3, role = "side" })
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

      assert.is_true(call("reset", { desk = 3, role = "big" }).ok)
      assert.are.equal("h[a:2, b]", branch("dual", "big").tree)
      assert.are.same({}, call("state").resized)
      assert.is_false(call("state").dirty)
    end)

    it("goes back to the file as saved, not as first loaded", function()
      setup()
      call("set_tree", { desk = 3, role = "big", tree = "v[a, b]" })
      call("save")
      call("set_tree", { desk = 3, role = "big", tree = "h[b, a]" })
      assert.is_true(call("reset", { desk = 3, role = "big" }).ok)
      assert.are.equal("v[a, b]", branch("dual", "big").tree)
      assert.is_false(call("state").dirty)
    end)

    it("removes a branch slots.lua does not have", function()
      setup()
      write(dir .. "/slots.lua", (SLOTS:gsub('big = "h%[a:2, b%]", side = "c"', 'big = "h[a:2, b, c]"')))
      assert.is_true(call("reload").ok)
      call("set_trees", { desk = 3, trees = { big = "h[a, b]", side = "c" } })
      assert.are.equal("c", branch("dual", "side").tree)

      assert.is_true(call("reset", { desk = 3, role = "side" }).ok)
      assert.is_nil(branch("dual", "side"))
      assert.matches("c", call("reset", { desk = 3, role = "big" }).tree)
      assert.is_false(call("state").dirty)
    end)

    it("refuses what the editor may not change, and a broken slots.lua", function()
      setup({
        ["config.lua"] = [[
local data = load_data("slots.lua")
local arrangements = { dual = data.arrangements.dual,
  work = { screens = { big = "DP-1" }, desks = { [3] = { big = "a" } } } }
return { slots = data.slots, arrangements = arrangements }
]],
        ["slots.lua"] = SLOTS,
      })
      assert.matches("config.lua", call("reset", { arrangement = "work", desk = 3, role = "big" }).error)
      assert.matches("no screen role", call("reset", { desk = 3, role = "nope" }).error)

      write(dir .. "/slots.lua", "return {")
      local reply = call("reset", { desk = 3, role = "big" })
      assert.is_false(reply.ok)
      assert.matches("slots.lua", reply.error)
    end)

    it("announces the reset", function()
      setup()
      call("set_tree", { desk = 3, role = "big", tree = "v[a, b]" })
      call("reset", { desk = 3, role = "big" })
      assert.are.same({ "hyprslots changed 1", "hyprslots changed 2" }, events())
    end)
  end)
end)
