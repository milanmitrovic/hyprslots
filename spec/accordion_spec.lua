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

  describe("an accordion", function()
    local TREE = "h[a[x, y, z]:1, d:1]"

    local function members(window)
      local out = {}
      for _, member in ipairs(window.group and window.group.members or {}) do
        out[#out + 1] = member.class
      end
      return out
    end

    it("groups its windows once the events have returned, never while they run", function()
      setup(TREE)
      local x = opened(1, "t-x")
      opened(2, "t-z")
      opened(3, "t-y")
      opened(4, "t-d")
      assert.are.same({}, hl.dispatched_of("group.toggle"), "nothing inside the event")

      hl.run_timers()
      assert.are.same({ { window = "address:" .. x.address } }, hl.dispatched_of("group.toggle"))
      assert.are.same({ "t-x", "t-y", "t-z" }, members(x))
    end)

    it("is one target with the accordion's box", function()
      setup(TREE)
      local x, y, z, d = opened(1, "t-x"), opened(2, "t-y"), opened(3, "t-z"), opened(4, "t-d")
      hl_stub.group({ x, y, z }, 2)
      local placed = recalculate({ y, d })
      assert.are.same(box(0, 0, 1200, 1350), placed["t-y"])
      assert.are.same(box(1200, 0, 1200, 1350), placed["t-d"])
    end)

    it("gives a group showing a stranger the accordion's box, and takes the stranger out", function()
      setup(TREE)
      local x, y, d = opened(1, "t-x"), opened(2, "t-y"), opened(4, "t-d")
      local foot = opened(5, "foot")
      hl.run_timers()
      hl_stub.group({ x, y, foot }, 3)
      local placed = recalculate({ foot, d })
      assert.are.same(box(0, 0, 1200, 1350), placed["foot"])
      assert.are.same(box(1200, 0, 1200, 1350), placed["t-d"])

      hl.run_timers()
      assert.are.same({ { out_of_group = true, window = "address:" .. foot.address } },
        hl.dispatched_of("window.move"))
      assert.are.same({ "t-x", "t-y" }, members(x))
    end)

    it("puts members not grouped yet in its box, and groups them afterwards", function()
      setup(TREE)
      -- Mapped, but window.open has not reached hyprslots yet.
      local x, y, d = hl_stub.window(1, "t-x", { workspace = 3 }), hl_stub.window(2, "t-y", { workspace = 3 }),
        hl_stub.window(4, "t-d", { workspace = 3 })
      hl.windows = { x, y, d }
      local before = #hl.dispatched
      local placed = recalculate({ x, y, d })
      assert.are.same(box(0, 0, 1200, 1350), placed["t-x"])
      assert.are.same(box(0, 0, 1200, 1350), placed["t-y"])
      assert.are.equal(before, #hl.dispatched, "recalculate dispatches nothing")

      hl.run_timers()
      assert.are.same({ "t-x", "t-y" }, members(x))
    end)

    it("takes back a member the user dragged out", function()
      setup(TREE)
      local x, y, z = opened(1, "t-x"), opened(2, "t-y"), opened(3, "t-z")
      hl.run_timers()
      x.group:remove(z)
      recalculate({ x, z })
      hl.run_timers()
      assert.are.same({ "t-x", "t-y", "t-z" }, members(x))
    end)

    it("re-plans when a window moves onto the desk's workspace", function()
      setup(TREE)
      local x, y = opened(1, "t-x"), opened(2, "t-y")
      local foot = opened(5, "foot", 1)
      hl.run_timers()
      x.group:add(foot)
      foot.workspace = { id = 3, name = "3" }
      hl.emit("window.move_to_workspace", foot, foot.workspace)
      hl.run_timers()
      assert.are.same({ "t-x", "t-y" }, members(x))
      assert.is_nil(foot.group)
      assert.is_not_nil(y.group)
    end)

    it("leaves groups on a workspace that is no desk alone", function()
      setup(TREE)
      local p, q = opened(1, "foot", 5), opened(2, "firefox", 5)
      hl_stub.group({ p, q })
      hl.emit("window.move_to_workspace", p, p.workspace)
      hl.run_timers()
      assert.are.same({}, hl.dispatched_of("group.toggle"))
      assert.are.same({}, hl.dispatched_of("window.move"))
    end)

    it("leaves floating windows out of the group", function()
      setup(TREE)
      local x = opened(1, "t-x")
      local y = hl_stub.window(2, "t-y", { workspace = 3, floating = true })
      hl.windows[#hl.windows + 1] = y
      hl.emit("window.open", y)
      hl.run_timers()
      assert.are.same({}, hl.dispatched_of("group.toggle"))
      assert.is_nil(x.group)
    end)

    it("stops re-planning from layout passes that keep finding the same split", function()
      setup(TREE)
      local x, y = opened(1, "t-x"), opened(2, "t-y")
      hl.run_timers()
      -- Hyprland refuses every move: the group never forms.
      hl.group_adds = {}
      for _ = 1, 10 do
        x.group, y.group = nil, nil
        recalculate({ x, y })
        hl.run_timers()
      end
      assert.is_true(#hl.dispatched_of("group.toggle") <= 4)
      assert.matches("accordion", hyprslots.dump())
    end)
  end)
end)
