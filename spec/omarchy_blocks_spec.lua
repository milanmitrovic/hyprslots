-- Test seam S2: the active desk's screens own Omarchy's workspace blocks
-- (docs/design.md §5), against Omarchy's real monitor-workspaces.lua on the
-- stubbed hl: screen i holds block i-1 in Omarchy's state file, a monitor
-- that is off or unplugged holds none, and the workspaces follow, windows
-- and slot assignments with them.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local OMARCHY = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/monitor-workspaces.lua"
local ODYSSEY = "Samsung Electric Company Odyssey G95NC HNTW700044"

local CONFIG = [[
return {
  slots = { main = {}, side = {} },
  specs = {
    [1] = { main = "t-one" },
    [2] = { main = "t-two" },
    [3] = { main = "t-main", side = "t-side" },
  },
  desks = {
    ultrawide = { monitors = { "]] .. ODYSSEY .. [[" }, layout = "wide" },
    laptop = { monitors = { "eDP-1" }, layout = "wide" },
    docked = { monitors = { "eDP-1", "]] .. ODYSSEY .. [[" }, layout = "dual" },
  },
  layouts = {
    wide = { screens = 1, default = { [1] = "h[main, side]" } },
    dual = { screens = 2, default = { [1] = "main", [2] = "side" } },
  },
}
]]

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

local have_omarchy = read(OMARCHY) ~= nil
local describe_omarchy = have_omarchy and describe or pending

