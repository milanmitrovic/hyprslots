-- Keyboard resize (slice 5) through the engine seam S2: the slots provider's
-- layout_msg, then recalculate, against a stubbed hl.

local hl_stub = require("helpers.hl_stub")

local SLOTS = [[
return {
  slots = { a = {}, b = {}, c = {} },
  specs = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, workspaces = { [3] = { [1] = "v[h[a, b], c]" } } } },
}
]]

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]]

local AREA = { x = 0, y = 0, w = 2400, h = 1350 }

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

local function fresh_module()
  for name in pairs(package.loaded) do
    if name == "hyprslots" or name:match("^hyprslots%.") then
      package.loaded[name] = nil
    end
  end
  return require("hyprslots")
end

describe("keyboard resize", function()
  local hl, o, dir, hyprslots, windows

  before_each(function()
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) } })
    o = hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
    _G.hl, _G.o = hl, o
    windows = {
      hl_stub.window(1, "t-a", { workspace = 3 }),
      hl_stub.window(2, "t-b", { workspace = 3 }),
      hl_stub.window(3, "t-c", { workspace = 3 }),
    }
    hl.windows = windows
    dir = config_dir({ ["config.lua"] = CONFIG, ["slots.lua"] = SLOTS })
    hyprslots = fresh_module()
    hyprslots.setup({ config_dir = dir })
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    os.execute("rm -rf '" .. dir .. "'")
  end)

  local function ctx()
    return hl_stub.layout_ctx(AREA, windows)
  end

  local function msg(text, focused)
    hl.active_window = focused or windows[1]
    return hl.layouts.slots.layout_msg(ctx(), text)
  end

  local function placed()
    local c = ctx()
    hl.layouts.slots.recalculate(c)
    return hl_stub.placed_by_class(c)
  end

  it("grows the focused slot by a fraction of its split", function()
    assert.is_true(msg("nudge r 0.1"))
    local boxes = placed()
    assert.are.same({ x = 0, y = 0, w = 1440, h = 675 }, boxes["t-a"])
    assert.are.same({ x = 1440, y = 0, w = 960, h = 675 }, boxes["t-b"])
    assert.are.same({ x = 0, y = 675, w = 2400, h = 675 }, boxes["t-c"])
  end)

  it("goes back to the configured tree on reset", function()
    msg("nudge r 0.1")
    msg("nudge d 0.2")
    assert.is_true(msg("reset"))
    local boxes = placed()
    assert.are.same({ x = 0, y = 0, w = 1200, h = 675 }, boxes["t-a"])
    assert.are.same({ x = 0, y = 675, w = 2400, h = 675 }, boxes["t-c"])
  end)

  it("nudges by exact pixels of the layout area", function()
    assert.is_true(msg("nudge l 100px", windows[2]))
    assert.are.same(1300, placed()["t-b"].w)
  end)

  describe("over the tree as laid out", function()
    -- t-c is closed and an unmatched window overflows: h[h[a, b]:3, *:1],
    -- so a and b are 900 px each and the overflow column 600.
    before_each(function()
      windows = { windows[1], windows[2], hl_stub.window(4, "foot", { workspace = 3 }) }
      hl.windows = windows
    end)

    it("moves the edge by exact pixels with the overflow column showing", function()
      assert.are.same({ 900, 900, 600 }, { placed()["t-a"].w, placed()["t-b"].w, placed()["foot"].w })
      assert.is_true(msg("nudge r 100px"))
      assert.are.same({ 1000, 800, 600 }, { placed()["t-a"].w, placed()["t-b"].w, placed()["foot"].w })
    end)

    it("does the same for Omarchy's resize binds", function()
      assert.is_true(msg("resize -50 0", windows[2]))
      assert.are.same({ 850, 950 }, { placed()["t-a"].w, placed()["t-b"].w })
    end)
  end)

  it("accumulates nudges", function()
    msg("nudge r 0.1")
    msg("nudge r 0.1")
    assert.are.same(1680, placed()["t-a"].w)
  end)

  describe("resize <dx> <dy> (Omarchy's resize binds)", function()
    it("moves the right edge when there is something to the right", function()
      assert.is_true(msg("resize 100 0"))
      assert.are.same({ 1300, 1100 }, { placed()["t-a"].w, placed()["t-b"].w })
    end)

    it("moves the left edge of the rightmost slot the same way, as dwindle does", function()
      -- Omarchy's "Expand window left" (dx = -100) widens the rightmost window.
      assert.is_true(msg("resize -100 0", windows[2]))
      assert.are.same({ 1100, 1300 }, { placed()["t-a"].w, placed()["t-b"].w })
    end)

    it("moves the top edge of the bottom slot", function()
      assert.is_true(msg("resize 0 -100", windows[3]))
      assert.are.same({ 575, 775 }, { placed()["t-a"].h, placed()["t-c"].h })
    end)

    it("tells the editor once when it moves both edges", function()
      local before = #hl.dispatched_of("event")
      assert.is_true(msg("resize 100 100"))
      assert.are.same({ 1300, 775 }, { placed()["t-a"].w, placed()["t-a"].h })
      assert.are.equal(before + 1, #hl.dispatched_of("event"))
    end)

    it("tells the editor once when it moves one edge", function()
      local before = #hl.dispatched_of("event")
      assert.is_true(msg("resize 100 0"))
      assert.are.equal(before + 1, #hl.dispatched_of("event"))
    end)
  end)

  it("keeps a nudge, keyed by layout, workspace and screen, across re-selecting the same desk", function()
    msg("nudge r 0.1")
    hl.emit("monitor.added", hl.monitors[1])
    hl.run_timers()
    assert.are.same(1440, placed()["t-a"].w)
    local state = require("hyprslots.dkjson").decode(hyprslots.api.state())
    assert.are.same({ "solo/3/1" }, (function()
      local keys = {}
      for key in pairs(state.resized) do
        keys[#keys + 1] = key
      end
      return keys
    end)())
    assert.are.same({ layout = "solo", workspace = 3, screen = 1, tree = "v[h[a:3, b:2], c]",
      ratio = "1[3:2]:1" }, state.resized["solo/3/1"])
    assert.is_true(state.layouts.solo.workspaces["3"]["1"].resized)
    assert.is_true(state.dirty)
  end)

  describe("refusals change nothing and say why", function()
    local function unchanged()
      assert.are.same(1200, placed()["t-a"].w)
    end

    it("an unknown message", function()
      assert.matches("unknown layout message", msg("bogus 1"))
      unchanged()
    end)

    it("a bad amount", function()
      assert.matches("fraction", msg("nudge r lots"))
      unchanged()
    end)

    it("no neighbour on that side", function()
      assert.matches("nothing right of 'b'", msg("nudge r 0.1", windows[2]))
      unchanged()
    end)

    it("a focused window off any workspace", function()
      assert.matches("not on a hyprslots workspace", msg("nudge r 0.1", hl_stub.window(9, "t-x", { workspace = 1 })))
      unchanged()
    end)

    it("no focused window", function()
      hl.active_window = nil
      assert.matches("no focused window", hl.layouts.slots.layout_msg(ctx(), "reset"))
    end)

    it("an error inside, which is logged rather than raised", function()
      hl.get_active_window = function() error("active window exploded") end
      assert.matches("active window exploded", hl.layouts.slots.layout_msg(ctx(), "nudge r 0.1"))
      assert.matches("active window exploded", hyprslots.dump())
      unchanged()
    end)
  end)
  describe("Omarchy's resize keys", function()
    local OMARCHY_KEYS = {
      ["SUPER + code:20"] = { -100, 0 },
      ["SUPER + code:21"] = { 100, 0 },
      ["SUPER + SHIFT + code:20"] = { 0, -100 },
      ["SUPER + SHIFT + code:21"] = { 0, 100 },
      ["SUPER + ALT + code:20"] = { -25, 0 },
      ["SUPER + ALT + code:21"] = { 25, 0 },
      ["SUPER + SHIFT + ALT + code:20"] = { 0, -25 },
      ["SUPER + SHIFT + ALT + code:21"] = { 0, 25 },
      ["SUPER + CTRL + code:20"] = { -300, 0 },
      ["SUPER + CTRL + code:21"] = { 300, 0 },
      ["SUPER + CTRL + SHIFT + code:20"] = { 0, -300 },
      ["SUPER + CTRL + SHIFT + code:21"] = { 0, 300 },
    }

    before_each(function()
      -- Omarchy's o.bind / o.rebind (default/hypr/helpers.lua), over the stub.
      function o.bind(keys, description, dispatcher, options)
        local opts = options or {}
        opts.description = description
        hl.bind(keys, dispatcher, opts)
      end
      function o.rebind(keys, description, dispatcher, options)
        hl.unbind(keys)
        o.bind(keys, description, dispatcher, options)
      end
    end)

    local function press(keys)
      hl.dispatched = {}
      hl.binds[keys].dispatcher()
    end

    it("rebinds all twelve of them, keeping their descriptions' keys", function()
      hyprslots.bind_resize_keys()
      local rebound = {}
      for keys in pairs(OMARCHY_KEYS) do
        assert.is_function(hl.binds[keys] and hl.binds[keys].dispatcher, keys)
        assert.is_string(hl.binds[keys].opts.description, keys)
        rebound[#rebound + 1] = keys
      end
      table.sort(rebound)
      table.sort(hl.unbound)
      assert.are.same(rebound, hl.unbound)
    end)

    it("sends a resize layout message on a lua:slots workspace", function()
      hyprslots.bind_resize_keys()
      hl.active_workspace = { id = 3, tiled_layout = "lua:slots" }
      for keys, delta in pairs(OMARCHY_KEYS) do
        press(keys)
        assert.are.same({ string.format("resize %d %d", delta[1], delta[2]) }, hl.dispatched_of("layout"), keys)
        assert.are.same({}, hl.dispatched_of("window.resize"), keys)
      end
    end)

    it("keeps Omarchy's own resize everywhere else", function()
      hyprslots.bind_resize_keys()
      hl.active_workspace = { id = 1, tiled_layout = "dwindle" }
      for keys, delta in pairs(OMARCHY_KEYS) do
        press(keys)
        assert.are.same({ { x = delta[1], y = delta[2], relative = true } }, hl.dispatched_of("window.resize"), keys)
        assert.are.same({}, hl.dispatched_of("layout"), keys)
      end
    end)

    it("lets Omarchy's keybindings menu replay a rebound key", function()
      hyprslots.bind_resize_keys()
      local action = hl.binds["SUPER + code:21"].dispatcher
      assert.are.equal("hyprslots.resize_key(100, 0)", o.bind_expressions[action])
    end)

    it("is not done by setup", function()
      assert.are.same({}, hl.binds)
    end)
  end)
end)
