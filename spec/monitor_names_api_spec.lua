-- Test seam S2: monitors by a short name in the editor (docs/design.md §8,
-- §9): state names each monitor (Built-in, the model, or the user's label),
-- a desk's monitors too, and set_monitor_name labels one; labels are saved
-- in slots.lua and never change which desk is active.

local engine = require("helpers.engine")
local json = require("hyprslots.dkjson")

local ODYSSEY = "Samsung Electric Company Odyssey G95NC HNTW700044"
local BLOCKS = { ["eDP-1"] = 0, ["DP-1"] = 1 }

local DOCKED = [[
return {
  slots = { left = { key = "l" }, main = { key = "m" }, right = { key = "r" } },
  desks = {
    docked = { monitors = { "eDP-1", "]] .. ODYSSEY .. [[" }, layout = "dual" },
    office = { monitors = { "eDP-1", "Dell Inc. DELL U2720Q 1ABC" }, layout = "dual" },
  },
  layouts = { dual = { screens = 2, default = { [1] = "h[left, main, right]" } } },
}
]]

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

describe("monitor names", function()
  local hl, hyprslots

  local function state()
    return engine.state(hyprslots)
  end

  local function call(name, args)
    return engine.call(hyprslots, name, json.encode(args or {}))
  end

  local function ok(name, args)
    local reply = call(name, args)
    assert.is_true(reply.ok, reply.error)
    return reply
  end

  local function setup(slots, config)
    hl = engine.stub({ "eDP-1", "DP-1" }, BLOCKS)
    hl.monitors[2].description = ODYSSEY
    hl.monitors[2].serial = "HNTW700044"
    hyprslots = engine.setup(slots or DOCKED, config)
  end

  local function monitor(s, connector)
    for _, m in ipairs(s.monitors) do
      if m.name == connector then
        return m
      end
    end
  end

  before_each(function() setup() end)
  after_each(engine.cleanup)

  describe("in state", function()
    it("names the laptop panel Built-in and the Samsung by its model", function()
      local s = state()
      assert.are.equal("docked", s.desk)
      assert.are.equal("Built-in", monitor(s, "eDP-1").display)
      assert.are.equal("eDP-1", monitor(s, "eDP-1").selector)
      assert.are.equal("Odyssey G95NC", monitor(s, "DP-1").display)
      assert.are.equal(ODYSSEY, monitor(s, "DP-1").selector)
      assert.is_nil(monitor(s, "DP-1").label)
    end)

    it("names each of a desk's monitors, the ones not connected too", function()
      local s = state()
      assert.are.same({ "Built-in", "Odyssey G95NC" }, s.desks.docked.displays)
      assert.are.same({ "Built-in", "DELL U2720Q 1ABC" }, s.desks.office.displays)
      assert.are.same({}, s.monitor_names)
    end)
  end)

  describe("set_monitor_name", function()
    it("labels a monitor by the selector a desk names it by, in memory; desks still match", function()
      local reply = ok("set_monitor_name", { selector = ODYSSEY, name = "Samsung" })
      assert.are.equal(ODYSSEY, reply.selector)
      assert.are.equal("Samsung", reply.name)
      assert.are.equal("Samsung", reply.display)
      local s = state()
      assert.are.equal("Samsung", monitor(s, "DP-1").display)
      assert.are.equal("Samsung", monitor(s, "DP-1").label)
      assert.are.same({ "Built-in", "Samsung" }, s.desks.docked.displays)
      assert.are.same({ [ODYSSEY] = "Samsung" }, s.monitor_names)
      assert.are.equal("docked", s.desk)
      assert.are.same({ "eDP-1", ODYSSEY }, s.desks.docked.monitors)
      assert.is_true(s.dirty)
    end)

    it("trims the name; an empty one clears the label, back to the automatic name", function()
      assert.are.equal("Wide", ok("set_monitor_name", { selector = ODYSSEY, name = "  Wide " }).name)
      local reply = ok("set_monitor_name", { selector = ODYSSEY, name = "" })
      assert.are.equal("", reply.name)
      assert.are.equal("Odyssey G95NC", reply.display)
      local s = state()
      assert.are.equal("Odyssey G95NC", monitor(s, "DP-1").display)
      assert.are.same({}, s.monitor_names)
    end)

    it("labels a monitor of a desk that is not connected", function()
      ok("set_monitor_name", { selector = "Dell Inc. DELL U2720Q 1ABC", name = "Office" })
      assert.are.same({ "Built-in", "Office" }, state().desks.office.displays)
    end)

    it("refuses a monitor no desk names and none connected is, and a name that is not one line of text", function()
      assert.matches("no monitor 'Acme'", call("set_monitor_name", { selector = "Acme", name = "x" }).error)
      assert.matches("selector", call("set_monitor_name", { name = "x" }).error)
      assert.matches("one line", call("set_monitor_name", { selector = "eDP-1", name = "a\nb" }).error)
      assert.matches("text", call("set_monitor_name", { selector = "eDP-1", name = 3 }).error)
      assert.is_false(state().dirty)
    end)

    it("is saved in slots.lua, and read again after a reload by a config.lua that does not pass it on", function()
      ok("set_monitor_name", { selector = ODYSSEY, name = "Samsung" })
      local reply = ok("save")
      assert.matches('monitor_names = {%s*%["' .. ODYSSEY:gsub("%p", "%%%0") .. '"%] = "Samsung",%s*}',
        read(reply.path))
      assert.is_false(state().dirty)
      ok("reload")
      local s = state()
      assert.are.equal("Samsung", monitor(s, "DP-1").display)
      assert.is_false(s.dirty)
    end)

    it("refuses labels config.lua sets in code", function()
      setup(DOCKED, [[
local data = load_data("slots.lua")
return { slots = data.slots, desks = data.desks, layouts = data.layouts, monitor_names = { ["eDP-1"] = "Panel" } }
]])
      assert.are.equal("Panel", monitor(state(), "eDP-1").display)
      assert.matches("your config", call("set_monitor_name", { selector = "eDP-1", name = "Laptop" }).error)
    end)
  end)
end)
