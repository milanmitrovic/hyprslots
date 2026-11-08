-- Test seam S2: the editor's api (docs/design.md §9) against a stubbed hl.
--
--   state, set_tree, set_ratio, record, save, reload
--   + hl.dsp.event("hyprslots changed <seq>") after every change

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local SLOTS = [[
return {
  slots = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a:1, b:2, c:1]" } },
    },
  },
}
]]

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements }
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
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

local AREA = { x = 0, y = 0, w = 2400, h = 1350 }

describe("hyprslots editor api", function()
  local hl, o, dir, hyprslots

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
    return hyprslots
  end

  local function call(name, args)
    local text = hyprslots.api.call(name, args and json.encode(args) or "{}")
    assert.is_string(text)
    assert.are_not.equal("", text)
    return json.decode(text)
  end

  local function state()
    return call("state")
  end

  -- The "hyprslots changed <seq>" events dispatched so far.
  local function events()
    local out = {}
    for _, d in ipairs(hl.dispatched_of("event")) do
      out[#out + 1] = d
    end
    return out
  end

  local function recalculate(windows, area)
    local ctx = hl_stub.layout_ctx(area or AREA, windows)
    hl.layouts.slots.recalculate(ctx)
    return hl_stub.placed_by_class(ctx)
  end

  -- Windows on workspace 3, already laid out by the slots layout, with their
  -- boxes recorded the way Hyprland reports them (at / size).
  local function laid_out_windows(classes)
    local windows = {}
    for i, class in ipairs(classes) do
      windows[i] = hl_stub.window(i, class, { workspace = 3 })
    end
    hl.windows = windows
    for _, window in ipairs(windows) do
      hl.emit("window.open", window)
    end
    local placed = recalculate(windows)
    for _, window in ipairs(windows) do
      local box = placed[window.class]
      window.at = { x = box.x, y = box.y }
      window.size = { x = box.w, y = box.h }
    end
    return windows
  end

  before_each(function()
    local monitor = hl_stub.monitor("HEADLESS-2", { focused = true })
    monitor.active_workspace = { id = 3, name = "3" }
    hl = hl_stub.new({ monitors = { monitor } })
    o = hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
    _G.hl, _G.o = hl, o
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    if dir then os.execute("rm -rf '" .. dir .. "'") end
    dir = nil
  end)

  describe("state", function()
    it("reports the arrangements with their trees and ratios", function()
      setup()
      local s = state()
      assert.are.equal("solo", s.arrangement)
      local solo = s.arrangements.solo
      assert.are.same({ main = "HEADLESS-2" }, solo.screens)
      assert.are.same({ tree = "h[a, b:2, c]", ratio = "1:2:1", slots = { "a", "b", "c" } }, solo.desks["3"].main)
      assert.is_true(solo.active)
      assert.is_false(solo.read_only)
    end)

    it("reports the global slots, and each desk's specs", function()
      setup()
      assert.are.same({ { name = "a" }, { name = "b" }, { name = "c" } }, state().slots)
      assert.are.same({ ["3"] = { a = "t-a", b = "t-b", c = "t-c" } }, state().specs)
    end)

    it("lists the desks", function()
      setup()
      assert.are.same({ 3 }, state().desks)
    end)

    it("reports live windows with their assignments and boxes", function()
      setup()
      laid_out_windows({ "t-a", "firefox" })
      local windows = state().windows
      assert.are.equal(2, #windows)
      local by_class = {}
      for _, w in ipairs(windows) do by_class[w.class] = w end
      assert.are.equal(3, by_class["t-a"].workspace)
      assert.are.equal(3, by_class["t-a"].desk)
      assert.are.equal("a", by_class["t-a"].slot)
      assert.are.same({ x = 0, y = 0, w = 1800, h = 1350 }, by_class["t-a"].box)
      assert.is_nil(by_class["firefox"].slot)
    end)

    it("reports fields config.lua sets in code as read-only", function()
      setup({
        ["config.lua"] = [[
local data = load_data("slots.lua")
local arrangements = { solo = data.arrangements.solo, work = { screens = { big = "DP-1" } } }
return { slots = data.slots, specs = data.specs, arrangements = arrangements, pinned = { "big" } }
]],
        ["slots.lua"] = SLOTS,
      })
      local s = state()
      assert.are.same({ "arrangements.work", "pinned" }, s.config.read_only)
      assert.is_true(s.arrangements.work.read_only)
      assert.is_false(s.arrangements.solo.read_only)
    end)

    it("starts clean, at seq 0", function()
      setup()
      local s = state()
      assert.is_false(s.dirty)
      assert.are.equal(0, s.seq)
      assert.are.equal(dir .. "/slots.lua", s.config.data_file)
    end)
  end)

  describe("set_tree", function()
    it("changes the tree in memory and lays the workspace out anew", function()
      setup()
      local windows = laid_out_windows({ "t-a", "t-b", "t-c" })
      local reply = call("set_tree", { desk = 3, role = "main", tree = "v[a, b, c]" })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("v[a, b, c]", reply.tree)
      assert.are.equal("v[a, b, c]", state().arrangements.solo.desks["3"].main.tree)
      assert.is_true(state().dirty)

      local placed = recalculate(windows)
      assert.are.same({ x = 0, y = 450, w = 2400, h = 450 }, placed["t-b"])
      assert.is_true(#hl.dispatched_of("window.resize") >= 1, "a nudge makes Hyprland recalculate")
    end)

    it("defaults to the active arrangement but takes another", function()
      setup()
      local reply = call("set_tree", { arrangement = "nope", desk = 3, role = "main", tree = "a" })
      assert.is_false(reply.ok)
      assert.matches("nope", reply.error)
    end)

    it("refuses a tree the config would reject, changing nothing", function()
      setup()
      local reply = call("set_tree", { desk = 3, role = "main", tree = "h[a, zzz]" })
      assert.is_false(reply.ok)
      assert.matches("zzz", reply.error)
      assert.are.equal("h[a, b:2, c]", state().arrangements.solo.desks["3"].main.tree)
      assert.is_false(state().dirty)
    end)

    it("refuses to change an arrangement config.lua builds in code", function()
      setup({
        ["config.lua"] = [[
local data = load_data("slots.lua")
local arrangements = { solo = { screens = data.arrangements.solo.screens, desks = { [3] = { main = "a" } } } }
return { slots = data.slots, specs = data.specs, arrangements = arrangements }
]],
        ["slots.lua"] = SLOTS,
      })
      local reply = call("set_tree", { desk = 3, role = "main", tree = "h[a, b]" })
      assert.is_false(reply.ok)
      assert.matches("config.lua", reply.error)
    end)

    it("announces the change with a custom event", function()
      setup()
      call("set_tree", { desk = 3, role = "main", tree = "v[a, b, c]" })
      assert.are.same({ "hyprslots changed 1" }, events())
      assert.are.equal(1, state().seq)
    end)
  end)

  describe("set_ratio", function()
    it("applies the ratio grammar to the current tree", function()
      setup()
      local reply = call("set_ratio", { desk = 3, role = "main", ratio = "3:1:1" })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a:3, b, c]", reply.tree)
      assert.are.equal("3:1:1", reply.ratio)
      assert.are.same({ "hyprslots changed 1" }, events())
    end)

    it("reports a ratio that does not fit the tree", function()
      setup()
      local reply = call("set_ratio", { desk = 3, role = "main", ratio = "1:1" })
      assert.is_false(reply.ok)
      assert.matches("expected 3 values", reply.error)
      assert.are.same({}, events())
    end)

    it("reports a desk the arrangement has no tree for", function()
      setup()
      local reply = call("set_ratio", { desk = 4, role = "main", ratio = "1:1" })
      assert.is_false(reply.ok)
      assert.matches("desk 4", reply.error)
    end)
  end)

  describe("record", function()
    it("turns the focused workspace's windows back into the same tree", function()
      setup()
      laid_out_windows({ "t-a", "t-b", "t-c" })
      local reply = call("record")
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a, b:2, c]", reply.tree)
      assert.are.same({ arrangement = "solo", desk = 3, role = "main" },
        { arrangement = reply.arrangement, desk = reply.desk, role = reply.role })
      assert.is_true(reply.applied)
    end)

    it("records what the windows show after a hand-made change", function()
      setup()
      local windows = laid_out_windows({ "t-a", "t-b", "t-c" })
      -- Columns of 800 + 800 + 800 px, as if resized by hand.
      for i, window in ipairs(windows) do
        local index = ({ ["t-a"] = 0, ["t-b"] = 1, ["t-c"] = 2 })[window.class]
        window.at = { x = index * 800, y = 0 }
        window.size = { x = 800, y = 1350 }
        windows[i] = window
      end
      local before = #events()
      local reply = call("record")
      assert.are.equal("h[a, b, c]", reply.tree)
      assert.are.equal("h[a, b, c]", state().arrangements.solo.desks["3"].main.tree)
      assert.are.equal(before + 1, #events())
      assert.are.equal("hyprslots changed " .. reply.seq, events()[#events()])
    end)

    it("does not apply a record that would drop a slot with no window", function()
      setup()
      laid_out_windows({ "t-a", "t-b" })
      local reply = call("record")
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a, b:2]", reply.tree)
      assert.is_false(reply.applied)
      assert.are.same({ "c" }, reply.missing)
      assert.are.equal("h[a, b:2, c]", state().arrangements.solo.desks["3"].main.tree)
    end)

    it("applies it anyway when asked to", function()
      setup()
      laid_out_windows({ "t-a", "t-b" })
      local reply = call("record", { apply = true })
      assert.is_true(reply.applied)
      assert.are.equal("h[a, b:2]", state().arrangements.solo.desks["3"].main.tree)
    end)

    it("previews without applying when asked to", function()
      setup()
      local windows = laid_out_windows({ "t-a", "t-b", "t-c" })
      windows[1].size = { x = 300, y = 1350 }
      local reply = call("record", { apply = false })
      assert.is_false(reply.applied)
      assert.is_false(state().dirty)
    end)

    it("refuses a workspace that is no desk of the arrangement", function()
      setup()
      local reply = call("record", { workspace = 7 })
      assert.is_false(reply.ok)
      assert.matches("workspace 7", reply.error)
    end)

    it("does not apply a record over a tree with an overflow leaf", function()
      setup()
      laid_out_windows({ "t-a", "t-b", "t-c" })
      local api_module = require("hyprslots.api")
      local original = api_module.effective_branch
      api_module.effective_branch = function()
        return { split = "h", weight = 1, children = {
          { slot = "a", weight = 1 }, { slot = "b", weight = 2 }, { slot = "c", weight = 1 }, { overflow = true, weight = 1 } } }
      end
      local reply = call("record")
      api_module.effective_branch = original
      assert.is_true(reply.ok, reply.error)
      assert.is_false(reply.applied)
      assert.are.same({ "*" }, reply.missing)
    end)

    it("refuses overlapping windows", function()
      setup()
      local windows = laid_out_windows({ "t-a", "t-b" })
      for _, window in ipairs(windows) do
        window.at = { x = 0, y = 0 }
        window.size = { x = 2400, y = 1350 }
      end
      local reply = call("record")
      assert.is_false(reply.ok)
      assert.matches("overlap", reply.error)
    end)
  end)

  describe("keyboard-resized trees", function()
    -- A nudge (resize.lua) holds its tree in memory; it is the tree in force
    -- for state, set_ratio, record and save until it is saved or dropped.
    local windows

    -- Focus t-a and nudge its right edge by 0.1 of the split:
    -- h[a:1, b:2, c:1] becomes h[a:7, b:8, c:5] (600 + 240 px for a).
    local function nudge_a()
      hl.active_window = windows[1]
      local ctx = hl_stub.layout_ctx(AREA, windows)
      assert.is_true(hl.layouts.slots.layout_msg(ctx, "nudge r 0.1"))
    end

    before_each(function()
      setup()
      windows = laid_out_windows({ "t-a", "t-b", "t-c" })
      nudge_a()
    end)

    it("is what state reports, as an unsaved override", function()
      local s = state()
      assert.are.equal("h[a:7, b:8, c:5]", s.arrangements.solo.desks["3"].main.tree)
      assert.is_true(s.arrangements.solo.desks["3"].main.resized)
      assert.are.same({ ["solo/3/main"] = { arrangement = "solo", desk = 3, role = "main",
        tree = "h[a:7, b:8, c:5]", ratio = "7:8:5" } }, s.resized)
      assert.is_true(s.dirty)
    end)

    it("is what the layout places", function()
      local placed = recalculate(windows)
      assert.are.same({ x = 0, y = 0, w = 840, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 840, y = 0, w = 960, h = 1350 }, placed["t-b"])
    end)

    it("announces itself with a change event", function()
      -- Three window opens, then the nudge.
      assert.are.same({ "hyprslots changed 1", "hyprslots changed 2", "hyprslots changed 3",
        "hyprslots changed 4" }, events())
      assert.are.equal(4, state().seq)
    end)

    it("is what set_ratio starts from, and set_ratio replaces it", function()
      local reply = call("set_ratio", { desk = 3, role = "main", ratio = "7:8:10" })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a:7, b:8, c:10]", reply.tree)
      assert.are.same({}, state().resized)
      assert.are.same({ x = 0, y = 0, w = 672, h = 1350 }, recalculate(windows)["t-a"])
    end)

    it("is what record compares against", function()
      for _, window in ipairs(windows) do
        local box = recalculate(windows)[window.class]
        window.at, window.size = { x = box.x, y = box.y }, { x = box.w, y = box.h }
      end
      local reply = call("record", { apply = false })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a:7, b:8, c:5]", reply.tree)
      assert.are.same({}, reply.missing)
    end)

    it("is written by save, which then holds it as the config and clears the override", function()
      local reply = call("save")
      assert.is_true(reply.ok, reply.error)
      assert.matches('main = "h%[a:7, b:8, c:5%]"', read(dir .. "/slots.lua"))
      local s = state()
      assert.are.same({}, s.resized)
      assert.is_false(s.dirty)
      assert.are.equal("h[a:7, b:8, c:5]", s.arrangements.solo.desks["3"].main.tree)
      assert.is_nil(s.arrangements.solo.desks["3"].main.resized)
      assert.are.same({ x = 0, y = 0, w = 840, h = 1350 }, recalculate(windows)["t-a"])
      -- A reset now has nothing to go back to: the saved tree is the config.
      hl.active_window = windows[1]
      hl.layouts.slots.layout_msg(hl_stub.layout_ctx(AREA, windows), "reset")
      assert.are.same({ x = 0, y = 0, w = 840, h = 1350 }, recalculate(windows)["t-a"])
    end)

    it("survives a reload once saved", function()
      call("save")
      assert.is_true(call("reload").ok)
      assert.are.equal("h[a:7, b:8, c:5]", state().arrangements.solo.desks["3"].main.tree)
      assert.are.same({ x = 0, y = 0, w = 840, h = 1350 }, recalculate(windows)["t-a"])
    end)

    it("is dropped by a reload without a save", function()
      assert.is_true(call("reload").ok)
      local s = state()
      assert.are.same({}, s.resized)
      assert.is_false(s.dirty)
      assert.are.equal("h[a, b:2, c]", s.arrangements.solo.desks["3"].main.tree)
      assert.are.same({ x = 0, y = 0, w = 600, h = 1350 }, recalculate(windows)["t-a"])
    end)
  end)

  describe("save", function()
    it("writes slots.lua atomically, and a reload reads the same layout", function()
      setup()
      call("set_ratio", { desk = 3, role = "main", ratio = "1:1:2" })
      local reply = call("save")
      assert.is_true(reply.ok, reply.error)
      assert.are.equal(dir .. "/slots.lua", reply.path)
      assert.matches("editor", read(dir .. "/slots.lua"))
      assert.is_false(state().dirty)

      -- A fresh engine (a Hyprland config reload) reads the saved file.
      hyprslots = fresh_module()
      hyprslots.setup({ config_dir = dir })
      assert.are.equal("h[a, b, c:2]", state().arrangements.solo.desks["3"].main.tree)
    end)

    it("refuses when there is no data file to save", function()
      setup({ ["config.lua"] = "return { slots = {}, arrangements = {} }" })
      local reply = call("save")
      assert.is_false(reply.ok)
      assert.matches("slots.lua", reply.error)
    end)

    it("announces the save", function()
      setup()
      call("save")
      assert.are.same({ "hyprslots changed 1" }, events())
    end)
  end)

  describe("reload", function()
    it("re-reads the files, dropping unsaved edits", function()
      setup()
      call("set_ratio", { desk = 3, role = "main", ratio = "5:1:1" })
      local reply = call("reload")
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a, b:2, c]", state().arrangements.solo.desks["3"].main.tree)
      assert.is_false(state().dirty)
    end)

    it("picks up a slots.lua changed on disk", function()
      setup()
      local file = assert(io.open(dir .. "/slots.lua", "w"))
      file:write((SLOTS:gsub("h%[a:1, b:2, c:1%]", "v[a, b, c]")))
      file:close()
      assert.is_true(hyprslots.reload_config())
      assert.are.equal("v[a, b, c]", state().arrangements.solo.desks["3"].main.tree)
    end)

    it("keeps the running config when the files are broken", function()
      setup()
      local file = assert(io.open(dir .. "/slots.lua", "w"))
      file:write("return {")
      file:close()
      local reply = call("reload")
      assert.is_false(reply.ok)
      assert.are.equal("solo", state().arrangement)
      assert.are.equal("h[a, b:2, c]", state().arrangements.solo.desks["3"].main.tree)
    end)

    it("announces the reload", function()
      setup()
      call("reload")
      assert.are.same({ "hyprslots changed 1" }, events())
    end)
  end)

  describe("change events", function()
    it("follow windows opening and closing", function()
      setup()
      local window = hl_stub.window(1, "t-a", { workspace = 3 })
      hl.emit("window.open", window)
      hl.emit("window.destroy", window)
      assert.are.same({ "hyprslots changed 1", "hyprslots changed 2" }, events())
    end)

    it("follow an arrangement change on hotplug", function()
      setup()
      hl.monitors = {}
      hl.emit("monitor.removed", {})
      hl.run_timers()
      assert.are.same({ "hyprslots changed 1" }, events())
    end)
  end)

  describe("replies", function()
    it("never come back empty, even for a failing call", function()
      setup()
      for _, name in ipairs({ "set_tree", "set_ratio", "record", "save", "reload", "state", "bogus" }) do
        local text = hyprslots.api.call(name, "{}")
        assert.is_string(text)
        assert.is_truthy(json.decode(text), name)
      end
    end)

    it("take well under the repl's 250 ms budget", function()
      setup()
      laid_out_windows({ "t-a", "t-b", "t-c" })
      for _, name in ipairs({ "state", "set_ratio", "record", "save", "reload" }) do
        local started = os.clock()
        call(name, name == "set_ratio" and { desk = 3, role = "main", ratio = "1:2:1" } or nil)
        assert.is_true(os.clock() - started < 0.05, name .. " took too long")
      end
    end)
  end)
end)
