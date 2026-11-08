-- scroll[...] branches on Hyprland's scrolling layout (scroll.lua): the pure
-- column-order plan (S3), and the engine putting a scroll desk's workspace on
-- the scrolling layout, keeping its columns in slot order and full width
-- (S2, against the stub's scrolling simulation).

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")
local scroll = require("hyprslots.scroll")

-- Apply swaps ({ a, b } addresses) to a list of addresses.
local function swapped(order, swaps)
  local out = {}
  for i, address in ipairs(order) do
    out[i] = address
  end
  for _, swap in ipairs(swaps) do
    for i, address in ipairs(out) do
      if address == swap.a then
        out[i] = swap.b
      elseif address == swap.b then
        out[i] = swap.a
      end
    end
  end
  return out
end

local function columns(list)
  local out = {}
  for i, entry in ipairs(list) do
    out[i] = { address = entry[1], slot = entry[2] }
  end
  return out
end

local function addresses(list)
  local out = {}
  for i, entry in ipairs(list) do
    out[i] = entry[1]
  end
  return out
end

describe("scroll.plan", function()
  local SLOTS = { "left", "main", "right" }

  it("makes no swap when the columns are in slot order", function()
    assert.are.same({}, scroll.plan(SLOTS, columns({ { "w1", "left" }, { "w2", "main" }, { "w3", "right" } })))
  end)

  it("puts the columns in slot order", function()
    local current = { { "w3", "right" }, { "w1", "left" }, { "w2", "main" } }
    local swaps = scroll.plan(SLOTS, columns(current))
    assert.are.same({ "w1", "w2", "w3" }, swapped(addresses(current), swaps))
    assert.are.equal(2, #swaps)
  end)

  it("closes up around empty slots", function()
    local current = { { "w3", "right" }, { "w1", "left" } }
    assert.are.same({ "w1", "w3" }, swapped(addresses(current), scroll.plan(SLOTS, columns(current))))
  end)

  it("puts windows with no slot after the slotted ones, in the order they are in", function()
    local current = { { "x1" }, { "w2", "main" }, { "x2" }, { "w1", "left" } }
    assert.are.same({ "w1", "w2", "x1", "x2" }, swapped(addresses(current), scroll.plan(SLOTS, columns(current))))
  end)

  it("makes no swap for windows with no slot alone", function()
    assert.are.same({}, scroll.plan(SLOTS, columns({ { "x2" }, { "x1" } })))
  end)
end)

describe("scroll.order", function()
  it("reads the columns left to right, then down a column", function()
    local windows = {
      { address = "c", column = 2, row = 0 },
      { address = "a", column = 0, row = 0 },
      { address = "b2", column = 1, row = 1 },
      { address = "b1", column = 1, row = 0 },
    }
    local out = {}
    for i, window in ipairs(scroll.order(windows)) do
      out[i] = window.address
    end
    assert.are.same({ "a", "b1", "b2", "c" }, out)
  end)
end)

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, arrangements = data.arrangements, scroll = %s }
]]

-- Desk 3: scroll[left, main, right] on the laptop screen; desk 4: a split.
local SLOTS = [[
return {
  slots = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
    [4] = { a = "t-a", b = "t-b" },
  },
  arrangements = {
    laptop = {
      screens = { lap = "eDP-1" },
      desks = {
        [3] = { lap = "scroll[left, main, right]" },
        [4] = { lap = "h[a, b]" },
      },
    },
  },
}
]]

