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
  slots = { left = { key = "l" }, main = { key = "m", description = "the editor" }, right = { key = "r" } },
  specs = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "h[left, main, right]" },
      workspaces = { [3] = { [1] = "h[main:2, right:1]", [2] = "left" } } },
    single = { screens = 1, default = { [1] = "h[left, main, right]" } },
  },
}
]]

local CONFIG_LUA = [[
local data = load_data("slots.lua")
return {
  slots = data.slots,
  specs = data.specs,
  desks = data.desks,
  layouts = data.layouts,
  title_matching = { browser_apps = { "firefox" } },
}
]]

describe("config.load", function()
  local dir
  after_each(function()
    if dir then remove_dir(dir) end
    dir = nil
  end)

  describe("with config.lua's scroll width of before", function()
    local SCROLLING = [[
return {
  slots = { left = { key = "l" }, main = { key = "m" } },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "scroll[left, main]" },
    workspaces = { [3] = { [1] = "scroll:0.25[main, left]" }, [4] = { [1] = "h[left, main]" } } } },
}
]]
    local function with_width(width)
      return [[
local data = load_data("slots.lua")
return { slots = data.slots, desks = data.desks, layouts = data.layouts, scroll = { width = ]] .. width .. [[ } }
]]
    end

    it("gives it to every scroll tree without a width of its own, in slots.lua's data too", function()
      dir = config_dir({ ["config.lua"] = with_width(0.5), ["slots.lua"] = SCROLLING })
      local cfg = assert(config.load(dir))
      assert.is_true(cfg.migrated)
      assert.are.equal(0.5, cfg.layouts.solo.default[1].width)
      assert.are.equal(0.25, cfg.layouts.solo.workspaces[3][1].width, "a tree's own width stays")
      local layouts = cfg.data_files["slots.lua"].data.layouts
      assert.are.equal("scroll:0.5[left, main]", layouts.solo.default[1])
      assert.are.equal("scroll:0.25[main, left]", layouts.solo.workspaces[3][1])
      assert.are.equal("h[left, main]", layouts.solo.workspaces[4][1])
      assert.are.same({ "scroll" }, require("hyprslots.edit").read_only(cfg.raw, cfg.data_files["slots.lua"].given),
        "the layouts are still slots.lua's")
    end)

    it("changes nothing when it was full width (0.99, the default)", function()
      dir = config_dir({ ["config.lua"] = with_width(0.99), ["slots.lua"] = SCROLLING })
      local cfg = assert(config.load(dir))
      assert.is_falsy(cfg.migrated)
      assert.is_nil(cfg.layouts.solo.default[1].width)
    end)
  end)

  it("loads config.lua, which loads slots.lua through load_data", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA })
    local cfg = assert(config.load(dir))

    assert.are.same({ "left", "main", "right" }, cfg.slot_names)
    assert.are.equal("the editor", cfg.slots.main.description)
    assert.are.equal("t-main", cfg.specs[3].main.class)
    assert.are.same({ "dual", "single" }, cfg.desk_names)
    assert.are.same({ "HEADLESS-2", "HEADLESS-3" }, cfg.desks.dual.monitors)
    assert.are.equal("dual", cfg.desks.dual.layout)
    assert.are.same({ "dual", "single" }, cfg.layout_names)
    assert.are.equal(2, cfg.layouts.dual.screens)
    assert.are.same({ "main", "right" }, require("hyprslots.tree").slots(cfg.layouts.dual.workspaces[3][1]))
    assert.is_falsy(cfg.migrated)
  end)

  it("keys the slots of a slots.lua whose slots have no key (left, main, right: l, m, r), and says it changed", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA:gsub(' key = "%a",?', "") })
    local cfg = assert(config.load(dir))
    assert.is_true(cfg.data_files["slots.lua"].migrated, "the file differs from what runs until it is saved")
    local slots = cfg.data_files["slots.lua"].data.slots
    assert.are.same({ left = { key = "l" }, main = { key = "m", description = "the editor" }, right = { key = "r" } },
      slots)
    assert.are.equal("r", cfg.slots.right.key)
    for _, path in ipairs(require("hyprslots.edit").read_only(cfg.raw, cfg.data_files["slots.lua"].given)) do
      assert.are_not.equal("slots", path, "the slots are still slots.lua's")
    end
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
        return { slots = {}, desks = {},
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
        return { slots = {}, desks = {} }
      ]],
    })
    assert(config.load(dir))
  end)

  it("loads slots.lua as data only", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("slots.lua"); return { slots = d.slots, desks = {} }',
      ["slots.lua"] = 'os.execute("true"); return { slots = {} }',
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("slots.lua", err)
    assert.matches("os", err)
  end)

  it("refuses to load data from outside the config directory", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("../etc/passwd"); return { slots = {}, desks = {} }',
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("load_data", err)
  end)

  it("reads a slots.lua in the per-workspace shape of before as global slots and per-workspace specs", function()
    dir = config_dir({
      ["config.lua"] = CONFIG_LUA,
      ["slots.lua"] = [[
return {
  slots = { [3] = { main = "t-main", right = "t-right" }, [4] = { main = "t-mail" } },
  descriptions = { [3] = { main = "the editor" } },
  arrangements = { solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "h[main, right]" } } } },
}
]],
    })
    local cfg = assert(config.load(dir))
    assert.is_true(cfg.migrated)
    assert.are.same({ "main", "right" }, cfg.slot_names)
    assert.are.equal("the editor", cfg.slots.main.description)
    assert.are.equal("t-main", cfg.specs[3].main.class)
    assert.are.equal("t-mail", cfg.specs[4].main.class)
    local file = cfg.data_files["slots.lua"]
    assert.are.same({ [3] = { main = "t-main", right = "t-right" }, [4] = { main = "t-mail" } }, file.data.specs,
      "the editor's data is in the global shape")
    assert.is_nil(file.data.descriptions)
  end)

  it("reads a slots.lua with arrangements as desks and layouts, ordered by the monitors connected", function()
    dir = config_dir({
      ["config.lua"] = CONFIG_LUA,
      ["slots.lua"] = [[
return {
  slots = { left = {}, main = {} },
  pinned = { "side" },
  arrangements = {
    dual = { screens = { big = "HEADLESS-2", side = "HEADLESS-3" }, desks = { [3] = { side = "left", big = "main" } } },
  },
}
]],
    })
    local monitors = {
      { name = "HEADLESS-2", description = "", serial = "", x = 1920, y = 0 },
      { name = "HEADLESS-3", description = "", serial = "", x = 0, y = 0 },
    }
    local cfg = assert(config.load(dir, { monitors = monitors }))
    assert.is_true(cfg.migrated)
    assert.are.same({ "HEADLESS-3", "HEADLESS-2" }, cfg.desks.dual.monitors)
    assert.is_nil(cfg.desks.dual.pinned, "pinned screens are gone")
    assert.are.same({ "left" }, require("hyprslots.tree").slots(cfg.layouts.dual.workspaces[3][1]))
    local file = cfg.data_files["slots.lua"]
    assert.is_nil(file.data.arrangements)
    assert.are.same({ monitors = { "HEADLESS-3", "HEADLESS-2" }, layout = "dual" }, file.data.desks.dual)
  end)

  it("refuses a config.lua that passes arrangements on, saying what to add", function()
    dir = config_dir({
      ["config.lua"] = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements, pinned = data.pinned }
]],
      ["slots.lua"] = SLOTS_LUA,
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("desks = data%.desks, layouts = data%.layouts", err)
  end)

  it("refuses a config.lua that passes slots.lua's slots on but drops its specs, saying what to add", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("slots.lua"); return { slots = d.slots, desks = d.desks, layouts = d.layouts }',
      ["slots.lua"] = SLOTS_LUA,
    })
    local cfg, err = config.load(dir)
    assert.is_nil(cfg)
    assert.matches("specs = data%.specs", err)
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
      slots = { left = {}, main = {} },
      specs = { [3] = { left = "t-left", main = "t-main" } },
      desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
      layouts = { solo = { screens = 1, workspaces = { [3] = { [1] = "h[left, main:2]" } } } },
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
    assert.are.same({ "solo" }, cfg.desk_names)
    assert.are.same({ "solo" }, cfg.layout_names)
  end)

  it("accepts a config with no slots, desks or layouts", function()
    local cfg = assert(config.validate({}))
    assert.are.same({}, cfg.desk_names)
    assert.are.same({}, cfg.layout_names)
  end)

  it("rejects a non-table", function() rejects(nil, "table") end)

  it("rejects an unknown top-level key", function()
    local raw = valid()
    raw.arangements = {}
    rejects(raw, "unknown key 'arangements'")
  end)

  it("rejects title_rules, which nothing reads (title_matching configures titles)", function()
    local raw = valid()
    raw.title_rules = {}
    rejects(raw, "unknown key 'title_rules'")
  end)

  it("keeps each global slot's description, the editor's note", function()
    local raw = valid()
    raw.slots.main = { description = "the editor" }
    local cfg = assert(config.validate(raw))
    assert.are.equal("the editor", cfg.slots.main.description)
    assert.is_nil(cfg.slots.left.description)
    assert.are.same({ "left", "main" }, cfg.slot_names)
  end)

  it("rejects a global slot that is not { description = text }", function()
    local raw = valid()
    raw.slots.main = { description = 4 }
    rejects(raw, "slots%.main%.description: must be text")
    raw.slots.main = { descripton = "x" }
    rejects(raw, "slots%.main: unknown key 'descripton'")
    raw.slots.main = "t-main"
    rejects(raw, "slots%.main: must be a table { key = \"m\", description = \"%.%.%.\" }")
  end)

  it("keeps each global slot's key, and keys the slots that have none (left, main: l, m)", function()
    local raw = valid()
    raw.slots.main = { key = "x" }
    local cfg = assert(config.validate(raw))
    assert.are.equal("x", cfg.slots.main.key)
    assert.are.equal("l", cfg.slots.left.key)
    assert.are.equal("l", assert(config.validate(valid())).slots.left.key)
    assert.are.equal("m", assert(config.validate(valid())).slots.main.key)
  end)

  it("rejects a slot key that is not one letter a-z", function()
    local raw = valid()
    for _, bad in ipairs({ "M", "1", "mm", "" }) do
      raw.slots.main = { key = bad }
      rejects(raw, "slots%.main%.key: a slot's key is one letter a%-z")
    end
  end)

  it("rejects a slot key another slot has", function()
    local raw = valid()
    raw.slots.left = { key = "m" }
    raw.slots.main = { key = "m" }
    rejects(raw, "slots%.main%.key: 'm' is slot 'left''s key already")
  end)

  it("still reads the per-workspace shape of before (slots = workspace -> slot -> spec, descriptions per workspace)", function()
    local cfg = assert(config.validate({
      slots = { [3] = { left = "t-left", main = "t-main" } },
      descriptions = { [3] = { main = "the editor" } },
      arrangements = { solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "h[left, main]" } } } },
    }))
    assert.are.same({ "solo" }, cfg.desk_names)
    assert.are.same({ "left", "main" }, cfg.slot_names)
    assert.are.equal("t-main", cfg.specs[3].main.class)
    assert.are.equal("the editor", cfg.slots.main.description)
  end)

  it("rejects a specs workspace that is not 1-10", function()
    local raw = valid()
    raw.specs[11] = { main = "y" }
    rejects(raw, "specs%[11%]: a workspace must be an integer from 1 to 10")
  end)

  it("manages workspaces 1 to 10 unless workspaces says how many", function()
    assert.are.equal(10, assert(config.validate(valid())).workspaces)
    local raw = valid()
    raw.workspaces = 9
    assert.are.equal(9, assert(config.validate(raw)).workspaces)
  end)

  it("rejects a workspaces count that is no integer from 1 to 10", function()
    for _, bad in ipairs({ 0, 11, 2.5, "9" }) do
      local raw = valid()
      raw.workspaces = bad
      rejects(raw, "workspaces: must be how many workspaces hyprslots manages, an integer from 1 to 10")
    end
  end)

  it("rejects specs and trees for a workspace past the count", function()
    local raw = valid()
    raw.workspaces = 9
    raw.specs[10] = { main = "y" }
    rejects(raw, "specs%[10%]: a workspace must be an integer from 1 to 9 %(workspaces = 9%)")
    raw = valid()
    raw.workspaces = 9
    raw.layouts.solo.workspaces[10] = { [1] = "main" }
    rejects(raw, "layouts%.solo%.workspaces%[10%]: a workspace must be an integer from 1 to 9 %(workspaces = 9%)")
  end)

  it("rejects a bad slot name", function()
    local raw = valid()
    raw.slots["has space"] = {}
    rejects(raw, "slot name")
  end)

  it("rejects a spec for a slot that is not defined under slots", function()
    local raw = valid()
    raw.specs[3].mian = "x"
    rejects(raw, "specs%[3%]%.mian: no slot 'mian' %(define it under slots%)")
  end)

  it("rejects a bad spec with its path", function()
    local raw = valid()
    raw.specs[3].main = "kitty/"
    rejects(raw, "specs%[3%]%.main: spec 'kitty/'")
  end)

  it("lets a tree place a global slot no workspace has a spec for (filled by hand)", function()
    local raw = valid()
    raw.slots.right = {}
    raw.layouts.solo.workspaces[3][1] = "h[left, main, right]"
    assert(config.validate(raw))
  end)

  it("rejects a desk without monitors, or listing one twice", function()
    local raw = valid()
    raw.desks.solo.monitors = {}
    rejects(raw, "desks%.solo%.monitors: must list at least one monitor")
    raw.desks.solo.monitors = { "A", "A" }
    rejects(raw, "desks%.solo%.monitors%[2%]: 'A' is listed twice")
  end)

  it("rejects a desk whose layout is missing or for another number of screens", function()
    local raw = valid()
    raw.desks.solo.layout = "nope"
    rejects(raw, "desks%.solo%.layout: no layout 'nope'")
    raw.desks.solo.layout = "solo"
    raw.desks.solo.monitors = { "HEADLESS-2", "HEADLESS-3" }
    rejects(raw, "desks%.solo%.layout: layout 'solo' is for 1 screen, and the desk has 2 monitors")
  end)

  it("lets several desks use one layout", function()
    local raw = valid()
    raw.desks.office = { monitors = { "DP-1" }, layout = "solo" }
    local cfg = assert(config.validate(raw))
    assert.are.equal(cfg.desks.office.layout, cfg.desks.solo.layout)
  end)

  it("rejects a desk or layout name with a '/'", function()
    local raw = valid()
    raw.desks["a/b"] = { monitors = { "X" }, layout = "solo" }
    rejects(raw, "no '/'")
  end)

  it("rejects a layout without its screen count, or a tree for a screen it does not have", function()
    local raw = valid()
    raw.layouts.solo.screens = nil
    rejects(raw, "layouts%.solo%.screens: must be how many screens")
    raw.layouts.solo.screens = 1
    raw.layouts.solo.workspaces[3][2] = "left"
    rejects(raw, "layouts%.solo%.workspaces%[3%]%[2%]: a screen must be an integer from 1 to 1")
  end)

  it("takes default trees for the workspaces with none of their own", function()
    local raw = valid()
    raw.layouts.solo.default = { [1] = "main" }
    local cfg = assert(config.validate(raw))
    local layout = cfg.layouts.solo
    assert.are.same({ "left", "main" }, require("hyprslots.tree").slots(config.trees_for(layout, 3)[1]))
    assert.are.same({ "main", "left" }, require("hyprslots.tree").slots(config.trees_for(layout, 5)[1]),
      "every tree holds every slot")
  end)

  it("gives a layout with no default tree one with every slot: a scroll branch on a laptop panel", function()
    local raw = valid()
    local tree = require("hyprslots.tree")
    local layout = assert(config.validate(raw)).layouts.solo
    assert.is_nil(tree.scroll(layout.default[1]))
    assert.are.same({ "left", "main" }, tree.slots(config.trees_for(layout, 5)[1]))
    assert.are.same({ "left", "main" }, tree.slots(config.trees_for(layout, 3)[1]), "a workspace's own stays")
    raw.desks.solo.monitors = { "eDP-1" }
    local laptop = assert(config.validate(raw)).layouts.solo
    assert.is_truthy(tree.scroll(laptop.default[1]))
    assert.are.same({ "left", "main" }, tree.slots(laptop.default[1]))
  end)

  it("rejects arrangements beside desks and layouts", function()
    local raw = valid()
    raw.arrangements = {}
    rejects(raw, "arrangements: arrangements are desks and layouts now")
  end)

  it("drops pinned screens (gone), a desk's or top-level, without a word", function()
    local raw = valid()
    raw.pinned = { "laptop" }
    raw.desks.solo.pinned = { 1 }
    local cfg = assert(config.validate(raw))
    assert.is_nil(cfg.desks.solo.pinned)
  end)

  it("rejects an unparsable tree with its path", function()
    local raw = valid()
    raw.layouts.solo.workspaces[3][1] = "h[left, main"
    rejects(raw, "layouts%.solo%.workspaces%[3%]%[1%]: expected ']'")
  end)

  it("drops a slot that is not defined under slots from a tree, which holds every slot that is", function()
    local raw = valid()
    raw.layouts.solo.workspaces[3][1] = "h[left, mian]"
    local cfg = assert(config.validate(raw))
    assert.are.same({ "left", "main" }, require("hyprslots.tree").slots(cfg.layouts.solo.workspaces[3][1]))
    assert.is_false(cfg.migrated, "a table config.lua builds is not a shape of before")
  end)

  it("accepts an overflow leaf", function()
    local raw = valid()
    raw.layouts.solo.workspaces[3][1] = "h[left:2, v[main, *]]"
    assert(config.validate(raw))
  end)

  it("refuses an accordion with its path, pointing to scroll[...]", function()
    local raw = valid()
    raw.layouts.solo.workspaces[3][1] = "a[left, main]"
    rejects(raw, "layouts%.solo%.workspaces%[3%]%[1%]: a%[...%] %(an accordion, a Hyprland group with tabs%) is gone: "
      .. "write scroll%[left, main%]")
  end)

  it("accepts a scroll branch, checking its slots", function()
    local raw = valid()
    raw.layouts.solo.workspaces[3][1] = "scroll[left, main]"
    assert(config.validate(raw))
    raw.layouts.solo.workspaces[3][1] = "scroll:0.5[left, mian]"
    local node = assert(config.validate(raw)).layouts.solo.workspaces[3][1]
    assert.are.same({ "left", "main" }, require("hyprslots.tree").scroll(node))
    assert.are.equal(0.5, node.width)
  end)

  it("still checks the scroll columns' width of before (each tree has its own now)", function()
    local raw = valid()
    raw.scroll = { width = 0.95 }
    assert(config.validate(raw))
    raw.scroll = { width = 1.5 }
    rejects(raw, "scroll%.width: must be a fraction of the screen from 0%.1 to 1, got 1%.5")
    raw.scroll = { widht = 0.9 }
    rejects(raw, "scroll: unknown key 'widht'")
    raw.scroll = 0.9
    rejects(raw, "scroll: must be a table")
  end)

  it("rejects a slot placed on two screens of one workspace", function()
    local raw = valid()
    raw.layouts.solo.screens = 2
    raw.desks.solo.monitors = { "HEADLESS-2", "HEADLESS-3" }
    raw.layouts.solo.workspaces[3][2] = "main"
    rejects(raw, "slot 'main' is placed on both screen 1 and screen 2")
  end)

  it("reports every error, not just the first", function()
    local raw = valid()
    raw.specs[3].main = ""
    raw.layouts.solo.workspaces[3][1] = "h["
    local cfg, err = config.validate(raw)
    assert.is_nil(cfg)
    assert.matches("specs%[3%]%.main", err)
    assert.matches("workspaces%[3%]%[1%]", err)
  end)
  describe("title_matching", function()
    it("matches title specs through the configured extractors", function()
      local raw = valid()
      raw.specs[3].main = "MyEditor/hyprslots"
      raw.title_matching = { extractors = { MyEditor = " — " } }
      local cfg = assert(config.validate(raw))
      local main = cfg.specs[3].main
      assert.is_true(spec.match(main, { class = "MyEditor", title = "hyprslots — init.lua" }))
      assert.is_false(spec.match(main, { class = "MyEditor", title = "x — hyprslots" }))
    end)

    it("restricts tag specs to the configured browsers", function()
      local raw = valid()
      raw.specs[3].main = "[Docs]"
      raw.title_matching = { browser_apps = { "firefox" } }
      local cfg = assert(config.validate(raw))
      assert.is_true(spec.match(cfg.specs[3].main, { class = "firefox", title = "[Docs] x" }))
      assert.is_false(spec.match(cfg.specs[3].main, { class = "chromium", title = "[Docs] x" }))
    end)

    it("uses the defaults when absent", function()
      local raw = valid()
      raw.specs[3].main = "kitty/build"
      local cfg = assert(config.validate(raw))
      assert.is_true(spec.match(cfg.specs[3].main, { class = "kitty", title = "build | fish" }))
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

describe("config.load with the data file in memory", function()
  local dir
  after_each(function()
    if dir then remove_dir(dir) end
    dir = nil
  end)

  it("hands config.lua the given data instead of reading slots.lua", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA })
    local data = assert(load(SLOTS_LUA, "=slots", "t", {}))()
    data.layouts.single.default[1] = "v[left, main, right]"
    local cfg = assert(config.load(dir, { data = { ["slots.lua"] = data } }))
    assert.are.equal("v", cfg.layouts.single.default[1].split)
  end)

  it("keeps what slots.lua held, untouched by config.lua", function()
    dir = config_dir({
      ["config.lua"] = [[
local data = load_data("slots.lua")
data.specs[3].main = "changed-by-code"
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]],
      ["slots.lua"] = SLOTS_LUA,
    })
    local cfg = assert(config.load(dir))
    assert.are.equal("changed-by-code", cfg.specs[3].main.class)
    local loaded = cfg.data_files["slots.lua"]
    assert.are.equal("t-main", loaded.data.specs[3].main, "the file's own content")
    assert.are.equal("changed-by-code", loaded.given.specs[3].main, "what config.lua was handed")
  end)

  it("never lets config.lua change the data it was given", function()
    dir = config_dir({
      ["config.lua"] = [[
local data = load_data("slots.lua")
data.specs[3].main = "changed-by-code"
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]],
    })
    local data = assert(load(SLOTS_LUA, "=slots", "t", {}))()
    assert(config.load(dir, { data = { ["slots.lua"] = data } }))
    assert.are.equal("t-main", data.specs[3].main)
  end)

  it("keeps the table config.lua returned", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA })
    local cfg = assert(config.load(dir))
    assert.are.same({ "firefox" }, cfg.raw.title_matching.browser_apps)
    assert.are.equal(cfg.data_files["slots.lua"].given.slots, cfg.raw.slots)
  end)

  it("remembers the directory it loaded from", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = SLOTS_LUA })
    assert.are.equal(dir, assert(config.load(dir)).dir)
  end)
