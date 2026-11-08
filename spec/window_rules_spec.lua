-- Test seam S2: class-only specs generate hl.window_rule entries that open a
-- window straight on its slot's workspace under the active desk's layout
-- (docs/design.md §7), kept current as desks, layouts and slots change.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("generated window rules", function()
  local hl, hyprslots

  -- The last spec registered under a rule name, or nil.
  local function rule(name)
    local last
    for _, spec in ipairs(hl.window_rules) do
      if spec.name == name then
        last = spec
      end
    end
    return last
  end

  local function names()
    local seen, out = {}, {}
    for _, spec in ipairs(hl.window_rules) do
      if not seen[spec.name] then
        seen[spec.name] = true
        out[#out + 1] = spec.name
      end
    end
    table.sort(out)
    return out
  end

  local function open(id, class, workspace, title)
    local window = hl_stub.window(id, class, { title = title or class, workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.emit("window.open", window)
    return window
  end

  after_each(engine.cleanup)

  describe("with two screens", function()
    before_each(function()
      hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
      hl_stub.simulate(hl)
      hl.add_workspace(1, "HEADLESS-2")
      hl.add_workspace(11, "HEADLESS-3")
      hyprslots = engine.setup(engine.TWO_SCREENS)
    end)

    it("sends each class-only spec's windows to its slot's workspace, silently", function()
      assert.are.same({ "hyprslots-t-left", "hyprslots-t-main", "hyprslots-t-right" }, names())
      assert.are.same({ name = "hyprslots-t-left", enabled = true, match = { class = "^(t-left)$" }, workspace = "13 silent" },
        rule("hyprslots-t-left"))
      assert.are.equal("3 silent", rule("hyprslots-t-main").workspace)
      assert.are.equal("3 silent", rule("hyprslots-t-right").workspace)
    end)

    it("follows the desk when a screen goes away", function()
      local side = hl.monitors[2]
      hl.monitors = { hl.monitors[1] }
      hl.emit("monitor.removed", side)
      hl.run_timers()
      hl.run_timers()
      assert.are.equal("3 silent", rule("hyprslots-t-left").workspace)
    end)

    it("keeps sending a class to its workspace while its slot is taken, for that workspace's overflow", function()
      local count = #hl.window_rules
      local window = open(1, "t-main", 1)
      assert.are.equal(count, #hl.window_rules, "nothing to re-register")
      assert.are.same({ name = "hyprslots-t-main", enabled = true, match = { class = "^(t-main)$" },
        workspace = "3 silent" }, rule("hyprslots-t-main"))
      hl.windows = {}
      hl.emit("window.destroy", window)
      assert.are.equal("3 silent", rule("hyprslots-t-main").workspace)
    end)

    it("follows a slot that an editor edit moved to the other screen", function()
      local function call(name, args)
        local reply = engine.call(hyprslots, name, require("hyprslots.dkjson").encode(args))
        assert.is_true(reply.ok, reply.error)
      end
      call("set_tree", { layout = "dual", workspace = 3, screen = 1, tree = "main" })
      call("set_tree", { layout = "dual", workspace = 3, screen = 2, tree = "h[left, right]" })
      assert.are.equal("13 silent", rule("hyprslots-t-right").workspace)
    end)

    it("follows slots that a reload moved", function()
      local slots = engine.TWO_SCREENS
        :gsub('%[1%] = "h%[main:2, right:1%]", %[2%] = "left"', '[1] = "h[main:2, left:1]", [2] = "right"')
      local file = assert(io.open(engine.state(hyprslots).config.data_file, "w"))
      file:write(slots)
      file:close()
      assert.is_true(engine.call(hyprslots, "reload", "{}").ok)
      assert.are.equal("3 silent", rule("hyprslots-t-left").workspace)
      assert.are.equal("13 silent", rule("hyprslots-t-right").workspace)
    end)

    it("turns off the rule of a class a reload no longer has a spec for", function()
      local slots = engine.TWO_SCREENS
        :gsub('right = "t%-right"', 'right = "t-other"')
      local file = assert(io.open(engine.state(hyprslots).config.data_file, "w"))
      file:write(slots)
      file:close()
      assert.is_true(engine.call(hyprslots, "reload", "{}").ok)
      assert.are.same({ name = "hyprslots-t-right", enabled = false }, rule("hyprslots-t-right"))
      assert.are.equal("3 silent", rule("hyprslots-t-other").workspace)
    end)

    it("does not register a rule again when nothing about it changed", function()
      local count = #hl.window_rules
      assert.are.equal(3, count)
      open(1, "firefox", 1)
      hl.emit("config.reloaded")
      assert.are.equal(count, #hl.window_rules)
    end)
  end)

  it("escapes regex characters in the class", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup([[
return {
  slots = { main = {} },
  specs = { [3] = { main = "org.gnome.Nautilus" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, workspaces = { [3] = { [1] = "main" } } } },
}
]])
    assert.are.same({ class = [[^(org\.gnome\.Nautilus)$]] }, rule("hyprslots-org.gnome.Nautilus").match)
  end)

  it("leaves a class to the router while an earlier title spec of it is free", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hyprslots = engine.setup([[
return {
  slots = { main = {} },
  specs = { [2] = { main = "foot/deltaf" }, [3] = { main = "foot" }, [4] = { main = "t-only/x" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "main" } } },
}
]])
    assert.are.same({ "hyprslots-foot" }, names(), "a class with title specs only gets no rule")
    assert.is_false(rule("hyprslots-foot").enabled, "a foot window might be deltaf's")

    open(1, "foot", 1, "deltaf | zellij")
    assert.are.equal("3 silent", rule("hyprslots-foot").workspace)

    -- With every foot slot taken, the first of them is a title spec: where an
    -- extra foot window overflows depends on its title, so the router decides.
    open(2, "foot", 1, "notes | x")
    assert.is_false(rule("hyprslots-foot").enabled)
  end)

  it("leaves a class to the router when a browser tag spec comes first", function()
    hl = engine.stub({ "HEADLESS-2" }, BLOCKS)
    hyprslots = engine.setup([[
return {
  slots = { main = {} },
  specs = { [2] = { main = "[Work]" }, [3] = { main = "chromium" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, workspaces = { [2] = { [1] = "main" }, [3] = { [1] = "main" } } } },
}
]])
    assert.is_false(rule("hyprslots-chromium").enabled)
  end)

  it("turns every rule off when no desk matches the screens", function()
    hl = engine.stub({ "DP-9" }, BLOCKS)
    hyprslots = engine.setup(engine.TWO_SCREENS)
    assert.are.equal(3, #names())
    for _, name in ipairs(names()) do
      assert.is_false(rule(name).enabled, name)
    end
  end)
end)
