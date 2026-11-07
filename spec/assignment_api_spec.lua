-- Test seam S2: what the editor's Assignment view needs from the api
-- (docs/design.md §9): overflowing windows in `state`, and the `assign` /
-- `unassign` calls that put a window into a slot, or take it out, by hand.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("the Assignment view's api", function()
  local hl, hyprslots

  local function open(id, class, workspace, title)
    local window = hl_stub.window(id, class, { title = title or class, workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.get_workspace(workspace).windows = hl.get_workspace(workspace).windows + 1
    hl.emit("window.open", window)
    return window
  end

  local function close(window)
    for i, w in ipairs(hl.windows) do
      if w == window then
        table.remove(hl.windows, i)
      end
    end
    hl.emit("window.close", window)
  end

  local function state()
    return engine.state(hyprslots)
  end

  local function call(name, args)
    return engine.call(hyprslots, name, require("hyprslots.dkjson").encode(args or {}))
  end

  local function window_entry(s, window)
    for _, entry in ipairs(s.windows) do
      if entry.address == window.address then
        return entry
      end
    end
  end

  before_each(function()
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    -- dual: side = "left", big = "h[main:2, right:1]"
    hyprslots = engine.setup(engine.TWO_SCREENS)
  end)

  after_each(engine.cleanup)

  describe("state", function()
    it("lists the windows that overflow, with the slot whose desk holds them", function()
      open(1, "t-left", 1)
      local extra = open(2, "t-left", 1)
      local s = state()
      assert.are.same({ [extra.address] = { desk = 3, slot = "left" } }, s.overflow)
      assert.are.same({ desk = 3, slot = "left" }, window_entry(s, extra).overflow)
    end)

    it("lists no overflow when every matched window has a slot", function()
      open(1, "t-left", 1)
      assert.are.same({}, state().overflow)
    end)
  end)
end)
