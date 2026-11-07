local config = require("hyprslots.config")
local spec = require("hyprslots.spec")

-- A fresh directory holding the given files (name -> content).
local function config_dir(files)
  local dir = os.tmpname()
  os.remove(dir)
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  for name, content in pairs(files) do
    local file = assert(io.open(dir .. "/" .. name, "w"))
    file:write(content)
    file:close()
  end
  return dir
end

local function remove_dir(dir)
  os.execute("rm -rf '" .. dir .. "'")
end

local SLOTS_LUA = [[
return {
  slots = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = {
        [3] = { side = "left", big = "h[main:2, right:1]" },
      },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = {
        [3] = { big = "h[left, main, right]" },
      },
    },
  },
}
]]

local CONFIG_LUA = [[
local data = load_data("slots.lua")
return {
  slots = data.slots,
  arrangements = data.arrangements,
  pinned = { "laptop" },
}
]]

describe("config.load", function()
  local dir
  after_each(function()
    if dir then remove_dir(dir) end
    dir = nil
  end)

  it("loads config.lua, which loads slots.lua through load_data", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA })
    local cfg = assert(config.load(dir))

    assert.are.equal("t-main", cfg.slots[3].main.class)
    assert.are.same({ "dual", "single" }, cfg.arrangement_names)
    assert.are.equal("HEADLESS-3", cfg.arrangements.dual.screens.side)
    assert.are.same({ "main", "right" }, require("hyprslots.tree").slots(cfg.arrangements.dual.desks[3].big))
    assert.are.same({ laptop = true }, cfg.pinned)
  end)

  it("reports a missing config.lua as missing", function()
    dir = config_dir({})
    local cfg, err, missing = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("config.lua", err)
    assert.is_true(missing)
  end)

  it("reports a syntax error with the file name", function()
    dir = config_dir({ ["config.lua"] = "return {" })
    local cfg, err, missing = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("config.lua", err)
    assert.is_falsy(missing)
  end)

  it("reports a runtime error raised by config.lua", function()
    dir = config_dir({ ["config.lua"] = "error('boom')" })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("boom", err)
  end)

  it("requires config.lua to return a table", function()
    dir = config_dir({ ["config.lua"] = "return 42" })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("must return a table", err)
  end)

  it("keeps os.execute, io and hl out of config.lua", function()
    _G.hl = { dispatch = function() end }
    dir = config_dir({
      ["config.lua"] = [[
        return { slots = {}, arrangements = {},
          probe = { os_execute = os.execute, io = io, hl = hl, require = require, dofile = dofile } }
      ]],
    })
    local cfg, err = config.load(dir)
    _G.hl = nil
    -- An unknown key is an error, so read the probe off the error-free path.
    assert.is_nil(cfg)
    assert.matches("unknown key 'probe'", err)

    local env = config.sandbox(dir)
    assert.is_nil(env.os.execute)
    assert.is_nil(env.io)
    assert.is_nil(env.hl)
    assert.is_nil(env.require)
    assert.is_nil(env.dofile)
    assert.is_function(env.os.getenv)
  end)

  it("gives config.lua what it needs to branch on the machine", function()
    dir = config_dir({
      ["config.lua"] = [[
        assert(type(hostname()) == "string")
        assert(os.getenv("HOME"))
        return { slots = {}, arrangements = {} }
      ]],
    })
    assert(config.load(dir))
  end)

  it("loads slots.lua as data only", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("slots.lua"); return { slots = d.slots, arrangements = {} }',
      ["slots.lua"] = 'os.execute("true"); return { slots = {} }',
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("slots.lua", err)
    assert.matches("os", err)
  end)

  it("refuses to load data from outside the config directory", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("../etc/passwd"); return { slots = {}, arrangements = {} }',
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("load_data", err)
  end)

  it("reports a missing data file", function()
    dir = config_dir({ ["config.lua"] = 'load_data("nope.lua"); return {}' })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("nope.lua", err)
  end)
end)

