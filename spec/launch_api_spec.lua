-- Test seam S2: launching the apps a workspace's empty slots wait for
-- (docs/design.md §9, Launching apps): each workspace's launch setting
-- (never, on demand, at login), the command each spec launches with (config
-- or the app's desktop entry, stored with the spec), `launch_missing`, and
-- the launch at Hyprland's start.

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]]

local SLOTS = [[
return {
  slots = { main = { key = "m" }, aside = { key = "a" }, notes = { key = "n" } },
  specs = { [3] = { main = "foot", aside = "t-aside", notes = "foot/notes" }, [5] = { main = "foot" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "h[main, aside, notes]" } } },
  launch = { [5] = "at_login" },
}
]]

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

describe("launching apps", function()
  local hl, dir, apps, hyprslots

  local function fresh_module()
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    return require("hyprslots")
  end

  local function setup(slots, config)
    write(dir .. "/config.lua", config or CONFIG)
    write(dir .. "/slots.lua", slots or SLOTS)
    hyprslots = fresh_module()
    hyprslots.setup({ config_dir = dir, desktop_dirs = { apps } })
  end

  local function call(name, args)
    return json.decode(hyprslots.api.call(name, args and json.encode(args) or "{}"))
  end

  local function launched()
    return hl.execs or {}
  end

  before_each(function()
    dir = os.tmpname()
    os.remove(dir)
    apps = dir .. "/applications"
    assert(os.execute("mkdir -p '" .. apps .. "'"))
    write(apps .. "/foot.desktop", "[Desktop Entry]\nName=Foot\nExec=foot %U\n")
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2", { id = 0, focused = true }) } })
    _G.hl = hl
    _G.o = hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
    hl.workspaces = { { id = 3, tiled_layout = "lua:slots" } }
    hl.active_workspace = hl.workspaces[1]
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    os.execute("rm -rf '" .. dir .. "'")
  end)

  describe("state", function()
    it("says each workspace's launch setting, never by default", function()
      setup()
      local state = call("state")
      assert.equal("never", state.launch["3"])
      assert.equal("at_login", state.launch["5"])
      assert.equal("never", state.launch["9"])
    end)

    it("says how each spec launches on a workspace that launches: its desktop entry, config's command, or why not", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"')), [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts,
  launch_commands = { ["foot/notes"] = "foot -T notes" } }
]])
      local status = call("state").launch_status["3"]
      assert.same({ command = "foot", source = "desktop", desktop = "foot" }, status.main)
      assert.same({ command = "foot -T notes", source = "config" }, status.notes)
      assert.same({ reason = "can't launch: set a command" }, status.aside)
      assert.is_nil(call("state").launch_status["5"], "workspace 5 launches nothing")
    end)
  end)

  describe("config", function()
    it("refuses a launch setting, a command or a desktop id that is none, with its path", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "always"')))
      assert.matches('launch%[3%]: must be "never", "on_demand" or "at_login"', call("state").config_error)
      setup(nil, [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts,
  launch_commands = { ["foot/"] = "foot" }, desktop_ids = { foot = "a/b" } }
]])
      local err = call("state").config_error
      assert.matches("launch_commands%[foot/%]: spec 'foot/'", err)
      assert.matches("desktop_ids%.foot: must be a desktop id", err)
    end)
  end)

  describe("set_launch", function()
    it("sets a workspace's launch setting, as an unsaved edit save writes", function()
      setup()
      local reply = call("set_launch", { workspace = 3, mode = "on_demand" })
      assert.is_true(reply.ok, reply.error)
      local state = call("state")
      assert.equal("on_demand", state.launch["3"])
      assert.is_true(state.dirty)
      assert.is_true(call("save").ok)
      assert.matches('%[3%] = "on_demand"', read(dir .. "/slots.lua"))
    end)

    it("never takes the workspace out of the saved settings", function()
      setup()
      assert.is_true(call("set_launch", { workspace = 5, mode = "never" }).ok)
      assert.is_true(call("save").ok)
      assert.not_matches("at_login", read(dir .. "/slots.lua"))
      assert.equal("never", call("state").launch["5"])
    end)

    it("refuses another setting, and one config.lua sets in code", function()
      setup()
      assert.matches("never, on_demand or at_login", call("set_launch", { workspace = 3, mode = "always" }).error)
      setup(nil, [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts, launch = { [3] = "never" } }
]])
      assert.matches("your config", call("set_launch", { workspace = 3, mode = "on_demand" }).error)
    end)
  end)

  describe("launch_missing", function()
    it("launches the apps of the workspace's empty slots there, silently, and says what it could not", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"')))
      local reply = call("launch_missing", { workspace = 3 })
      assert.is_true(reply.ok, reply.error)
      assert.same({ { slot = "main", command = "foot" } }, reply.launched)
      assert.same({ { slot = "aside", reason = "can't launch: set a command" },
        { slot = "notes", reason = "can't launch: set a command" } }, reply.cannot)
      assert.same({ { cmd = "foot", rules = { workspace = "3 silent" } } }, launched())
    end)

    it("not again while that app is on its way, nor for a window already open", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"')))
      local first = call("launch_missing", { workspace = 3 })
      assert.same({}, first.open)
      assert.same({}, first.pending)
      local reply = call("launch_missing", { workspace = 3 })
      assert.same({}, reply.launched)
      assert.same({ "main" }, reply.pending)
      assert.same({}, reply.open)
      assert.equal(1, #launched())

      hl.windows = { hl_stub.window(1, "foot", { workspace = 7 }) }
      hyprslots = fresh_module()
      hyprslots.setup({ config_dir = dir, desktop_dirs = { apps } })
      -- setup takes that window into main: the slot is not empty.
      reply = call("launch_missing", { workspace = 3 })
      assert.same({}, reply.launched)
      assert.same({}, reply.open)
      assert.same({}, reply.pending)

      -- Out of its slot it is open, and still counts for main.
      assert.is_true(call("unassign", { address = "0x1001" }).ok)
      reply = call("launch_missing", { workspace = 3 })
      assert.same({}, reply.launched)
      assert.same({ "main" }, reply.open)
      assert.same({}, reply.pending)
      assert.equal(1, #launched())
    end)

    it("encodes every list in its reply as a JSON array, even an empty one", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"')))
      call("launch_missing", { workspace = 3 })
      local raw = hyprslots.api.call("launch_missing", json.encode({ workspace = 3 }))
      assert.matches('"launched":%[%]', raw)
      assert.matches('"open":%[%]', raw)
      assert.matches('"pending":%["main"%]', raw)
      assert.matches('"cannot":%[{', raw)
      assert.is_nil(raw:find('"open":{}', 1, true))
    end)

    it("refuses on a workspace that launches nothing", function()
      setup()
      assert.matches("launches no apps", call("launch_missing", { workspace = 3 }).error)
      assert.equal(0, #launched())
    end)

    it("defaults to the focused workspace", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"')))
      assert.equal(3, call("launch_missing", {}).workspace)
    end)
  end)

  describe("at login", function()
    it("launches the missing apps of the workspaces set to, once Hyprland has started, one after another", function()
      setup()
      hl.emit("hyprland.start")
      hl.run_timers() -- the start's wait
      hl.run_timers() -- one app after another
      assert.same({ { cmd = "foot", rules = { workspace = "5 silent" } } }, launched())
    end)

    it("the window that opens goes into the slot it was launched for, though another workspace's comes first", function()
      setup()
      hl.emit("hyprland.start")
      hl.run_timers()
      local window = hl_stub.window(7, "foot", { workspace = 1 })
      hl.windows = { window }
      hl.emit("window.open", window)
      -- Workspace 3's main waits for foot too, and workspace 3 comes first.
      assert.same({ workspace = 5, slot = "main" }, call("state").assignments["0x1007"])
    end)

    it("not on a config reload", function()
      setup()
      hl.emit("config.reloaded")
      hl.run_timers()
      hl.run_timers()
      assert.same({}, launched())
    end)
  end)

  describe("the window launched for a slot", function()
    local function login()
      hl.emit("hyprland.start")
      hl.run_timers() -- the start's wait: foot is then on its way to 5's main
    end

    local function open(window)
      hl.windows[#hl.windows + 1] = window
      hl.emit("window.open", window)
    end

    local function close(window)
      for i, w in ipairs(hl.windows) do
        if w == window then
          table.remove(hl.windows, i)
          break
        end
      end
      hl.emit("window.close", window)
    end

    local function slot_of(window)
      return call("state").assignments[window.address]
    end

    it("is not one its spec does not match: that goes where it would, and the claim waits for the app", function()
      setup()
      login()
      local aside = hl_stub.window(8, "t-aside", { workspace = 1 })
      open(aside)
      assert.same({ workspace = 3, slot = "aside" }, slot_of(aside))
      local foot = hl_stub.window(7, "foot", { workspace = 1 })
      open(foot)
      assert.same({ workspace = 5, slot = "main" }, slot_of(foot))
    end)

    it("takes the slot once: the app's next window is routed as any window opening", function()
      setup()
      login()
      local first = hl_stub.window(7, "foot", { workspace = 1 })
      open(first)
      assert.same({ workspace = 5, slot = "main" }, slot_of(first))
      close(first)
      local second = hl_stub.window(9, "foot", { workspace = 1 })
      open(second)
      -- Workspace 3's main comes first in the router's precedence.
      assert.same({ workspace = 3, slot = "main" }, slot_of(second))
    end)

    it("is routed as any window opening where another window filled its slot while the app was on its way", function()
      setup()
      login()
      local other = hl_stub.window(8, "t-aside", { workspace = 1 })
      open(other)
      local reply = call("assign", { address = other.address, workspace = 5, slot = "main" })
      assert.is_nil(reply.error)
      local foot = hl_stub.window(7, "foot", { workspace = 1 })
      open(foot)
      assert.same({ workspace = 3, slot = "main" }, slot_of(foot))
      local held = slot_of(other)
      assert.same({ 5, "main" }, { held.workspace, held.slot })
    end)

    it("is the first of those waiting for its app by workspace, as a number, then by slot", function()
      setup([[
return {
  slots = { main = { key = "m" }, aside = { key = "a" } },
  specs = { [5] = { main = "foot" }, [10] = { main = "foot", aside = "foot" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "h[main, aside]" } } },
  launch = { [5] = "on_demand", [10] = "on_demand" },
}
]], (CONFIG:gsub("layouts = data.layouts", "layouts = data.layouts, workspaces = 10", 1)))
      -- Launched by hand, 10 first: each waits until its window arrives.
      assert.is_true(call("launch_missing", { workspace = 10 }).ok)
      assert.is_true(call("launch_missing", { workspace = 5 }).ok)
      assert.equal(3, #launched())
      local windows = {}
      for i = 1, 3 do
        windows[i] = hl_stub.window(10 + i, "foot", { workspace = 1 })
        open(windows[i])
      end
      -- 5 before 10, though "10/main" sorts before "5/main" as text.
      assert.same({ workspace = 5, slot = "main" }, slot_of(windows[1]))
      assert.same({ workspace = 10, slot = "aside" }, slot_of(windows[2]))
      assert.same({ workspace = 10, slot = "main" }, slot_of(windows[3]))
    end)
  end)

  describe("the desktop entry", function()
    it("is stored with the spec a window's assignment makes, so it need not be looked for again", function()
      hl.windows = { hl_stub.window(1, "foot", { workspace = 3 }) }
      setup()
      assert.is_true(call("take_spec", { workspace = 4, slot = "main", address = "0x1001" }).ok)
      assert.is_true(call("save").ok)
      assert.matches('desktop_ids = {%s*foot = "foot"', read(dir .. "/slots.lua"))
    end)

    it("stored, is the one launched even where the app's own is gone", function()
      setup((SLOTS:gsub("%[5%] = \"at_login\"", '[3] = "on_demand"'):gsub("launch = ", 'desktop_ids = { foot = "my-foot" }, launch = ')))
      write(apps .. "/my-foot.desktop", "[Desktop Entry]\nExec=foot --server\n")
      os.remove(apps .. "/foot.desktop")
      assert.same({ { slot = "main", command = "foot --server" } }, call("launch_missing", { workspace = 3 }).launched)
    end)
  end)
end)
