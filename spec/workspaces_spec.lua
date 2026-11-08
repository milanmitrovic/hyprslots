-- Test seam S2: workspace switching across every screen of the active desk
-- (docs/design.md §5), through api.call("workspace") and hyprslots.workspace(n).

local engine = require("helpers.engine")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

local NINE = engine.CONFIG:gsub("layouts = data.layouts", "layouts = data.layouts, workspaces = 9", 1)

local PINNED_SIDE = engine.TWO_SCREENS:gsub('layout = "dual" }', 'layout = "dual", pinned = { 2 } }', 1)

describe("workspaces across screens", function()
  local hl, o, hyprslots

  local function focus(name)
    for _, monitor in ipairs(hl.monitors) do
      monitor.focused = monitor.name == name
    end
  end

  after_each(engine.cleanup)

  describe("with two screens", function()
    before_each(function()
      hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    end)

    it("shows workspace N on every screen, the focused one last", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      local reply = engine.call(hyprslots, "workspace", '{"workspace": 3}')
      assert.is_true(reply.ok)
      assert.are.same({
        { workspace = 3, monitor = "HEADLESS-3" },
        { workspace = 3, monitor = "HEADLESS-2" },
      }, o.workspaces.focused)
    end)

    it("refocuses the screen that was focused", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      focus("HEADLESS-3")
      engine.call(hyprslots, "workspace", '{"workspace": 2}')
      assert.are.same({
        { workspace = 2, monitor = "HEADLESS-2" },
        { workspace = 2, monitor = "HEADLESS-3" },
      }, o.workspaces.focused)
      local focused = hl.dispatched_of("focus")
      assert.are.same({ monitor = "HEADLESS-3" }, focused[#focused])
    end)

    it("hyprslots.workspace(n) is the same switch, for a keybinding", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      hl.dispatch(hyprslots.workspace(5))
      assert.are.same({
        { workspace = 5, monitor = "HEADLESS-3" },
        { workspace = 5, monitor = "HEADLESS-2" },
      }, o.workspaces.focused)
    end)

    it("leaves a pinned screen on whatever workspace it shows", function()
      hyprslots = engine.setup(PINNED_SIDE)
      engine.call(hyprslots, "workspace", '{"workspace": 3}')
      assert.are.same({ { workspace = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
    end)

    it("switches the other screens from a pinned one and keeps focus on it", function()
      hyprslots = engine.setup(PINNED_SIDE)
      focus("HEADLESS-3")
      engine.call(hyprslots, "workspace", '{"workspace": 3}')
      assert.are.same({ { workspace = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
      local focused = hl.dispatched_of("focus")
      assert.are.same({ monitor = "HEADLESS-3" }, focused[#focused])
    end)

    it("skips a screen set_pinned pins on the active desk, and switches it again once unpinned", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      local reply = engine.call(hyprslots, "set_pinned", '{"pinned": [2]}')
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("dual", reply.desk)
      assert.are.same({ 2 }, reply.pinned)
      assert.are.same({ 2 }, engine.state(hyprslots).pinned)
      assert.are.same({ 2 }, engine.state(hyprslots).desks.dual.pinned)
      engine.call(hyprslots, "workspace", '{"workspace": 3}')
      assert.are.same({ { workspace = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)

      assert.is_true(engine.call(hyprslots, "set_pinned", '{"desk": "dual", "pinned": []}').ok)
      assert.are.same({}, engine.state(hyprslots).pinned)
      engine.call(hyprslots, "workspace", '{"workspace": 4}')
      assert.are.same({ workspace = 4, monitor = "HEADLESS-3" }, o.workspaces.focused[2])
    end)
  end)

  it("switches only the focused screen when no desk matches", function()
    hl, o = engine.stub({ "HEADLESS-2", "DP-9" }, BLOCKS)
    hyprslots = engine.setup(engine.TWO_SCREENS)
    assert.is_nil(engine.state(hyprslots).desk)
    engine.call(hyprslots, "workspace", '{"workspace": 3}')
    assert.are.same({ { workspace = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
  end)

  describe("with workspaces = 9", function()
    before_each(function()
      hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
      hyprslots = engine.setup(engine.TWO_SCREENS, NINE)
    end)

    it("switches to workspace 9 but refuses 10", function()
      assert.is_true(engine.call(hyprslots, "workspace", '{"workspace": 9}').ok)
      local reply = engine.call(hyprslots, "workspace", '{"workspace": 10}')
      assert.is_false(reply.ok)
      assert.matches("a workspace must be an integer from 1 to 9, got 10", reply.error)
    end)

    it("says how many workspaces it manages in state", function()
      assert.are.equal(9, engine.state(hyprslots).workspace_count)
    end)

    it("refuses to assign a window to workspace 10", function()
      local window = require("helpers.hl_stub").window(1, "kitty", { workspace = hl.get_workspace(1) })
      hl.windows[#hl.windows + 1] = window
      hl.emit("window.open", window)
      local reply = engine.call(hyprslots, "assign", require("hyprslots.dkjson").encode({ address = window.address,
        workspace = 10, slot = "main" }))
      assert.matches("a workspace must be an integer from 1 to 9, got 10", reply.error)
    end)
  end)

  it("says it manages ten workspaces by default", function()
    hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hyprslots = engine.setup(engine.TWO_SCREENS)
    assert.are.equal(10, engine.state(hyprslots).workspace_count)
  end)

  describe("when hyprslots is not running", function()
    before_each(function()
      hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    end)

    it("Super+N falls back to Omarchy's own switch on a refused engine", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      o.workspaces.enabled = false -- hyprmoncfg's planner took over
      hl.emit("config.reloaded")
      assert.is_truthy(engine.state(hyprslots).refused)

      hl.dispatch(hyprslots.workspace(4))
      assert.are.same({ { workspace = 4 } }, o.workspaces.focused, "o.workspaces.focus(4), the focused screen only")
    end)

    it("the api's workspace call still reports the refusal and switches nothing", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      o.workspaces.enabled = false
      hl.emit("config.reloaded")
      local reply = engine.call(hyprslots, "workspace", '{"workspace": 4}')
      assert.is_false(reply.ok)
      assert.matches("not running", reply.error)
      assert.are.same({}, o.workspaces.focused)
    end)

    it("an out-of-range workspace is no fallback", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      o.workspaces.enabled = false
      hl.emit("config.reloaded")
      hl.dispatch(hyprslots.workspace(11))
      assert.are.same({}, o.workspaces.focused)
    end)
  end)

  describe("bind_workspace_keys", function()
    before_each(function()
      hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    end)

    it("rebinds Super+1..0 to workspace switching through Omarchy's o.rebind", function()
      local rebound = {}
      o.rebind = function(keys, description, dispatcher)
        rebound[#rebound + 1] = { keys = keys, description = description, dispatcher = dispatcher }
      end
      hyprslots = engine.setup(engine.TWO_SCREENS)
      assert.are.same({}, rebound, "setup alone leaves Omarchy's bindings alone")

      hyprslots.bind_workspace_keys()
      assert.are.equal(10, #rebound)
      assert.are.equal("SUPER + code:10", rebound[1].keys)
      assert.are.equal("SUPER + code:19", rebound[10].keys)
      assert.matches("workspace 1", rebound[1].description)

      hl.dispatch(rebound[10].dispatcher)
      assert.are.same({
        { workspace = 10, monitor = "HEADLESS-3" },
        { workspace = 10, monitor = "HEADLESS-2" },
      }, o.workspaces.focused)
      assert.are.equal("hyprslots.workspace(10)", o.bind_expressions[rebound[10].dispatcher])
    end)

    it("with workspaces = 9 rebinds Super+1..9 and leaves Super+0 Omarchy's", function()
      local rebound = {}
      o.rebind = function(keys) rebound[#rebound + 1] = keys end
      hyprslots = engine.setup(engine.TWO_SCREENS, NINE)
      hyprslots.bind_workspace_keys()
      assert.are.equal(9, #rebound)
      assert.are.equal("SUPER + code:18", rebound[9])
    end)

    it("falls back to hl.unbind and hl.bind without o.rebind", function()
      local calls = {}
      hl.unbind = function(keys) calls[#calls + 1] = { "unbind", keys } end
      hl.bind = function(keys, dispatcher) calls[#calls + 1] = { "bind", keys, type(dispatcher) } end
      hyprslots = engine.setup(engine.TWO_SCREENS)
      hyprslots.bind_workspace_keys()
      assert.are.equal(20, #calls)
      assert.are.same({ "unbind", "SUPER + code:12" }, calls[5])
      assert.are.same({ "bind", "SUPER + code:12", "function" }, calls[6])
    end)

    it("keeps hyprslots.desk and bind_desk_keys as deprecated aliases", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      assert.are.equal(hyprslots.workspace, hyprslots.desk)
      assert.are.equal(hyprslots.bind_workspace_keys, hyprslots.bind_desk_keys)
    end)
  end)
end)
