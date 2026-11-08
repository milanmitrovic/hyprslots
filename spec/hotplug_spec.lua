-- Test seam S2: monitor hotplug re-selects the arrangement and re-routes every
-- assigned window to its slot's workspace (docs/design.md §8), after
-- Omarchy's own deferred reconcile.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

local PINNED_SIDE = engine.TWO_SCREENS:gsub("^return {", 'return {\n  pinned = { "side" },')

describe("hotplug", function()
  local hl, o, hyprslots, side

  local function window_on(id, class, workspace)
    local window = hl_stub.window(id, class, { workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.get_workspace(workspace).windows = hl.get_workspace(workspace).windows + 1
    return window
  end

  local function workspace_of(class)
    for _, window in ipairs(hl.windows) do
      if window.class == class then
        return window.workspace.id
      end
    end
  end

  -- Omarchy's monitor-workspaces loads before hyprslots, so its handler runs
  -- first: on removal it reconciles from a oneshot timer of its own, merging
  -- the unplugged screen's workspace 13 into big's block as workspace 4.
  local function omarchy_reconcile_on_removal()
    hl.on("monitor.removed", function()
      hl.timer(function()
        local workspace = hl.get_workspace(13)
        if workspace then
          workspace.id, workspace.name = 4, "4"
        end
      end, { type = "oneshot", timeout = 1 })
    end)
  end

  local function unplug_side()
    hl.monitors = { hl.monitors[1] }
    hl.get_workspace(13).monitor = hl.monitors[1]
    hl.emit("monitor.removed", side)
  end

  before_each(function()
    hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    side = hl.monitors[2]
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
  end)

  after_each(engine.cleanup)

  describe("when a screen is removed", function()
    before_each(function()
      omarchy_reconcile_on_removal()
      window_on(1, "t-left", 13)
      window_on(2, "t-main", 3)
      window_on(3, "t-right", 3)
      hyprslots = engine.setup(engine.TWO_SCREENS)
      assert.are.equal("dual", engine.state(hyprslots).arrangement)
    end)

    it("re-routes each window to its slot under the arrangement for what is left", function()
      unplug_side()
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("single", engine.state(hyprslots).arrangement)
      assert.are.equal(3, workspace_of("t-left"))
      assert.are.equal(3, workspace_of("t-main"))
      assert.are.equal(3, workspace_of("t-right"))
    end)

    it("re-routes only after Omarchy's reconcile timer from the same event has run", function()
      unplug_side()
      hl.run_timers()
      assert.are.same({}, hl.dispatched_of("window.move"), "not alongside Omarchy's timer")
      hl.run_timers()
      assert.are.same({ { workspace = "3", window = "address:0x1001", follow = false } },
        hl.dispatched_of("window.move"))
    end)

    it("changes no focus", function()
      unplug_side()
      hl.run_timers()
      hl.run_timers()
      assert.are.same({}, hl.dispatched_of("focus"))
      assert.are.same({}, o.workspaces.focused)
    end)
  end)

  describe("when a screen is added", function()
    before_each(function()
      hl.monitors = { hl.monitors[1] }
      window_on(1, "t-left", 3)
      window_on(2, "t-main", 3)
      hyprslots = engine.setup(engine.TWO_SCREENS)
      assert.are.equal("single", engine.state(hyprslots).arrangement)
    end)

    it("moves the slots of the new screen's branch onto its workspace there", function()
      hl.monitors[2] = side
      hl.emit("monitor.added", side)
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("dual", engine.state(hyprslots).arrangement)
      assert.are.equal(13, workspace_of("t-left"))
      assert.are.equal("HEADLESS-3", hl.get_workspace(13).monitor.name)
      assert.are.equal(3, workspace_of("t-main"))
      assert.are.equal(1, #hl.dispatched_of("window.move"), "t-main was already in place")
    end)

    local function plug_side()
      hl.monitors[2] = side
      hl.emit("monitor.added", side)
      hl.run_timers()
      hl.run_timers()
    end

    it("shows the active workspace on the screen that came back, keeping focus", function()
      engine.call(hyprslots, "workspace", '{"workspace": 3}')
      o.workspaces.focused = {}
      hl.dispatched = {}
      plug_side()
      assert.are.same({ { workspace = 3, monitor = "HEADLESS-3" } }, o.workspaces.focused)
      local focused = hl.dispatched_of("focus")
      assert.are.same({ monitor = "HEADLESS-2" }, focused[#focused])
    end)

    it("shows no workspace on the new screen before any workspace switch", function()
      plug_side()
      assert.are.same({}, o.workspaces.focused)
      assert.are.same({}, hl.dispatched_of("focus"))
    end)

    it("leaves windows with no slot alone", function()
      window_on(9, "firefox", 3)
      hl.monitors[2] = side
      hl.emit("monitor.added", side)
      hl.run_timers()
      hl.run_timers()
      assert.are.equal(3, workspace_of("firefox"))
    end)
  end)

  describe("with a pinned screen", function()
    it("leaves a pinned screen that came back on its own workspace", function()
      hl.monitors = { hl.monitors[1] }
      hyprslots = engine.setup(PINNED_SIDE)
      engine.call(hyprslots, "workspace", '{"workspace": 3}')
      o.workspaces.focused = {}
      hl.dispatched = {}
      hl.monitors[2] = side
      hl.emit("monitor.added", side)
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("dual", engine.state(hyprslots).arrangement)
      assert.are.same({}, o.workspaces.focused)
      assert.are.same({}, hl.dispatched_of("focus"))
    end)

    it("just re-selects when the pinned screen goes, refocusing nothing", function()
      omarchy_reconcile_on_removal()
      window_on(1, "t-left", 13)
      window_on(2, "t-main", 3)
      hyprslots = engine.setup(PINNED_SIDE)
      unplug_side()
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("single", engine.state(hyprslots).arrangement)
      assert.are.equal(3, workspace_of("t-left"))
      assert.are.same({}, hl.dispatched_of("focus"))
      assert.are.same({}, o.workspaces.focused)
    end)
  end)

  describe("with a scroll branch in the arrangement that is left", function()
    -- dual tiles x and y side by side on side; single puts main, x and y in
    -- scrolling columns on big, which only a scroll pass after the re-route
    -- can put in slot order.
    local SLOTS = [==[
return {
  slots = { [3] = { x = "t-x", y = "t-y", main = "t-main" } },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = { [3] = { side = "h[x, y]", big = "main" } },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "scroll[main, x, y]" } },
    },
  },
}
]==]

    local function drain()
      for _ = 1, 10 do
        hl.run_timers()
      end
    end

    local function index_of(name, args)
      for i, d in ipairs(hl.dispatched) do
        if type(d) == "table" and d.dsp == name and (args == nil or d.args.window == args) then
          return i
        end
      end
    end

    it("puts the columns in slot order after the windows are re-routed onto its workspace", function()
      hl_stub.scrolling(hl)
      local y = window_on(2, "t-y", 13)
      window_on(1, "t-x", 13)
      window_on(3, "t-main", 3)
      hyprslots = engine.setup(SLOTS)
      for _, window in ipairs(hl.windows) do
        hl.emit("window.open", window)
      end
      drain()
      assert.are.equal("lua:slots", hl.get_workspace(3).tiled_layout, "no scroll branch on dual")

      unplug_side()
      drain()
      assert.are.equal("single", engine.state(hyprslots).arrangement)
      assert.are.equal("scrolling", hl.get_workspace(3).tiled_layout)
      assert.are.same({ 3, 3 }, { workspace_of("t-x"), workspace_of("t-y") })
      assert.are.same({ "t-main", "t-x", "t-y" }, hl.column_classes(3))
      local moved = index_of("window.move", "address:" .. y.address)
      local swapped = index_of("window.swap")
      assert.is_true(moved < swapped, "the scroll pass ran after the re-route")
    end)
  end)

  it("moves nothing when no arrangement fits what is left", function()
    window_on(1, "t-left", 13)
    hyprslots = engine.setup(engine.TWO_SCREENS)
    hl.monitors = { side }
    hl.emit("monitor.removed", hl_stub.monitor("HEADLESS-2"))
    hl.run_timers()
    hl.run_timers()
    assert.is_nil(engine.state(hyprslots).arrangement)
    assert.are.same({}, hl.dispatched_of("window.move"))
  end)
end)
