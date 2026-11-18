-- The api (api.lua) is the protocol layer: it decodes a call, checks it,
-- runs the engine's modules and shapes the reply. The engine never depends
-- on it (init.lua only exposes it), the behaviour it runs lives in the
-- engine's modules, and its header names every call it answers.

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

local DIR = "lua/hyprslots/"

local function modules()
  local out = {}
  local list = assert(io.popen("ls " .. DIR))
  for name in list:lines() do
    local module = name:match("^(.+)%.lua$")
    if module then
      out[#out + 1] = module
    end
  end
  list:close()
  table.sort(out)
  return out
end

describe("module boundaries", function()
  it("no engine module requires the api but init.lua, which exposes it", function()
    local found = {}
    for _, module in ipairs(modules()) do
      if module ~= "api" and read(DIR .. module .. ".lua"):find('require%("hyprslots%.api"%)') then
        found[#found + 1] = module
      end
    end
    assert.are.same({ "init" }, found)
  end)

  it("init.lua uses the api only to expose it: call, state, dump", function()
    local used = {}
    local code = read(DIR .. "init.lua"):gsub("%-%-[^\n]*", "") -- comments may name api.lua
    for name in code:gmatch("[^%w_.]api%.([%w_]+)") do
      used[name] = true
    end
    local names = {}
    for name in pairs(used) do
      names[#names + 1] = name
    end
    table.sort(names)
    assert.are.same({ "call", "dump", "state" }, names)
  end)

  it("the modules the api runs do not reach back into it", function()
    for _, module in ipairs({ "edits", "persist", "launcher", "capture_apply" }) do
      local text = read(DIR .. module .. ".lua")
      assert.is_nil(text:find("hyprslots%.api[^%w_]"), module)
    end
  end)

  it("api.lua's header names every call it answers", function()
    local text = read(DIR .. "api.lua")
    local header = text:match("^(.-)\nlocal ")
    local missing = {}
    local count = 0
    for name in text:gmatch("\nfunction handlers%.([%w_]+)%(") do
      count = count + 1
      if not header:find("[^%w_]" .. name .. "[^%w_]") then
        missing[#missing + 1] = name
      end
    end
    assert.is_true(count > 30, "found the handlers")
    assert.are.same({}, missing)
  end)
end)
