-- Test seam S2: desk switching across every screen of the arrangement
-- (docs/design.md §5), through api.call("desk") and hyprslots.desk(n).

local engine = require("helpers.engine")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

local PINNED_SIDE = engine.TWO_SCREENS:gsub("^return {", 'return {\n  pinned = { "side" },')

describe("desks across screens", function()
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

    it("shows desk N on every screen, the focused one last", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      local reply = engine.call(hyprslots, "desk", '{"desk": 3}')
      assert.is_true(reply.ok)
      assert.are.same({
        { desk = 3, monitor = "HEADLESS-3" },
        { desk = 3, monitor = "HEADLESS-2" },
      }, o.workspaces.focused)
    end)

    it("refocuses the screen that was focused", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      focus("HEADLESS-3")
      engine.call(hyprslots, "desk", '{"desk": 2}')
      assert.are.same({
        { desk = 2, monitor = "HEADLESS-2" },
        { desk = 2, monitor = "HEADLESS-3" },
      }, o.workspaces.focused)
      local focused = hl.dispatched_of("focus")
      assert.are.same({ monitor = "HEADLESS-3" }, focused[#focused])
    end)

    it("hyprslots.desk(n) is the same switch, for a keybinding", function()
      hyprslots = engine.setup(engine.TWO_SCREENS)
      hl.dispatch(hyprslots.desk(5))
      assert.are.same({
        { desk = 5, monitor = "HEADLESS-3" },
        { desk = 5, monitor = "HEADLESS-2" },
      }, o.workspaces.focused)
    end)

    it("leaves a pinned screen on whatever desk it shows", function()
      hyprslots = engine.setup(PINNED_SIDE)
      engine.call(hyprslots, "desk", '{"desk": 3}')
      assert.are.same({ { desk = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
    end)

    it("switches the other screens from a pinned one and keeps focus on it", function()
      hyprslots = engine.setup(PINNED_SIDE)
      focus("HEADLESS-3")
      engine.call(hyprslots, "desk", '{"desk": 3}')
      assert.are.same({ { desk = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
      local focused = hl.dispatched_of("focus")
      assert.are.same({ monitor = "HEADLESS-3" }, focused[#focused])
    end)
  end)

  it("switches only the focused screen when no arrangement matches", function()
    hl, o = engine.stub({ "HEADLESS-2", "DP-9" }, BLOCKS)
    hyprslots = engine.setup(engine.TWO_SCREENS)
    assert.is_nil(engine.state(hyprslots).arrangement)
    engine.call(hyprslots, "desk", '{"desk": 3}')
    assert.are.same({ { desk = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
  end)
end)
