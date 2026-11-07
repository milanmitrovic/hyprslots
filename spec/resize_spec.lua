-- Keyboard resize (slice 5) through the engine seam S2: the slots provider's
-- layout_msg, then recalculate, against a stubbed hl.

local hl_stub = require("helpers.hl_stub")

local SLOTS = [[
return {
  slots = { [3] = { a = "t-a", b = "t-b", c = "t-c" } },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "v[h[a, b], c]" } },
    },
  },
}
]]

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, arrangements = data.arrangements }
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
  local hl, dir, hyprslots, windows

  before_each(function()
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) } })
    _G.hl, _G.o = hl, hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
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

    it("moves the left edge of the rightmost slot", function()
      assert.is_true(msg("resize 100 0", windows[2]))
      assert.are.same({ 1100, 1300 }, { placed()["t-a"].w, placed()["t-b"].w })
    end)

    it("shrinks the bottom slot from its top edge", function()
      assert.is_true(msg("resize 0 -100", windows[3]))
      assert.are.same({ 775, 575 }, { placed()["t-a"].h, placed()["t-c"].h })
    end)
  end)

  it("keeps a nudge across re-selecting the same arrangement", function()
    msg("nudge r 0.1")
    hl.emit("monitor.added", hl.monitors[1])
    hl.run_timers()
    assert.are.same(1440, placed()["t-a"].w)
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

    it("a focused window off any desk", function()
      assert.matches("not on a desk", msg("nudge r 0.1", hl_stub.window(9, "t-x", { workspace = 1 })))
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
end)
