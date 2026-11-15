-- Test seam S2: the engine records the active desk's geometry (its
-- monitors' logical boxes) in slots.lua (docs/design.md §8), quietly: saved
-- at once while nothing else is unsaved, else with the next save; and the
-- api reports every desk's map for the editor's Desk tab (§9).

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

local function load_text(text)
  return assert(load(text, "slots.lua", "t", {}))()
end

describe("desk geometry", function()
  local hl, hyprslots, big, side

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

  local function saved()
    return load_text(read(state().config.data_file))
  end

  local function events()
    return #hl.dispatched_of("event")
  end

  -- dual: HEADLESS-2 (2400x1350 at 0, 0) and HEADLESS-3 (a 4K panel at
  -- scale 2, 1920x1080 logical, at 2400, 135); single: HEADLESS-2.
  local function setup(slots, config)
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    big, side = hl.monitors[1], hl.monitors[2]
    big.width, big.height, big.scale, big.transform = 2400, 1350, 1, 0
    side.width, side.height, side.scale, side.transform = 3840, 2160, 2, 0
    side.x, side.y = 2400, 135
    hl_stub.simulate(hl)
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    hyprslots = engine.setup(slots or engine.TWO_SCREENS, config)
  end

  local DUAL = {
    ["HEADLESS-2"] = { x = 0, y = 0, w = 2400, h = 1350 },
    ["HEADLESS-3"] = { x = 2400, y = 135, w = 1920, h = 1080 },
  }

  after_each(engine.cleanup)

  describe("with the desks in slots.lua", function()
    local SLOTS = [[
return {
  slots = { left = { key = "l" }, main = { key = "m" }, right = { key = "r" } },
  specs = { [3] = { left = "t-left", main = "t-main", right = "t-right" } },
  desks = {
    dual = { monitors = { "HEADLESS-3", "HEADLESS-2" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "h[left, main, right]" },
      workspaces = { [3] = { [1] = "h[main:2, right:1]", [2] = "left" } } },
    single = { screens = 1, default = { [1] = "h[left, main, right]" } },
  },
}
]]

    before_each(function() setup(SLOTS) end)

    it("records the active desk's monitors' logical boxes into slots.lua, quietly, while nothing else is unsaved",
      function()
        hl.run_timers()
        assert.are.same(DUAL, saved().desks.dual.geometry)
        assert.is_nil(saved().desks.single.geometry, "a desk not seen has none")
        assert.is_false(state().dirty)
        assert.are.same({}, hl.notifications)
      end)

    it("does nothing more while the geometry stays the same", function()
      hl.run_timers()
      local text, before = read(state().config.data_file), events()
      hl.emit("monitor.layout_changed")
      hl.run_timers()
      assert.are.equal(text, read(state().config.data_file))
      assert.are.equal(before, events())
    end)

    it("loads back from slots.lua as it was written: clean, nothing written again", function()
      hl.run_timers()
      local text = read(state().config.data_file)
      ok("reload")
      hl.run_timers()
      assert.is_false(state().dirty)
      assert.are.equal(text, read(state().config.data_file))
    end)

    it("goes with the next save when other edits are unsaved, and leaves dirty as it was", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      hl.run_timers()
      assert.is_nil(saved().desks.dual.geometry, "not saved over the pending edit")
      assert.is_true(state().dirty)
      ok("save")
      local data = saved()
      assert.are.same(DUAL, data.desks.dual.geometry)
      assert.are.equal("the editor", data.slots.main.description)
      assert.is_false(state().dirty)
    end)

    it("is kept through an edit made after it was folded in", function()
      ok("describe_slot", { slot = "main", description = "the editor" })
      hl.run_timers()
      ok("set_spec", { workspace = 4, slot = "main", spec = "kitty" })
      ok("save")
      assert.are.same(DUAL, saved().desks.dual.geometry)
    end)

    it("waits for a keyboard-resized tree's save too", function()
      local main = hl_stub.window(1, "t-main", { workspace = hl.get_workspace(3) })
      local right = hl_stub.window(2, "t-right", { workspace = hl.get_workspace(3) })
      for _, window in ipairs({ main, right }) do
        hl.windows[#hl.windows + 1] = window
        hl.emit("window.open", window)
      end
      hl.active_window = main
      assert.is_true(hl.layouts.slots.layout_msg(hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { main, right }),
        "nudge r 0.1"))
      assert.is_not_nil(next(state().resized))
      hl.run_timers()
      assert.is_nil(saved().desks.dual.geometry)
    end)

    it("is recorded again when a monitor's mode changes", function()
      hl.run_timers()
      side.scale = 1.5
      hl.emit("monitor.layout_changed")
      hl.run_timers()
      assert.are.same({ x = 2400, y = 135, w = 2560, h = 1440 }, saved().desks.dual.geometry["HEADLESS-3"])
      assert.is_false(state().dirty)
    end)

    it("is recorded for the desk that is active after a hotplug, the other desk's kept", function()
      hl.run_timers()
      hl.monitors = { big }
      hl.get_workspace(13).monitor = big
      hl.emit("monitor.removed", side)
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("single", state().desk)
      local data = saved()
      assert.are.same({ ["HEADLESS-2"] = { x = 0, y = 0, w = 2400, h = 1350 } }, data.desks.single.geometry)
      assert.are.same(DUAL, data.desks.dual.geometry)
    end)

    it("survives a desk's rename", function()
      hl.run_timers()
      ok("rename_desk", { desk = "dual", to = "home" })
      ok("save")
      assert.are.same(DUAL, saved().desks.home.geometry)
    end)

    it("is not dirty again once a reset brings the trees back to the file", function()
      ok("set_tree", { layout = "dual", workspace = 3, screen = 1, tree = "h[main, right]" })
      hl.run_timers()
      assert.is_nil(saved().desks.dual.geometry)
      ok("reset", { layout = "dual", workspace = 3, screen = 1 })
      hl.run_timers()
      assert.is_false(state().dirty)
      assert.are.same(DUAL, saved().desks.dual.geometry, "saved once nothing else was unsaved")
    end)

    describe("in state, every desk's map", function()
      it("is the live boxes for the active desk, its screens numbered as the layout's", function()
        local desks = state().desks
        assert.are.same({
          { x = 2400, y = 135, w = 1920, h = 1080, screen = 2 },
          { x = 0, y = 0, w = 2400, h = 1350, screen = 1 },
        }, desks.dual.geometry, "one per monitor the desk lists, in its order")
        assert.are.same({ "HEADLESS-2", "HEADLESS-3" }, desks.dual.screens)
      end)

      it("is the recorded boxes for a desk not connected, else equal boxes side by side", function()
        hl.run_timers()
        hl.monitors = { big }
        hl.get_workspace(13).monitor = big
        hl.emit("monitor.removed", side)
        hl.run_timers()
        hl.run_timers()
        local desks = state().desks
        assert.are.same({
          { x = 2400, y = 135, w = 1920, h = 1080, screen = 2 },
          { x = 0, y = 0, w = 2400, h = 1350, screen = 1 },
        }, desks.dual.geometry, "recorded while it was active")
        assert.are.same({ false, true }, desks.dual.connected)
        ok("add_desk", { name = "office", monitors = { "DP-7", "DP-8" }, layout = "dual" })
        assert.are.same({
          { x = 0, y = 0, w = 1600, h = 900, screen = 1 },
          { x = 1600, y = 0, w = 1600, h = 900, screen = 2 },
        }, state().desks.office.geometry, "never seen")
      end)
    end)
  end)

  describe("where config.lua builds the desks in code", function()
    it("records nothing and saves nothing, the active desk's map still live", function()
      setup(nil, [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, layouts = data.layouts,
  desks = { dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" } } }
]])
      local text = read(state().config.data_file)
      hl.run_timers()
      assert.are.equal(text, read(state().config.data_file))
      assert.is_false(state().dirty)
      assert.are.equal(2, #state().desks.dual.geometry)
      assert.are.equal(2400, state().desks.dual.geometry[1].w)
    end)
  end)
end)
