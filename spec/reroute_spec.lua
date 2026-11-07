-- Test seam S2: an editor edit (set_tree, set_ratio) or a reload that moves
-- a slot to another screen role sends the slot's open window there, the way
-- hotplug re-routes (docs/design.md §8, §9).

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("re-routing after an edit", function()
  local hl, hyprslots

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

  local function call(name, args)
    local reply = engine.call(hyprslots, name, require("hyprslots.dkjson").encode(args or {}))
    assert.is_true(reply.ok, reply.error)
    return reply
  end

  before_each(function()
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    hyprslots = engine.setup(engine.TWO_SCREENS)
    -- dual: side = "left", big = "h[main:2, right:1]", all three in place.
    for i, spot in ipairs({ { "t-left", 13 }, { "t-main", 3 }, { "t-right", 3 } }) do
      hl.emit("window.open", window_on(i, spot[1], spot[2]))
    end
    assert.are.equal("dual", engine.state(hyprslots).arrangement)
    assert.are.same({ 13, 3, 3 }, { workspace_of("t-left"), workspace_of("t-main"), workspace_of("t-right") })
  end)

  after_each(engine.cleanup)

  it("moves a window whose slot set_tree put on the other screen", function()
    call("set_tree", { arrangement = "dual", desk = 3, role = "big", tree = "main" })
    assert.are.equal(3, workspace_of("t-right"), "a slot on no screen stays where it is")
    call("set_tree", { arrangement = "dual", desk = 3, role = "side", tree = "h[left, right]" })
    assert.are.equal(13, workspace_of("t-right"))
    assert.are.equal(13, workspace_of("t-left"))
    assert.are.equal(3, workspace_of("t-main"))
  end)

  it("moves windows when a reload swaps slots between screens", function()
    local slots = engine.TWO_SCREENS
      :gsub('side = "left", big = "h%[main:2, right:1%]"', 'side = "right", big = "h[main:2, left:1]"')
    local file = assert(io.open(engine.state(hyprslots).config.data_file, "w"))
    file:write(slots)
    file:close()
    call("reload")
    assert.are.same({ 3, 3, 13 }, { workspace_of("t-left"), workspace_of("t-main"), workspace_of("t-right") })
    assert.are.equal("HEADLESS-3", hl.get_workspace(13).monitor.name)
  end)

  it("leaves windows alone when an edit only changes weights", function()
    local moves = #hl.dispatched_of("window.move")
    call("set_ratio", { arrangement = "dual", desk = 3, role = "big", ratio = "1:1" })
    assert.are.equal(moves, #hl.dispatched_of("window.move"))
  end)
end)