end)

describe("monitor_names: the user's labels for monitors", function()
  local dir
  after_each(function()
    if dir then remove_dir(dir) end
    dir = nil
  end)

  local ODYSSEY = "Samsung Electric Company Odyssey G95NC HNTW700044"
  local LABELLED = SLOTS_LUA:gsub("^return {", "return {\n  monitor_names = { [\"" .. ODYSSEY .. "\"] = \"Samsung\" },")

  it("are none when absent", function()
    assert.are.same({}, assert(config.validate({})).monitor_names)
  end)

  it("come from the data file even where config.lua does not pass them on", function()
    dir = config_dir({ ["config.lua"] = CONFIG_LUA, ["slots.lua"] = LABELLED })
    local cfg = assert(config.load(dir))
    assert.are.same({ [ODYSSEY] = "Samsung" }, cfg.monitor_names)
  end)

  it("are config.lua's own when it returns them", function()
    dir = config_dir({
      ["config.lua"] = 'local d = load_data("slots.lua"); return { slots = d.slots, specs = d.specs, desks = d.desks,'
        .. ' layouts = d.layouts, monitor_names = { ["eDP-1"] = "Panel" } }',
      ["slots.lua"] = LABELLED,
    })
    assert.are.same({ ["eDP-1"] = "Panel" }, assert(config.load(dir)).monitor_names)
  end)

  it("map a selector to a name, each non-empty text", function()
    local function rejects(names, pattern)
      local cfg, err = config.validate({ monitor_names = names })
      assert.is_nil(cfg)
      assert.matches(pattern, err)
    end
    rejects("Samsung", "monitor_names: must be a table")
    rejects({ "Samsung" }, "monitor_names%[1%]: must be keyed by a monitor")
    rejects({ [""] = "Samsung" }, "must be keyed by a monitor")
    rejects({ ["eDP-1"] = 3 }, "monitor_names%[eDP%-1%]: must be a name")
    rejects({ ["eDP-1"] = "  " }, "monitor_names%[eDP%-1%]: must be a name")
    rejects({ ["eDP-1"] = "two\nlines" }, "one line")
    assert.are.same({ ["eDP-1"] = "Panel" }, assert(config.validate({ monitor_names = { ["eDP-1"] = " Panel " } })).monitor_names)
  end)
end)
