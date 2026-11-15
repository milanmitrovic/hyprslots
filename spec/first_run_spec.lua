-- Test seam S2: the first start of a fresh install (docs/design.md §4,
-- "First run"). With no config.lua, setup() writes a starter config.lua and
-- an empty slots.lua, never over a file that is there, and runs with zero
-- slots: a desk and a layout for the connected monitors, no trees.

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("a")
  file:close()
  return text
end

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local function errors_notified(hl)
  local out = {}
  for _, n in ipairs(hl.notifications) do
    if n.icon == 3 then -- hl_adapter's error icon
      out[#out + 1] = n.text
    end
  end
  return out
end

describe("first run", function()
  local hl, root, dir, hyprslots

  local function fresh_module()
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    return require("hyprslots")
  end

  local function setup()
    hyprslots = fresh_module()
    hyprslots.setup({ config_dir = dir })
    hl.run_timers() -- the new desk, a second later
    return hyprslots
  end

  local function state()
    return json.decode(hyprslots.api.call("state", "{}"))
  end

  local function call(name, args)
    return json.decode(hyprslots.api.call(name, json.encode(args)))
  end

  before_each(function()
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { focused = true }) } })
    _G.hl, _G.o = hl, hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
    root = os.tmpname()
    os.remove(root)
    assert(os.execute("mkdir -p '" .. root .. "'"))
    dir = root .. "/hyprslots"
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    os.execute("rm -rf '" .. root .. "'")
  end)

  it("writes a starter config.lua and an empty slots.lua where there is no config dir", function()
    setup()
    local config = read(dir .. "/config.lua")
    assert.is_string(config, "config.lua written")
    assert.matches('load_data%("slots.lua"%)', config)
    for _, field in ipairs({ "slots", "specs", "desks", "layouts", "monitor_names", "workspaces" }) do
      assert.matches(field .. " = data." .. field, config, nil, true)
    end
    local slots = read(dir .. "/slots.lua")
    assert.is_string(slots, "slots.lua written")
    assert.are.same({}, assert(load(slots, "slots.lua", "t", {}))())
  end)

  it("explains itself to someone who has never seen hyprslots", function()
    setup()
    local config = read(dir .. "/config.lua")
    assert.matches("named places", config)
    assert.matches("slots.lua", config)
    assert.matches("rewrites it", config)
    assert.matches("Lua", config)
  end)

  it("runs on it with zero slots: no error, a desk and a layout for the monitors", function()
    setup()
    local s = state()
    assert.is_nil(s.config_error)
    assert.is_nil(s.refused)
    assert.are.same({}, s.slots)
    assert.are.equal("headless-2", s.desk)
    assert.is_string(s.layout)
    assert.are.same({}, s.layouts[s.layout].default, "no slots, no tree")
    assert.are.same({}, errors_notified(hl), "no error notification")
    assert.is_true(s.config.editable, "the editor can edit it")
    assert.are.same({}, s.config.read_only)
  end)

  it("makes the desk without a notification while there are no slots", function()
    setup()
    assert.are.equal("headless-2", state().desk)
    assert.are.same({}, hl.notifications, "nothing to say before the first slot")
  end)

  it("lays out nothing with zero slots, and raises nothing", function()
    setup()
    local ctx = hl_stub.layout_ctx({ x = 0, y = 0, w = 1920, h = 1080 }, { hl_stub.window(1, "foot") })
    assert.has_no.errors(function() hl.layouts.slots.recalculate(ctx) end)
  end)

  it("puts the first slot made into the layout's tree, and saves it beside the starter", function()
    setup()
    local before = read(dir .. "/config.lua")
    local added = call("add_slot", { slot = "main" })
    assert.is_true(added.ok, added.error)
    assert.are.equal("m", added.key)
    local s = state()
    assert.are.equal("main", s.layouts[s.layout].default["1"].tree)
    assert.is_true(call("save", {}).ok)
    local saved = assert(load(read(dir .. "/slots.lua"), "slots.lua", "t", {}))()
    assert.are.same({ main = { key = "m" } }, saved.slots)
    assert.is_table(saved.desks["headless-2"])
    assert.are.equal(before, read(dir .. "/config.lua"), "config.lua is never rewritten")
  end)

  it("writes into a config dir that is there but empty", function()
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    setup()
    assert.is_string(read(dir .. "/config.lua"))
    assert.is_string(read(dir .. "/slots.lua"))
    assert.is_nil(state().config_error)
  end)

  it("keeps a slots.lua that is there, and writes only config.lua", function()
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local mine = "return { slots = { left = { key = 'l' } } }\n"
    write(dir .. "/slots.lua", mine)
    setup()
    assert.are.equal(mine, read(dir .. "/slots.lua"))
    assert.is_string(read(dir .. "/config.lua"))
    assert.are.same({ { name = "left", key = "l" } }, state().slots)
  end)

  it("never touches a config.lua that is there, even with no slots.lua beside it", function()
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local mine = 'local data = load_data("slots.lua")\nreturn { slots = data.slots }\n'
    write(dir .. "/config.lua", mine)
    setup()
    assert.are.equal(mine, read(dir .. "/config.lua"))
    assert.is_nil(read(dir .. "/slots.lua"), "slots.lua is written only with a starter config.lua")
    assert.matches("slots.lua", state().config_error)
  end)

  it("leaves both files alone when they are there", function()
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local config = 'local data = load_data("slots.lua")\nreturn { slots = data.slots, specs = data.specs }\n'
    local slots = "return { slots = { main = { key = 'm' } } }\n"
    write(dir .. "/config.lua", config)
    write(dir .. "/slots.lua", slots)
    setup()
    assert.are.equal(config, read(dir .. "/config.lua"))
    assert.are.equal(slots, read(dir .. "/slots.lua"))
  end)

  it("says so with an error notification when the starter cannot be written", function()
    write(root .. "/blocked", "a file where the config dir's parent should be")
    dir = root .. "/blocked/hyprslots"
    setup()
    local s = state()
    assert.matches("starter", s.config_error)
    assert.are.equal(1, #errors_notified(hl))
  end)
end)