describe("config.validate", function()
  local function valid()
    return {
      slots = { [3] = { left = "t-left", main = "t-main" } },
      arrangements = {
        solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "h[left, main:2]" } } },
      },
    }
  end

  local function rejects(raw, pattern)
    local cfg, err = config.validate(raw)
    assert.is_nil(cfg)
    assert.is_string(err)
    assert.matches(pattern, err)
  end

  it("accepts a well-formed config", function()
    local cfg = assert(config.validate(valid()))
    assert.are.same({ "solo" }, cfg.arrangement_names)
    assert.are.same({}, cfg.pinned)
  end)

  it("accepts a config with no slots or arrangements", function()
    local cfg = assert(config.validate({}))
    assert.are.same({}, cfg.arrangement_names)
  end)

  it("rejects a non-table", function() rejects(nil, "table") end)

  it("rejects an unknown top-level key", function()
    local raw = valid()
    raw.arangements = {}
    rejects(raw, "unknown key 'arangements'")
  end)

  it("rejects a desk that is not 1-10", function()
    local raw = valid()
    raw.slots[11] = { x = "y" }
    rejects(raw, "slots%[11%]: a desk must be an integer from 1 to 10")
  end)

  it("rejects a bad slot name", function()
    local raw = valid()
    raw.slots[3]["has space"] = "x"
    rejects(raw, "slot name")
  end)

  it("rejects a bad spec with its path", function()
    local raw = valid()
    raw.slots[3].main = "kitty/"
    rejects(raw, "slots%[3%]%.main: spec 'kitty/'")
  end)

  it("rejects an arrangement without screens", function()
    local raw = valid()
    raw.arrangements.solo.screens = {}
    rejects(raw, "arrangements%.solo%.screens")
  end)

  it("rejects a desk tree for a role the arrangement has no screen for", function()
    local raw = valid()
    raw.arrangements.solo.desks[3].side = "left"
    rejects(raw, "arrangements%.solo%.desks%[3%]%.side: no screen role 'side'")
  end)

  it("rejects an unparsable tree with its path", function()
    local raw = valid()
    raw.arrangements.solo.desks[3].big = "h[left, main"
    rejects(raw, "arrangements%.solo%.desks%[3%]%.big: expected ']'")
  end)

  it("rejects a tree naming a slot the desk does not have", function()
    local raw = valid()
    raw.arrangements.solo.desks[3].big = "h[left, mian]"
    rejects(raw, "desks%[3%]%.big: desk 3 has no slot 'mian'")
  end)

  it("rejects a slot placed on two screens of one desk", function()
    local raw = valid()
    raw.arrangements.solo.screens.side = "HEADLESS-3"
    raw.arrangements.solo.desks[3].side = "main"
    rejects(raw, "slot 'main' is placed on both")
  end)

  it("rejects pinned that is not a list of roles", function()
    local raw = valid()
    raw.pinned = "laptop"
    rejects(raw, "pinned")
  end)

  it("reports every error, not just the first", function()
    local raw = valid()
    raw.slots[3].main = ""
    raw.arrangements.solo.desks[3].big = "h["
    local cfg, err = config.validate(raw)
    assert.is_nil(cfg)
    assert.matches("slots%[3%]%.main", err)
    assert.matches("desks%[3%]%.big", err)
  end)
  describe("title_matching", function()
    it("matches title specs through the configured extractors", function()
      local raw = valid()
      raw.slots[3].main = "MyEditor/hyprslots"
      raw.title_matching = { extractors = { MyEditor = " — " } }
      local cfg = assert(config.validate(raw))
      local main = cfg.slots[3].main
      assert.is_true(spec.match(main, { class = "MyEditor", title = "hyprslots — init.lua" }))
      assert.is_false(spec.match(main, { class = "MyEditor", title = "x — hyprslots" }))
    end)

    it("restricts tag specs to the configured browsers", function()
      local raw = valid()
      raw.slots[3].main = "[Docs]"
      raw.title_matching = { browser_apps = { "firefox" } }
      local cfg = assert(config.validate(raw))
      assert.is_true(spec.match(cfg.slots[3].main, { class = "firefox", title = "[Docs] x" }))
      assert.is_false(spec.match(cfg.slots[3].main, { class = "chromium", title = "[Docs] x" }))
    end)

    it("uses the defaults when absent", function()
      local raw = valid()
      raw.slots[3].main = "kitty/build"
      local cfg = assert(config.validate(raw))
      assert.is_true(spec.match(cfg.slots[3].main, { class = "kitty", title = "build | fish" }))
    end)

    it("rejects an unknown key", function()
      local raw = valid()
      raw.title_matching = { extractor = {} }
      rejects(raw, "title_matching: unknown key 'extractor'")
    end)

    it("rejects a separator that is not a non-empty string", function()
      local raw = valid()
      raw.title_matching = { extractors = { kitty = 7 } }
      rejects(raw, "title_matching%.extractors%.kitty")
    end)

    it("rejects a malformed Lua strip pattern", function()
      local raw = valid()
      raw.title_matching = { strip_patterns = { App = "[" } }
      rejects(raw, "title_matching%.strip_patterns%.App: .*Lua pattern")
    end)

    it("rejects browser_apps that is not a list of classes", function()
      local raw = valid()
      raw.title_matching = { browser_apps = { 1 } }
      rejects(raw, "title_matching%.browser_apps")
      raw.title_matching = { browser_apps = "chromium" }
      rejects(raw, "title_matching%.browser_apps")
    end)
  end)
end)
