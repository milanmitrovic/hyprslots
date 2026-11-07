-- Test seam S2: accordions (Hyprland groups) and the overflow leaf, driven
-- through hyprslots.setup() and the slots layout against a stubbed hl.

local hl_stub = require("helpers.hl_stub")

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, arrangements = data.arrangements }
]]

local function slots_lua(tree)
  return string.format([[
return {
  slots = { [3] = { x = "t-x", y = "t-y", z = "t-z", d = "t-d" } },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = %q } },
    },
  },
}
]], tree)
end

local AREA = { x = 0, y = 0, w = 2400, h = 1350 }

local function box(x, y, w, h) return { x = x, y = y, w = w, h = h } end

describe("accordions and overflow", function()
  local hl, dir, hyprslots

  local function setup(tree)
    dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    for name, content in pairs({ ["config.lua"] = CONFIG, ["slots.lua"] = slots_lua(tree) }) do
      local file = assert(io.open(dir .. "/" .. name, "w"))
      file:write(content)
      file:close()
    end
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    hyprslots = require("hyprslots")
    assert(hyprslots.setup({ config_dir = dir }))
  end

  -- A window on desk 3 that has been through window.open.
  local function opened(id, class, ws)
    local window = hl_stub.window(id, class, { workspace = ws or 3 })
    hl.windows[#hl.windows + 1] = window
    hl.emit("window.open", window)
    return window
  end

  local function recalculate(windows)
    local ctx = hl_stub.layout_ctx(AREA, windows)
    hl.layouts.slots.recalculate(ctx)
    return hl_stub.placed_by_class(ctx), ctx
  end

  before_each(function()
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) } })
    _G.hl, _G.o = hl, hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    if dir then os.execute("rm -rf '" .. dir .. "'") end
    dir = nil
  end)

  describe("the overflow leaf", function()
    it("stacks unmatched windows in an explicit overflow leaf, equally", function()
      setup("h[x:1, v[d, *]:1]")
      local placed = recalculate({ opened(1, "t-x"), opened(2, "t-d"), opened(3, "foot"), opened(4, "firefox") })
      assert.are.same(box(0, 0, 1200, 1350), placed["t-x"])
      assert.are.same(box(1200, 0, 1200, 675), placed["t-d"])
      assert.are.same(box(1200, 675, 1200, 337), placed["foot"])
      assert.are.same(box(1200, 1012, 1200, 338), placed["firefox"])
    end)

    it("closes up an explicit overflow leaf with nothing in it", function()
      setup("h[x:1, v[d, *]:1]")
      local placed = recalculate({ opened(1, "t-x"), opened(2, "t-d") })
      assert.are.same(box(1200, 0, 1200, 1350), placed["t-d"])
    end)

    it("respects where the tree puts it", function()
      setup("h[*, x]")
      local placed = recalculate({ opened(1, "t-x"), opened(2, "foot") })
      assert.are.same(box(0, 0, 1200, 1350), placed["foot"])
      assert.are.same(box(1200, 0, 1200, 1350), placed["t-x"])
    end)

    it("sends a window whose slot is on another screen's tree to the overflow leaf", function()
      setup("h[x, *]")
      local placed = recalculate({ opened(1, "t-x"), opened(2, "t-d") })
      assert.are.same(box(1200, 0, 1200, 1350), placed["t-d"])
    end)
  end)
end)
