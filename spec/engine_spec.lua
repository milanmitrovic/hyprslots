-- Test seam S2: hyprslots.setup() and hyprslots.api.call against a stubbed hl.

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local SLOTS = [[
return {
  slots = { a = {}, b = {}, c = {} },
  specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "h[a, b, c]" }, workspaces = { [3] = { [1] = "h[a:1, b:2, c:1]" } } } },
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

local AREA = { x = 0, y = 0, w = 2400, h = 1350 }

describe("hyprslots engine", function()
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

  local function state()
    return json.decode(hyprslots.api.call("state", "{}"))
  end

  local function recalculate(windows, area)
    local ctx = hl_stub.layout_ctx(area or AREA, windows)
    hl.layouts.slots.recalculate(ctx)
    return hl_stub.placed_by_class(ctx), ctx
  end

  before_each(function()
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) } })
    o = hl_stub.omarchy({ ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 })
    _G.hl, _G.o = hl, o
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    if dir then os.execute("rm -rf '" .. dir .. "'") end
    dir = nil
  end)

  describe("setup", function()
    it("registers the slots layout", function()
      setup()
      assert.is_function(hl.layouts.slots.recalculate)
    end)

    it("makes every block's workspaces use lua:slots, the shared tree where they have none", function()
      setup()
      local rules = {}
      for _, rule in ipairs(hl.workspace_rules) do
        rules[rule.workspace] = rule.layout
      end
      assert.are.equal("lua:slots", rules["3"])
      assert.are.equal("lua:slots", rules["13"])
      assert.are.equal("lua:slots", rules["4"], "workspace 4 has the shared tree")
    end)

    it("selects the desk for the monitors already connected", function()
      setup()
      assert.are.equal("solo", state().desk)
      assert.are.equal("solo", state().layout)
      assert.are.same({ workspace = 3, screen = 1, monitor = "HEADLESS-2", layout = "lua:slots" }, state().workspaces["3"])
      assert.is_false(state().dirty)
      assert.is_nil(state().config.migrated)
    end)

    it("never raises, and reports a broken config with a notification", function()
      setup({ ["config.lua"] = "return { slots = { a = {} }, specs = { [3] = { a = '[x' } } }" })
      assert.are.equal(1, #hl.notifications)
      assert.matches("hyprslots", hl.notifications[1].text)
      assert.matches("%[x", state().config_error)
      assert.is_function(hl.layouts.slots.recalculate, "the layout still exists so lua:slots never dangles")
    end)

    it("does not notify when there is simply no config", function()
      setup({})
      assert.are.equal(0, #hl.notifications)
      assert.matches("no config", state().config_error)
    end)

    it("contains an error raised while starting", function()
      hl.get_monitors = function() error("monitor query exploded") end
      assert.has_no.errors(function() setup() end)
      assert.are.equal(1, #hl.notifications)
      assert.matches("monitor query exploded", hyprslots.dump())
    end)

    it("refuses to start without Omarchy's o.workspaces", function()
      _G.o = nil
      setup()
      assert.are.equal(1, #hl.notifications)
      assert.matches("o.workspaces", state().refused)
    end)
  end)

  describe("a slots.lua of arrangements (the shape of before)", function()
    local OLD = [[
return {
  slots = { a = {}, b = {}, c = {} },
  specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a:1, b:2, c:1]" } },
    },
  },
  pinned = { "main" },
}
]]

    it("runs as desks and layouts, dirty until saved", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = OLD })
      local s = state()
      assert.is_nil(s.config_error)
      assert.are.equal("solo", s.desk)
      assert.are.equal("solo", s.layout)
      assert.are.same({ workspace = 3, screen = 1, monitor = "HEADLESS-2", layout = "lua:slots" }, s.workspaces["3"])
      assert.is_nil(s.desks.solo.pinned, "pinned screens are gone")
      assert.is_true(s.config.migrated)
      assert.is_true(s.dirty, "what runs differs from the file until it is saved")
      local placed = recalculate({ hl_stub.window(1, "t-a", { workspace = 3 }), hl_stub.window(2, "t-b", { workspace = 3 }) })
      assert.are.same({ x = 0, y = 0, w = 800, h = 1350 }, placed["t-a"])
      assert.is_true(json.decode(hyprslots.api.call("set_tree", '{"workspace": 3, "screen": 1, "tree": "h[a, b]"}')).ok)
      assert.is_true(state().config.migrated, "the file is still in the shape of before after an edit")
    end)

    it("save writes the new shape, which then loads clean", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = OLD })
      assert.is_true(json.decode(hyprslots.api.call("save", "{}")).ok)
      assert.is_false(state().dirty)
      local written = assert(loadfile(dir .. "/slots.lua", "t", {}))()
      assert.is_nil(written.arrangements)
      assert.is_nil(written.pinned)
      assert.are.same({ solo = { monitors = { "HEADLESS-2" }, layout = "solo" } }, written.desks)
      assert.are.same({ solo = { screens = 1, default = { [1] = "h[a, b, c]" }, workspaces = { [3] = { [1] = "h[a:1, b:2, c:1]" } } } },
        written.layouts, "the layout of before had no shared tree: it gets the default one")

      hyprslots.setup({ config_dir = dir })
      assert.is_false(state().dirty)
      assert.is_nil(state().config.migrated)
      assert.are.equal("solo", state().desk)
    end)

    local function call(name, args)
      return json.decode(hyprslots.api.call(name, json.encode(args or {})))
    end

    it("stays dirty after a reset back to the file: the file is still in the shape of before", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = OLD })
      assert.is_true(call("set_tree", { workspace = 3, screen = 1, tree = "v[a, b, c]" }).ok)
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a, b:2, c]", reply.tree)
      assert.is_true(state().dirty)
    end)

    it("forgets the renames made before a reload", function()
      setup({ ["config.lua"] = CONFIG, ["slots.lua"] = OLD })
      assert.is_true(call("rename_slot", { slot = "a", to = "x" }).ok)
      assert.is_true(call("reload").ok)
      assert.is_true(state().dirty)
      assert.is_true(call("set_tree", { workspace = 3, screen = 1, tree = "v[a, b, c]" }).ok)
      local reply = call("reset", { workspace = 3, screen = 1 })
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("h[a, b:2, c]", reply.tree)
    end)
  end)

  describe("refusing to fight hyprmoncfg's workspace planner", function()
    for _, event in ipairs({ "hyprland.start", "config.reloaded" }) do
      it("refuses on " .. event .. " when o.workspaces.enabled is false", function()
        setup()
        o.workspaces.enabled = false
        hl.emit(event)
        assert.matches("enabled = false", state().refused)
        assert.are.equal(1, #hl.notifications)

        hl.emit("window.open", hl_stub.window(1, "t-a", { workspace = 1 }))
        assert.are.same({}, hl.dispatched_of("window.move"), "a refused engine moves nothing")
      end)
    end

    it("starts normally when o.workspaces is enabled", function()
      setup()
      hl.emit("hyprland.start")
      assert.is_nil(state().refused)
      assert.are.equal(0, #hl.notifications)
    end)
  end)

  describe("desk selection on hotplug", function()
    it("re-selects after a monitor is added, once the event has returned", function()
      hl.monitors = {}
      setup()
      assert.is_nil(state().desk)

      hl.monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) }
      hl.emit("monitor.added", hl.monitors[1])
      assert.is_nil(state().desk, "deferred, not inside the event")

      hl.run_timers()
      assert.are.equal("solo", state().desk)
    end)

    it("drops the desk when its monitor is removed", function()
      setup()
      local gone = hl.monitors[1]
      hl.monitors = {}
      hl.emit("monitor.removed", gone)
      hl.run_timers()
      assert.is_nil(state().desk)
    end)
  end)

  describe("routing", function()
    it("moves a matched window to its slot's workspace when it opens elsewhere", function()
      setup()
      local window = hl_stub.window(1, "t-b", { workspace = 1 })
      hl.emit("window.open", window)
      assert.are.same({ { workspace = "3", window = "address:" .. window.address, follow = false } },
        hl.dispatched_of("window.move"))
      assert.are.same({ workspace = 3, slot = "b" }, state().assignments[window.address])
    end)

    it("uses the workspace of the screen holding the slot", function()
      o = hl_stub.omarchy({ ["HEADLESS-2"] = 2 })
      _G.o = o
      setup()
      hl.emit("window.open", hl_stub.window(1, "t-b", { workspace = 1 }))
      assert.are.equal("23", hl.dispatched_of("window.move")[1].workspace)
    end)

    it("leaves a window already on its workspace alone", function()
      setup()
      hl.emit("window.open", hl_stub.window(1, "t-b", { workspace = 3 }))
      assert.are.same({}, hl.dispatched_of("window.move"))
    end)

    it("leaves a window that matches no slot alone", function()
      setup()
      hl.emit("window.open", hl_stub.window(1, "firefox", { workspace = 1 }))
      assert.are.same({}, hl.dispatched_of("window.move"))
    end)

    it("leaves a matched window alone when no desk places its slot", function()
      hl.monitors = { hl_stub.monitor("DP-9", { focused = true }) }
      setup()
      hl.emit("window.open", hl_stub.window(1, "t-b", { workspace = 1 }))
      assert.are.same({}, hl.dispatched_of("window.move"))
    end)

    it("frees the slot when its window is destroyed", function()
      setup()
      local first = hl_stub.window(1, "t-b", { workspace = 1 })
      hl.emit("window.open", first)
      hl.emit("window.destroy", first)
      local second = hl_stub.window(2, "t-b", { workspace = 1 })
      hl.emit("window.open", second)
      assert.are.same({ workspace = 3, slot = "b" }, state().assignments[second.address])
      assert.is_nil(state().assignments[first.address])
    end)

    it("assigns the windows that already exist when it starts (config reload)", function()
      hl.windows = { hl_stub.window(5, "t-c", { workspace = 3 }) }
      setup()
      assert.are.same({ workspace = 3, slot = "c" }, state().assignments[hl.windows[1].address])
    end)
  end)

  describe("the slots layout", function()
    local function opened(id, class, ws)
      local window = hl_stub.window(id, class, { workspace = ws or 3 })
      hl.emit("window.open", window)
      return window
    end

    it("places each window in its slot's box", function()
      setup()
      local windows = { opened(1, "t-c"), opened(2, "t-a"), opened(3, "t-b") }
      local placed = recalculate(windows)
      assert.are.same({ x = 0, y = 0, w = 600, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 600, y = 0, w = 1200, h = 1350 }, placed["t-b"])
      assert.are.same({ x = 1800, y = 0, w = 600, h = 1350 }, placed["t-c"])
    end)

    it("places a window that has not reached window.open yet", function()
      setup()
      local windows = { hl_stub.window(1, "t-a", { workspace = 3 }) }
      local placed = recalculate(windows)
      assert.are.same({ x = 0, y = 0, w = 2400, h = 1350 }, placed["t-a"])
    end)

    it("closes up around an empty slot, keeping the ratio of the rest", function()
      setup()
      local placed = recalculate({ opened(1, "t-a"), opened(2, "t-b") })
      assert.are.same({ x = 0, y = 0, w = 800, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 800, y = 0, w = 1600, h = 1350 }, placed["t-b"])
    end)

    it("works in the area Hyprland hands it, offset and fractional", function()
      setup()
      local placed = recalculate({ opened(1, "t-a") }, { x = 2400.0, y = 30.0, w = 1920.0, h = 1050.0 })
      assert.are.same({ x = 2400, y = 30, w = 1920, h = 1050 }, placed["t-a"])
    end)

    it("puts windows with no slot in an overflow column", function()
      setup()
      local placed = recalculate({ opened(1, "t-a"), opened(2, "firefox"), opened(3, "foot") })
      assert.are.same({ x = 0, y = 0, w = 1800, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 1800, y = 0, w = 600, h = 675 }, placed["firefox"])
      assert.are.same({ x = 1800, y = 675, w = 600, h = 675 }, placed["foot"])
    end)

    it("tiles a workspace the layout has no tree for in columns", function()
      setup()
      local placed = recalculate({ opened(1, "t-a", 4), opened(2, "foot", 4) })
      assert.are.same({ x = 0, y = 0, w = 1200, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 1200, y = 0, w = 1200, h = 1350 }, placed["foot"])
    end)

    it("falls back to columns and logs when placing fails", function()
      setup()
      local cursed = setmetatable({ address = "0xbad", stable_id = 9, workspace = { id = 3 } }, {
        __index = function(_, key) error("cursed window field " .. key) end,
      })
      local placed, ctx = recalculate({ opened(1, "t-a"), cursed })
      assert.are.same({ x = 0, y = 0, w = 1200, h = 1350 }, placed["t-a"])
      assert.are.same({ x = 1200, y = 0, w = 1200, h = 1350 }, ctx.targets[2].placed)
      assert.matches("cursed window field", hyprslots.dump())
    end)

    it("dispatches nothing while placing", function()
      setup()
      local windows = { opened(1, "t-a"), opened(2, "t-b") }
      local before = #hl.dispatched
      recalculate(windows)
      assert.are.equal(before, #hl.dispatched)
    end)

    it("does nothing with no targets", function()
      setup()
      assert.has_no.errors(function() recalculate({}) end)
    end)
  end)

  describe("workspaces", function()
    it("activates workspace N on the focused screen through o.workspaces", function()
      setup()
      local reply = json.decode(hyprslots.api.call("workspace", '{"workspace": 3}'))
      assert.is_true(reply.ok)
      assert.are.same({ { workspace = 3, monitor = "HEADLESS-2" } }, o.workspaces.focused)
    end)

    it("hyprslots.workspace(n) returns the same action for a keybinding", function()
      setup()
      local action = hyprslots.workspace(4)
      assert.is_function(action)
      hl.dispatch(action)
      assert.are.same({ { workspace = 4, monitor = "HEADLESS-2" } }, o.workspaces.focused)
      assert.are.equal("hyprslots.workspace(4)", o.bind_expressions[action])
    end)

    it("rejects a workspace that is not 1-10", function()
      setup()
      local reply = json.decode(hyprslots.api.call("workspace", '{"workspace": 11}'))
      assert.is_false(reply.ok)
      assert.matches("workspace", reply.error)
      assert.are.same({}, o.workspaces.focused)
    end)
  end)

  describe("api", function()
    it("answers state as JSON", function()
      setup()
      local s = state()
      assert.is_true(s.ok)
      assert.are.equal("solo", s.desk)
      assert.are.equal("solo", s.layout)
      assert.are.same({ "HEADLESS-2" }, s.screens)
      assert.is_nil(s.arrangement)
      assert.is_nil(s.arrangements)
    end)

    it("reports malformed JSON as an error reply", function()
      setup()
      local reply = json.decode(hyprslots.api.call("workspace", "{nope"))
      assert.is_false(reply.ok)
      assert.matches("JSON", reply.error)
    end)

    it("reports an unknown call as an error reply", function()
      setup()
      local reply = json.decode(hyprslots.api.call("frobnicate", "{}"))
      assert.is_false(reply.ok)
      assert.matches("frobnicate", reply.error)
    end)

    it("accepts a call with no arguments", function()
      setup()
      assert.is_true(json.decode(hyprslots.api.call("state")).ok)
    end)

    it("answers before setup instead of raising", function()
      hyprslots = fresh_module()
      local reply = json.decode(hyprslots.api.call("state", "{}"))
      assert.is_false(reply.ok)
      assert.matches("setup", reply.error)
    end)
  end)

  describe("dump", function()
    it("shows the state and the log", function()
      setup()
      hl.emit("window.open", hl_stub.window(1, "t-b", { workspace = 1 }))
      local text = hyprslots.dump()
      assert.matches('"desk":%s*"solo"', text)
      assert.matches("t%-b", text)
    end)
  end)
end)
