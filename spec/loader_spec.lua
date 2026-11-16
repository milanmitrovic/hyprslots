-- The engine loader (tools/loader.lua): the one file hyprslots puts into
-- Omarchy's workspace-layouts folder, which Omarchy's
-- default/hypr/workspace-layouts.lua requires on every config load. It is
-- run here as Omarchy runs it, from that folder under its installed name,
-- against a plugin folder on disk (a stand-in engine that records what the
-- loader asks of it).

local hl_stub = require("helpers.hl_stub")

local ID = "io.github.milanmitrovic.hyprslots"

local ENGINE = [[
local calls = _G.loader_spec_calls
return {
  setup = function() calls[#calls + 1] = "setup" end,
  bind_workspace_keys = function() calls[#calls + 1] = "bind_workspace_keys" end,
  bind_resize_keys = function() calls[#calls + 1] = "bind_resize_keys" end,
}
]]

describe("the engine loader", function()
  local root, config_home, loader_path, plugin, hl
  local saved = {}

  local function sh(command)
    assert(os.execute(command))
  end

  local function write(path, content)
    sh("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
  end

  local function exists(path)
    local file = io.open(path, "r")
    if file then
      file:close()
      return true
    end
    return false
  end

  -- Omarchy requiring the folder's files on a config load.
  local function load()
    return dofile(loader_path)
  end

  before_each(function()
    root = os.tmpname()
    os.remove(root)
    config_home = root .. "/config"
    plugin = config_home .. "/omarchy/plugins/" .. ID
    loader_path = root .. "/state/omarchy/workspace-layouts/zz-hyprslots.lua"
    local source = assert(io.open("tools/loader.lua", "r"))
    write(loader_path, source:read("a"))
    source:close()

    saved.getenv, saved.path, saved.engine = os.getenv, package.path, package.loaded["hyprslots"]
    os.getenv = function(name)
      if name == "XDG_CONFIG_HOME" then
        return config_home
      end
      return saved.getenv(name)
    end
    package.loaded["hyprslots"] = nil
    -- Hyprland's search path, which has no hyprslots on it (busted's has
    -- this repo's lua/).
    package.path = "/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua"
    hl = hl_stub.new({ monitors = {} })
    _G.hl = hl
    _G.loader_spec_calls = {}
    _G.hyprslots, _G.hyprslots_load_error = nil, nil
  end)

  after_each(function()
    os.getenv, package.path, package.loaded["hyprslots"] = saved.getenv, saved.path, saved.engine
    _G.hl, _G.loader_spec_calls, _G.hyprslots, _G.hyprslots_load_error = nil, nil, nil, nil
    sh("rm -rf '" .. root .. "'")
  end)

  it("runs the engine from the plugin folder: set up, then Super+N and the resize keys", function()
    write(plugin .. "/lua/hyprslots/init.lua", ENGINE)
    load()
    assert.are.same({ "setup", "bind_workspace_keys", "bind_resize_keys" }, _G.loader_spec_calls)
    assert.is_table(_G.hyprslots)
    assert.is_nil(_G.hyprslots_load_error)
    assert.are.same({}, hl.notifications)
    local first = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;"
    assert.are.equal(first, package.path:sub(1, #first))
  end)

  it("puts the plugin's lua folder on the search path once, however often the config loads", function()
    write(plugin .. "/lua/hyprslots/init.lua", ENGINE)
    load()
    package.loaded["hyprslots"] = nil
    load()
    local _, count = package.path:gsub(plugin:gsub("%p", "%%%0") .. "/lua/%?%.lua;", "")
    assert.are.equal(1, count)
  end)

  it("says why in a notification when the engine fails, and lets the config load on", function()
    write(plugin .. "/lua/hyprslots/init.lua", "error('broken engine')")
    assert.has_no.errors(load)
    assert.is_nil(_G.hyprslots)
    assert.matches("broken engine", _G.hyprslots_load_error)
    assert.are.equal(1, #hl.notifications)
    assert.matches("^hyprslots failed to load: .*broken engine", hl.notifications[1].text)
    assert.is_true(exists(loader_path))
  end)

  it("does nothing, and removes itself, once the plugin is removed", function()
    load()
    assert.are.same({}, _G.loader_spec_calls)
    assert.is_nil(_G.hyprslots)
    assert.is_nil(_G.hyprslots_load_error)
    assert.are.same({}, hl.notifications)
    assert.is_false(exists(loader_path))
  end)

  it("stays when the plugin folder is there without an engine in it, and says so", function()
    sh("mkdir -p '" .. plugin .. "'")
    load()
    assert.is_true(exists(loader_path))
    assert.are.equal(1, #hl.notifications)
    assert.matches("^hyprslots failed to load", hl.notifications[1].text)
  end)
end)
