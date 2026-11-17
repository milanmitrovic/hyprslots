-- Test seam S2: the api's `capture` (docs/design.md §9, Capture): the
-- windows of a workspace, on every screen of the active desk, turned into
-- slots, trees and assignments in one edit, previewed first.

local hl_stub = require("helpers.hl_stub")
local json = require("hyprslots.dkjson")

local CONFIG = [[
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
]]

-- A first run: no slots, a desk of two screens on a layout with no trees.
local EMPTY = [[
return {
  desks = { dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" } },
  layouts = { dual = { screens = 2 } },
}
]]

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

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("a")
  file:close()
  return text
end

describe("capture api", function()
  local hl, dir, hyprslots

  local function fresh_module()
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    return require("hyprslots")
  end

  local function setup(slots, config)
    dir = config_dir({ ["config.lua"] = config or CONFIG, ["slots.lua"] = slots })
    hyprslots = fresh_module()
    hyprslots.setup({ config_dir = dir })
    hl.emit("hyprland.start")
  end

  local function call(name, args)
    return json.decode(hyprslots.api.call(name, args and json.encode(args) or "{}"))
  end

  local function window(n, class, workspace, x, y, w, h, fields)
    local f = { workspace = workspace, at = { x = x, y = y }, size = { x = w, y = h } }
    for k, v in pairs(fields or {}) do
      f[k] = v
    end
    return hl_stub.window(n, class, f)
  end

  before_each(function()
    hl = hl_stub.new({ monitors = {
      hl_stub.monitor("HEADLESS-2", { id = 0, focused = true, x = 0, y = 0, width = 1920, height = 1080 }),
      hl_stub.monitor("HEADLESS-3", { id = 1, x = 1920, y = 0, width = 1920, height = 1080 }),
    } })
    _G.hl = hl
    _G.o = hl_stub.omarchy({ ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 })
    hl.workspaces = { { id = 3, tiled_layout = "dwindle" }, { id = 13, tiled_layout = "dwindle" } }
    hl.active_workspace = hl.workspaces[1]
    -- Workspace 3: two thirds and a third on screen 1, a third window alone on screen 2 (13).
    hl.windows = {
      window(1, "foot", 3, 10, 10, 1260, 1060),
      window(2, "foot", 3, 1280, 10, 630, 1060),
      window(3, "com.mitchellh.ghostty", 13, 1930, 10, 1900, 1060),
    }
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
    if dir then
      os.execute("rm -rf '" .. dir .. "'")
    end
  end)

  it("previews the slots it would make, each screen's tree and each window's slot, changing nothing", function()
    setup(EMPTY)
    local reply = call("capture", { workspace = 3 })
    assert.is_true(reply.ok, reply.error)
    assert.is_false(reply.applied)
    assert.equal(3, reply.workspace)
    assert.equal("dual", reply.layout)
    assert.same({ { slot = "foot", key = "f" }, { slot = "foot-2", key = "o" }, { slot = "ghostty", key = "g" } },
      reply.new_slots)
    assert.equal("h[foot:2, foot-2]", reply.trees["1"].tree)
    assert.equal("ghostty", reply.trees["2"].tree)
    assert.equal("foot", reply.windows[1].slot)
    assert.equal("com.mitchellh.ghostty", reply.windows[3].spec)
    local state = call("state")
    assert.same({}, state.slots)
    assert.is_false(state.dirty)
  end)

  it("defaults to the focused workspace", function()
    setup(EMPTY)
    assert.equal(3, call("capture", {}).workspace)
  end)

  it("applied to all workspaces, makes the slots, the shared trees and the specs in one unsaved edit", function()
    setup(EMPTY)
    local before = call("state").seq
    local reply = call("capture", { workspace = 3, scope = "all", apply = true })
    assert.is_true(reply.ok, reply.error)
    assert.is_true(reply.applied)
    local state = call("state")
    assert.equal(before + 1, state.seq, "one edit, one change event")
    assert.is_true(state.dirty)
    assert.same({ "foot", "foot-2", "ghostty" }, (function()
      local names = {}
      for i, s in ipairs(state.slots) do
        names[i] = s.name
      end
      return names
    end)())
    assert.equal("h[foot:2, foot-2]", state.layouts.dual.default["1"].tree)
    assert.equal("ghostty", state.layouts.dual.default["2"].tree)
    assert.same({ foot = "foot/foot", ["foot-2"] = "foot/foot", ghostty = "com.mitchellh.ghostty" }, state.specs["3"])
    assert.same({ workspace = 3, slot = "foot" }, state.assignments["0x1001"])
    assert.same({ workspace = 3, slot = "foot-2" }, state.assignments["0x1002"])
    assert.same({ workspace = 3, slot = "ghostty" }, state.assignments["0x1003"])
  end)

  it("saved, slots.lua holds it, and a reload keeps it", function()
    setup(EMPTY)
    assert.is_true(call("capture", { workspace = 3, scope = "all", apply = true }).ok)
    assert.is_true(call("save").ok)
    assert.matches("ghostty", read(dir .. "/slots.lua"))
    assert.is_true(call("reload").ok)
    local state = call("state")
    assert.is_false(state.dirty)
    assert.equal("h[foot:2, foot-2]", state.layouts.dual.default["1"].tree)
    assert.same({ workspace = 3, slot = "foot-2" }, state.assignments["0x1002"])
  end)

  it("applied to this workspace only, gives it trees of its own and leaves the shared ones", function()
    setup([[
return {
  slots = { main = { key = "m" } },
  desks = { dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" } },
  layouts = { dual = { screens = 2, default = { [1] = "main" } } },
}
]])
    local reply = call("capture", { workspace = 3, scope = "workspace", apply = true })
    assert.is_true(reply.ok, reply.error)
    local layout = call("state").layouts.dual
    assert.same({ 3 }, layout.own)
    assert.equal("h[foot:2, foot-2, main]", layout.workspaces["3"]["1"].tree)
    assert.equal("ghostty", layout.workspaces["3"]["2"].tree)
    -- The new slots stay off the shared tree: only workspace 3, on its own trees, fills them (§4).
    assert.equal("main", layout.default["1"].tree)
  end)

  it("applied to all workspaces from one with trees of its own, the workspace goes back to the shared ones", function()
    setup([[
return {
  slots = { main = { key = "m" } },
  desks = { dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" } },
  layouts = { dual = { screens = 2, default = { [1] = "main" }, workspaces = { [3] = { [2] = "main" } } } },
}
]])
    assert.is_true(call("capture", { workspace = 3, scope = "all", apply = true }).ok)
    local layout = call("state").layouts.dual
    assert.same({}, layout.own)
    assert.equal("h[foot:2, foot-2, main]", layout.default["1"].tree)
  end)

  it("records a scrolling screen as a scroll branch, in column order, as wide as its columns", function()
    hl.workspaces[1].tiled_layout = "scrolling"
    hl.windows[1].layout = { name = "scrolling", column = { index = 1, width = 0.5 }, index_in_column = 0 }
    hl.windows[2].layout = { name = "scrolling", column = { index = 0, width = 0.5 }, index_in_column = 0 }
    setup(EMPTY)
    local reply = call("capture", { workspace = 3 })
    assert.is_true(reply.ok, reply.error)
    assert.equal("scroll:0.5[foot, foot-2]", reply.trees["1"].tree)
    assert.equal("0x1002", reply.windows[1].address, "the first column first")
  end)

  it("refuses with no active desk, windows that overlap, and slots that config.lua builds", function()
    hl.monitors[2] = nil
    setup(EMPTY)
    assert.matches("no desk", call("capture", { workspace = 3 }).error)

    hl.monitors[2] = hl_stub.monitor("HEADLESS-3", { id = 1, x = 1920, y = 0 })
    hl.windows[2] = window(2, "foot", 3, 500, 10, 1260, 1060)
    setup(EMPTY)
    assert.matches("overlap", call("capture", { workspace = 3 }).error)

    hl.windows[2] = window(2, "foot", 3, 1280, 10, 630, 1060)
    setup(EMPTY, [[
local data = load_data("slots.lua")
return { slots = {}, specs = data.specs, desks = data.desks, layouts = data.layouts }
]])
    assert.matches("set by code", call("capture", { workspace = 3, scope = "all", apply = true }).error)
  end)

  it("previews a plan token that names the edit, the same while nothing changes", function()
    setup(EMPTY)
    local first = call("capture", { workspace = 3, scope = "all" })
    assert.is_true(first.ok, first.error)
    assert.matches("^%x%x%x%x%x%x%x%x$", first.plan)
    assert.equal(first.plan, call("capture", { workspace = 3, scope = "all" }).plan)
    assert.are_not.equal(first.plan, call("capture", { workspace = 3, scope = "workspace" }).plan,
      "the trees go elsewhere: another edit")
  end)

  it("applies the previewed plan when the windows are as they were", function()
    setup(EMPTY)
    local preview = call("capture", { workspace = 3, scope = "all" })
    local reply = call("capture", { workspace = 3, scope = "all", apply = true, plan = preview.plan })
    assert.is_true(reply.ok, reply.error)
    assert.is_true(reply.applied)
    assert.equal(preview.plan, reply.plan)
    assert.equal("h[foot:2, foot-2]", call("state").layouts.dual.default["1"].tree)
  end)

  -- The y/n prompt is open while the preview shows: whatever moves the
  -- windows meanwhile must not slip an edit past the one approved.
  local function refused_after(change)
    setup(EMPTY)
    local preview = call("capture", { workspace = 3, scope = "all" })
    assert.is_true(preview.ok, preview.error)
    local before = call("state")
    change()
    local reply = call("capture", { workspace = 3, scope = "all", apply = true, plan = preview.plan })
    assert.is_false(reply.ok)
    assert.matches("the windows changed since the preview: capture again", reply.error, 1, true)
    local state = call("state")
    assert.equal(before.seq, state.seq, "nothing applied")
    assert.is_false(state.dirty)
    assert.same({}, state.slots)
  end

  it("refuses the previewed plan once a window opened since", function()
    refused_after(function()
      hl.windows[#hl.windows + 1] = window(4, "google-chrome", 13, 1930, 10, 1900, 1060)
      hl.windows[3] = window(3, "com.mitchellh.ghostty", 13, 1930, 10, 940, 1060)
      hl.windows[4] = window(4, "google-chrome", 13, 2880, 10, 940, 1060)
    end)
  end)

  it("refuses the previewed plan once a window closed since", function()
    refused_after(function()
      table.remove(hl.windows, 2)
    end)
  end)

  it("refuses the previewed plan once a window moved to another screen since", function()
    refused_after(function()
      hl.windows[2] = window(2, "foot", 13, 1930, 10, 940, 1060)
      hl.windows[3] = window(3, "com.mitchellh.ghostty", 13, 2880, 10, 940, 1060)
    end)
  end)

  it("refuses the previewed plan once the arrangement changed since", function()
    refused_after(function()
      hl.windows[1] = window(1, "foot", 3, 10, 10, 940, 1060)
      hl.windows[2] = window(2, "foot", 3, 960, 10, 950, 1060)
    end)
  end)

  it("refuses a plan previewed for the other scope", function()
    setup(EMPTY)
    local preview = call("capture", { workspace = 3, scope = "workspace" })
    assert.is_true(preview.ok, preview.error)
    local reply = call("capture", { workspace = 3, scope = "all", apply = true, plan = preview.plan })
    assert.is_false(reply.ok)
    assert.matches("capture again", reply.error)
    assert.same({}, call("state").slots)
  end)

  it("takes a preview without a scope as one for all workspaces", function()
    setup(EMPTY)
    local preview = call("capture", { workspace = 3 })
    assert.is_true(call("capture", { workspace = 3, scope = "all", apply = true, plan = preview.plan }).ok)
  end)

  it("refuses a plan that is not a string", function()
    setup(EMPTY)
    local reply = call("capture", { workspace = 3, scope = "all", apply = true, plan = 7 })
    assert.is_false(reply.ok)
    assert.matches("plan must be", reply.error)
    assert.same({}, call("state").slots)
  end)

  it("asks whom an applied capture is for", function()
    setup(EMPTY)
    assert.matches("scope", call("capture", { workspace = 3, apply = true }).error)
  end)
end)