describe("a scroll branch", function()
  local hl, dirs, hyprslots, state_home

  local function write(dir, name, content)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local file = assert(io.open(dir .. "/" .. name, "w"))
    file:write(content)
    file:close()
  end

  local function tmpdir()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    dirs[#dirs + 1] = dir
    return dir
  end

  -- Omarchy's saved mode for a workspace (what Super+L / its toggle writes).
  local function saved_mode(id, mode)
    write(state_home .. "/omarchy/workspace-layouts", id .. ".lua",
      string.format('o.workspace_mode({ workspace = "%d", mode = "%s" })\n', id, mode))
  end

  local function setup(scroll_config)
    local dir = tmpdir()
    write(dir, "config.lua", string.format(CONFIG, scroll_config or "nil"))
    write(dir, "slots.lua", SLOTS)
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    hyprslots = require("hyprslots")
    assert(hyprslots.setup({ config_dir = dir }))
    hl.emit("hyprland.start")
    hl.run_timers()
  end

  local function window(id, class, ws)
    return hl_stub.window(id, class, { workspace = hl.get_workspace(ws) or hl.add_workspace(ws, "eDP-1") })
  end

  -- A window opening on workspace `ws` (where a window rule put it).
  local function open(id, class, ws)
    local w = window(id, class, ws)
    hl.open(w)
    hl.emit("window.open", w)
    return w
  end

  local function focus(w)
    hl.active_window = w
    hl.emit("window.active", w)
  end

  local function swaps()
    return hl.dispatched_of("window.swap")
  end

  local function layout_msgs()
    local out = {}
    for _, msg in ipairs(hl.dispatched_of("layout")) do
      out[#out + 1] = msg
    end
    return out
  end

  local function call(name, args)
    return json.decode(hyprslots.api.call(name, args or "{}"))
  end

  before_each(function()
    dirs = {}
    state_home = tmpdir()
    package.loaded["default.hypr.paths"] = { state_home = state_home }
    hl = hl_stub.new({ monitors = { hl_stub.monitor("eDP-1", { focused = true }) } })
    hl_stub.simulate(hl)
    hl_stub.scrolling(hl)
    _G.hl, _G.o = hl, hl_stub.omarchy({ ["eDP-1"] = 0 })
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    package.loaded["default.hypr.paths"] = nil
    for _, dir in ipairs(dirs) do
      os.execute("rm -rf '" .. dir .. "'")
    end
  end)

  local function rule_for(id)
    local layout
    for _, spec in ipairs(hl.workspace_rules) do
      if spec.workspace == tostring(id) then
        layout = spec.layout
      end
    end
    return layout
  end

  it("puts its workspace on Hyprland's scrolling layout, and a split's on lua:slots", function()
    setup()
    assert.are.equal("scrolling", rule_for(3))
    assert.are.equal("lua:slots", rule_for(4))
  end)

  it("keeps a workspace's saved Omarchy mode when the arrangement changes at runtime", function()
    hl.monitors = {}
    setup()
    saved_mode(3, "dwindle")
    local before = #hl.workspace_rules
    hl.monitors = { hl_stub.monitor("eDP-1", { focused = true }) }
    hl.emit("monitor.added")
    hl.run_timers()
    hl.run_timers()
    local after = {}
    for i = before + 1, #hl.workspace_rules do
      after[hl.workspace_rules[i].workspace] = hl.workspace_rules[i].layout
    end
    assert.is_nil(after["3"])
  end)

  it("puts the columns in slot order once windows have opened", function()
    setup()
    open(1, "t-right", 3)
    open(2, "t-left", 3)
    open(3, "t-main", 3)
    assert.are.same({}, swaps()) -- deferred: nothing inside the events
    hl.run_timers()
    assert.are.same({ "t-left", "t-main", "t-right" }, hl.column_classes(3))
  end)

  it("puts windows with no slot after the slotted ones", function()
    setup()
    open(1, "foot", 3)
    open(2, "t-main", 3)
    open(3, "t-left", 3)
    hl.run_timers()
    assert.are.same({ "t-left", "t-main", "foot" }, hl.column_classes(3))
  end)

  it("swaps without the cursor warping, and puts the setting back", function()
    hl.config({ cursor = { no_warps = false } })
    setup()
    open(1, "t-right", 3)
    open(2, "t-left", 3)
    hl.run_timers()
    local seen = {}
    for _, values in ipairs(hl.config_calls) do
      if values.cursor then
        seen[#seen + 1] = values.cursor.no_warps
      end
    end
    assert.are.same({ false, true, false }, seen)
    assert.is_false(hl.get_config("cursor.no_warps"))
  end)

  it("leaves the columns of a workspace taken out of slots by Super+L alone", function()
    setup()
    saved_mode(3, "scrolling") -- side-by-side or full-width, the user's own
    open(1, "t-right", 3)
    open(2, "t-left", 3)
    hl.run_timers()
    assert.are.same({}, swaps())
    assert.are.same({ "t-right", "t-left" }, hl.column_classes(3))
  end)

  it("leaves a workspace whose tiled layout is not scrolling alone", function()
    setup()
    local ws = hl.add_workspace(3, "eDP-1")
    ws.tiled_layout = "dwindle"
    open(1, "t-right", 3)
    open(2, "t-left", 3)
    hl.run_timers()
    assert.are.same({}, swaps())
  end)

  it("does not reorder on a focus change, so a column the user moved stays", function()
    setup()
    local left = open(1, "t-left", 3)
    local main = open(2, "t-main", 3)
    hl.run_timers()
    hl.dispatch(hl.dsp.window.swap({ window = "address:" .. left.address, target = "address:" .. main.address }))
    local before = #swaps()
    focus(left)
    hl.run_timers()
    assert.are.equal(before, #swaps())
    assert.are.same({ "t-main", "t-left" }, hl.column_classes(3))
  end)

  it("puts the columns back in slot order on a desk switch", function()
    setup()
    local left = open(1, "t-left", 3)
    local main = open(2, "t-main", 3)
    hl.run_timers()
    hl.dispatch(hl.dsp.window.swap({ window = "address:" .. left.address, target = "address:" .. main.address }))
    call("desk", '{"desk": 3}')
    hl.run_timers()
    assert.are.same({ "t-left", "t-main" }, hl.column_classes(3))
  end)

  it("makes new columns full width when their workspace is focused, then keeps the view on the focus", function()
    setup()
    local main = open(1, "t-main", 3)
    focus(main)
    open(2, "t-left", 3)
    hl.run_timers()
    assert.are.same({ "colresize all 0.99", "fit_into_view" }, layout_msgs())
    assert.are.equal(0.99, hl.widths[main.address])
  end)

  it("widens a hidden workspace's new columns once it is shown", function()
    setup()
    local other = open(9, "foot", 1)
    focus(other)
    hl.run_timers()
    local main = open(1, "t-main", 3)
    hl.run_timers()
    assert.are.same({}, layout_msgs())
    focus(main)
    hl.emit("workspace.active", main.workspace)
    hl.run_timers()
    assert.are.same({ "colresize all 0.99", "fit_into_view" }, layout_msgs())
  end)

  it("leaves a column the user resized alone on later passes", function()
    setup()
    local main = open(1, "t-main", 3)
    focus(main)
    hl.run_timers()
    local before = #layout_msgs()
    hl.widths[main.address] = 0.6 -- the user's resize
    focus(main)
    hl.emit("workspace.active", main.workspace)
    hl.run_timers()
    assert.are.equal(before, #layout_msgs())
    assert.are.equal(0.6, hl.widths[main.address])
  end)

  describe("in the api", function()
    it("says which layout each desk workspace gets", function()
      setup()
      local state = call("state")
      assert.are.equal("scrolling", state.workspaces["3"].layout)
      assert.are.equal("lua:slots", state.workspaces["4"].layout)
    end)

    it("describes each scroll workspace: its columns, whether hyprslots keeps them, whether they are in order", function()
      setup()
      local right = open(1, "t-right", 3)
      local left = open(2, "t-left", 3)
      local described = call("state").scroll
      assert.are.equal(1, #described)
      local ws = described[1]
      assert.are.equal(3, ws.workspace)
      assert.are.equal(3, ws.desk)
      assert.are.equal("lap", ws.role)
      assert.are.same({ "left", "main", "right" }, ws.slots)
      assert.are.equal("scrolling", ws.layout)
      assert.is_true(ws.managed)
      assert.are.same({ right.address, left.address }, ws.columns)
      assert.are.same({ left = left.address, right = right.address }, ws.members)
      assert.is_false(ws.in_order)
      hl.run_timers()
      assert.is_true(call("state").scroll[1].in_order)
      saved_mode(3, "scrolling")
      assert.is_false(call("state").scroll[1].managed)
    end)

    it("arranges now on request (Super+L entering slots)", function()
      setup()
      local main = open(1, "t-main", 3)
      focus(main)
      open(2, "t-left", 3)
      local reply = call("arrange")
      assert.is_true(reply.ok)
      assert.are.equal(1, reply.swaps)
      assert.are.same({ 3 }, reply.widened)
      assert.are.same({ "t-left", "t-main" }, hl.column_classes(3))
    end)

    it("records a scroll workspace's columns as its slot order", function()
      setup()
      local left = open(1, "t-left", 3)
      local main = open(2, "t-main", 3)
      local right = open(3, "t-right", 3)
      hl.run_timers()
      hl.dispatch(hl.dsp.window.swap({ window = "address:" .. left.address, target = "address:" .. right.address }))
      local reply = call("record", '{"workspace": 3}')
      assert.is_true(reply.ok, reply.error)
      assert.are.equal("scroll[right, main, left]", reply.tree)
      assert.is_true(reply.applied)
      assert.are.same({}, reply.missing)
      assert.are.equal("scroll[right, main, left]", call("state").arrangements.laptop.desks["3"].lap.tree)
      local _ = main
    end)

    it("records only the slots present, saying which are missing", function()
      setup()
      open(1, "t-right", 3)
      open(2, "t-left", 3)
      hl.run_timers()
      local reply = call("record", '{"workspace": 3}')
      assert.are.equal("scroll[left, right]", reply.tree)
      assert.are.same({ "main" }, reply.missing)
      assert.is_false(reply.applied)
    end)
  end)

  it("widens again the columns of windows that come back after their workspace stopped scrolling", function()
    setup()
    local main = open(1, "t-main", 3)
    focus(main)
    hl.run_timers()
    assert.are.equal(2, #layout_msgs())
    assert.is_true(call("set_tree", '{"desk": 3, "role": "lap", "tree": "h[left, main, right]"}').ok)
    hl.run_timers()
    assert.are.equal("lua:slots", hl.get_workspace(3).tiled_layout)
    assert.is_true(call("set_tree", '{"desk": 3, "role": "lap", "tree": "scroll[left, main, right]"}').ok)
    hl.run_timers()
    assert.are.equal("scrolling", hl.get_workspace(3).tiled_layout)
    assert.are.same({ "colresize all 0.99", "fit_into_view", "colresize all 0.99", "fit_into_view" }, layout_msgs())
  end)

  it("uses the configured column width", function()
    setup("{ width = 0.95 }")
    local main = open(1, "t-main", 3)
    focus(main)
    hl.run_timers()
    assert.are.equal("colresize all 0.95", layout_msgs()[1])
  end)
end)