describe_omarchy("Omarchy's workspace blocks under the active desk", function()
  local hl, hyprslots, state_dir, edp, dp

  local function state_file()
    return read(state_dir .. "/omarchy/monitor-workspaces")
  end

  -- Omarchy's monitor-workspaces, loaded the way hyprland.lua loads it: before
  -- hyprslots, its blocks read from the state file.
  local function load_omarchy(blocks_text)
    os.execute("mkdir -p '" .. state_dir .. "/omarchy'")
    write(state_dir .. "/omarchy/monitor-workspaces", blocks_text)
    package.loaded["default.hypr.paths"] = { state_home = state_dir }
    _G.o = { bind_expressions = {}, shell_quote = function(value) return "'" .. value .. "'" end }
    dofile(OMARCHY)
  end

  local function workspace(id, monitor)
    local ws = { id = id, name = tostring(id), monitor = monitor, windows = 0 }
    hl.workspaces[#hl.workspaces + 1] = ws
    return ws
  end

  local function window_on(n, class, id)
    local ws = hl.get_workspace(id)
    local window = hl_stub.window(n, class, { workspace = ws })
    ws.windows = ws.windows + 1
    hl.windows[#hl.windows + 1] = window
    return window
  end

  local function workspace_of(class)
    for _, window in ipairs(hl.windows) do
      if window.class == class then
        return window.workspace.id
      end
    end
  end

  -- "id@monitor" for every workspace holding windows, by id.
  local function occupied()
    local list = {}
    for _, ws in ipairs(hl.workspaces) do
      if ws.id > 0 and ws.windows > 0 then
        list[#list + 1] = ws
      end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local out = {}
    for _, ws in ipairs(list) do
      out[#out + 1] = ws.id .. "@" .. (ws.monitor and ws.monitor.name or "?")
    end
    return table.concat(out, " ")
  end

  local function assignments()
    return json.encode(engine.state(hyprslots).assignments, { keyorder = {} })
  end

  before_each(function()
    state_dir = os.tmpname()
    os.remove(state_dir)
    edp = hl_stub.monitor("eDP-1", { id = 0, x = 0, y = 0 })
    dp = hl_stub.monitor("DP-2", { id = 2, x = 1728, y = 0, description = ODYSSEY, focused = true })
    hl = hl_stub.simulate(hl_stub.new({ monitors = { dp } }))
    _G.hl = hl
  end)

  after_each(function()
    engine.cleanup()
    package.loaded["default.hypr.paths"] = nil
    os.execute("rm -rf '" .. state_dir .. "'")
  end)

  describe("with the laptop panel turned off and its workspaces left on it", function()
    before_each(function()
      -- The live case: eDP-1 kept block 0 and its workspaces; DP-2 got 11-20.
      load_omarchy("0\t\teDP-1\n1\tDP-2\t" .. ODYSSEY .. "\n2\t\tFALLBACK\n")
      workspace(1, edp)
      workspace(5, edp)
      dp.active_workspace = workspace(11, dp)
      workspace(12, dp)
      window_on(1, "u-one", 1)
      window_on(2, "u-five", 5)
      window_on(3, "t-one", 11)
      window_on(4, "t-two", 12)
      hyprslots = engine.setup(CONFIG)
      assert.are.equal("ultrawide", engine.state(hyprslots).desk)
    end)

    it("gives the desk's only screen block 0 on the next reconcile, and every workspace 1-9 on it", function()
      local before = assignments()
      hl.emit("config.reloaded")
      hl.run_timers()

      assert.are.equal("0\tDP-2\t" .. ODYSSEY .. "\n", state_file())
      assert.are.equal("1@DP-2 2@DP-2 5@DP-2", occupied())
      assert.are.equal(1, workspace_of("u-one"))
      assert.are.equal(1, workspace_of("t-one"))
      assert.are.equal(2, workspace_of("t-two"))
      assert.are.equal(5, workspace_of("u-five"))
      assert.are.equal(before, assignments())
      assert.is_true(dp.active_workspace.id >= 1 and dp.active_workspace.id <= 9)
    end)

    it("leaves Omarchy's numbering alone while hyprslots is off", function()
      -- hyprmoncfg's workspace planner switched Omarchy's workspaces off.
      o.workspaces.enabled = false
      local blocks = state_file()
      hl.emit("config.reloaded")
      hl.run_timers()
      assert.are.equal(blocks, state_file())
      assert.are.same({ 1, 11, 12, 5 }, { workspace_of("u-one"), workspace_of("t-one"), workspace_of("t-two"),
        workspace_of("u-five") })
    end)
  end)

  it("keeps Omarchy's numbering while no desk is the connected monitors", function()
    load_omarchy("0\t\teDP-1\n1\tDP-2\t" .. ODYSSEY .. "\n")
    local other = hl_stub.monitor("HDMI-A-1", { id = 3, x = 0, y = 0, description = "Some Projector" })
    hl.monitors = { other, dp }
    dp.active_workspace = workspace(12, dp)
    window_on(1, "t-two", 12)
    hyprslots = engine.setup(CONFIG)
    hl.emit("config.reloaded")
    assert.is_nil(engine.state(hyprslots).desk)
    assert.matches("1\tDP%-2\t", state_file())
    assert.are.equal(12, workspace_of("t-two"))
  end)

  describe("docked, when the laptop panel is turned off and on again", function()
    before_each(function()
      load_omarchy("0\teDP-1\teDP-1\n1\tDP-2\t" .. ODYSSEY .. "\n")
      hl.monitors = { edp, dp }
      edp.active_workspace = workspace(3, edp)
      dp.active_workspace = workspace(13, dp)
      workspace(17, dp)
      window_on(1, "t-main", 3)
      window_on(2, "t-side", 13)
      window_on(3, "u-free", 17)
      hyprslots = engine.setup(CONFIG)
      assert.are.equal("docked", engine.state(hyprslots).desk)
    end)

    -- Hyprland moves a disabled monitor's workspaces to another and reports
    -- monitor.removed; Omarchy reconciles from a timer, hyprslots after it.
    local function panel_off()
      hl.monitors = { dp }
      for _, ws in ipairs(hl.workspaces) do
        if ws.monitor == edp then
          ws.monitor = dp
        end
      end
      hl.emit("monitor.removed", edp)
      for _ = 1, 3 do
        hl.run_timers()
      end
    end

    it("gives the Odyssey block 0 alone, every window under its own number on it", function()
      local before = assignments()
      panel_off()
      assert.are.equal("ultrawide", engine.state(hyprslots).desk)
      assert.are.equal("0\tDP-2\t" .. ODYSSEY .. "\n", state_file())
      assert.are.equal("3@DP-2 7@DP-2", occupied())
      assert.are.same({ 3, 3, 7 }, { workspace_of("t-main"), workspace_of("t-side"), workspace_of("u-free") })
      assert.are.equal(before, assignments())
    end)

    it("gives the screens their order back when the panel is on again: eDP-1 1-10, DP-2 11-20", function()
      local before = assignments()
      panel_off()
      hl.monitors = { edp, dp }
      edp.active_workspace = nil
      hl.emit("monitor.added", edp)
      for _ = 1, 3 do
        hl.run_timers()
      end
      assert.are.equal("docked", engine.state(hyprslots).desk)
      assert.are.equal("0\teDP-1\teDP-1\n1\tDP-2\t" .. ODYSSEY .. "\n", state_file())
      assert.are.same({ 3, 13, 17 }, { workspace_of("t-main"), workspace_of("t-side"), workspace_of("u-free") })
      assert.are.equal("eDP-1", hl.get_workspace(3).monitor.name)
      assert.are.equal("DP-2", hl.get_workspace(13).monitor.name)
      assert.are.equal("DP-2", hl.get_workspace(17).monitor.name)
      assert.are.equal(before, assignments())
    end)
  end)
end)

describe("Omarchy's workspace blocks out of reach", function()
  after_each(engine.cleanup)

  it("leaves the numbering to Omarchy and says so once", function()
    local hl, o = engine.stub({ "HEADLESS-3" }, { ["HEADLESS-3"] = 1 })
    hl_stub.simulate(hl)
    hl.add_workspace(13, "HEADLESS-3")
    hl.windows[1] = hl_stub.window(1, "t-main", { workspace = hl.get_workspace(13) })
    hl.get_workspace(13).windows = 1
    -- A monitor-workspaces.lua of another shape: no local block table behind workspace_id.
    o.workspaces.workspace_id = function(monitor, slot)
      return (monitor.name == "HEADLESS-3" and 1 or 0) * 10 + slot
    end
    local hyprslots = engine.setup([[
return {
  slots = { main = {} },
  specs = { [3] = { main = "t-main" } },
  desks = { solo = { monitors = { "HEADLESS-3" }, layout = "one" } },
  layouts = { one = { screens = 1, default = { [1] = "main" } } },
}
]])
    hl.emit("config.reloaded")
    hl.emit("config.reloaded")
    assert.are.equal(13, hl.windows[1].workspace.id)
    local warnings = 0
    for line in hyprslots.dump():gmatch("[^\n]+") do
      if line:match("warn workspace numbers stay Omarchy's") then
        warnings = warnings + 1
      end
    end
    assert.are.equal(1, warnings)
  end)
end)
