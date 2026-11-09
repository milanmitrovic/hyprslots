-- Drive hyprslots.setup() against a stubbed hl (test seam S2), for the specs
-- that need two screens: workspaces, routing across screens, hotplug.
--
--   local engine = require("helpers.engine")
--   local hl, o = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 })
--   local hyprslots = engine.setup(engine.TWO_SCREENS)
--   engine.state(hyprslots).desk

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local M = {}

M.CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]]

-- The completion test's config (docs/design.md §12).
M.TWO_SCREENS = [[
return {
  slots = { left = {}, main = {}, right = {} },
  specs = { [3] = { left = "t-left", main = "t-main", right = "t-right" } },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "h[left, main, right]" },
      workspaces = { [3] = { [1] = "h[main:2, right:1]", [2] = "left" } } },
    single = { screens = 1, default = { [1] = "h[left, main, right]" }, workspaces = { [3] = { [1] = "h[left, main, right]" } } },
  },
}
]]

local dirs = {}

local function config_dir(files)
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  for name, content in pairs(files) do
    local file = assert(io.open(dir .. "/" .. name, "w"))
    file:write(content)
    file:close()
  end
  dirs[#dirs + 1] = dir
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

-- Install a stub hl with these monitors (the first focused) and Omarchy's
-- o.workspaces with these blocks, as _G.hl and _G.o.
function M.stub(names, blocks)
  local monitors = {}
  for i, name in ipairs(names) do
    monitors[i] = hl_stub.monitor(name, { id = i - 1, focused = i == 1, x = (i - 1) * 2400, y = 0 })
  end
  local hl = hl_stub.new({ monitors = monitors })
  local o = hl_stub.omarchy(blocks)
  _G.hl, _G.o = hl, o
  return hl, o
end

-- setup() hyprslots with slots.lua = `slots` and config.lua = `config`
-- (default: the standard M.CONFIG).
function M.setup(slots, config)
  local hyprslots = fresh_module()
  hyprslots.setup({ config_dir = config_dir({ ["config.lua"] = config or M.CONFIG, ["slots.lua"] = slots }) })
  return hyprslots
end

function M.state(hyprslots)
  return json.decode(hyprslots.api.call("state", "{}"))
end

function M.call(hyprslots, name, args)
  return json.decode(hyprslots.api.call(name, args))
end

function M.cleanup()
  _G.hl, _G.o = nil, nil
  for _, dir in ipairs(dirs) do
    os.execute("rm -rf '" .. dir .. "'")
  end
  dirs = {}
end

return M
