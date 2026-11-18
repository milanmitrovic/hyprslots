-- Test seam S3: capture.lua, the pure half of "turn what is on screen into a
-- layout" (docs/design.md §9, Capture): a slot name for each window's app,
-- and a tiled screen's ratios snapped to the editor's 1 to 5 arrangements.

local capture = require("hyprslots.capture")

describe("capture.slot_name", function()
  it("is the app's class, lower case, its reverse-domain prefix and vendor dropped", function()
    assert.equal("ghostty", capture.slot_name("com.mitchellh.ghostty"))
    assert.equal("chrome", capture.slot_name("google-chrome"))
    assert.equal("edge", capture.slot_name("microsoft-edge"))
    assert.equal("brave", capture.slot_name("brave-browser"))
    assert.equal("nautilus", capture.slot_name("org.gnome.Nautilus"))
    assert.equal("alacritty", capture.slot_name("Alacritty"))
    assert.equal("foot", capture.slot_name("foot"))
  end)

  it("is a valid slot name whatever the class holds", function()
    assert.equal("my_app", capture.slot_name("My App"))
    assert.equal("app-2048", capture.slot_name("2048"))
    assert.equal("app", capture.slot_name(""))
    assert.equal("app", capture.slot_name(nil))
  end)

  it("is short", function()
    assert.equal("averyverylongapp", capture.slot_name("averyverylongapplicationname"))
  end)
end)

describe("capture.weights", function()
  it("snaps a split to the 1 to 5 arrangement nearest what was measured", function()
    assert.same({ 2, 1 }, capture.weights({ 1265, 625 }))
    assert.same({ 1, 1, 1 }, capture.weights({ 630, 640, 625 }))
    assert.same({ 3, 2 }, capture.weights({ 1150, 760 }))
  end)

  it("falls back on record's own snapping where no 1 to 5 arrangement is near", function()
    -- 7:1 is no arrangement of weights 1 to 5 (the nearest, 5:1, is 4% off).
    assert.same({ 7, 1 }, capture.weights({ 1680, 240 }))
  end)
end)

describe("capture.plan", function()
  local serialize = require("hyprslots.serialize")
  local spec = require("hyprslots.spec")
  local tree = require("hyprslots.tree")

  local function box(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
  end

  local function win(n, class, b, fields)
    local w = { address = string.format("0x%x", 0x100 + n), class = class, title = class, box = b }
    for k, v in pairs(fields or {}) do
      w[k] = v
    end
    return w
  end

  local function parsed(text)
    return assert(tree.parse(text))
  end

  local function plan(input)
    input.workspace = input.workspace or 3
    input.slots = input.slots or {}
    input.specs = input.specs or {}
    input.assignments = input.assignments or {}
    local out, err = capture.plan(input)
    assert.is_nil(err)
    return out
  end

  local function texts(trees)
    local out = {}
    for screen, node in pairs(trees) do
      out[screen] = node and serialize.tree(node) or false
    end
    return out
  end

  it("makes a slot per app, named after it, records the screen as its tree and gives each its window's spec", function()
    -- foot on the left two thirds, two more stacked on the right (Hyprland's gaps between).
    local out = plan({ screens = { { windows = {
      win(1, "foot", box(10, 10, 1260, 1060)),
      win(2, "foot", box(1280, 10, 630, 525)),
      win(3, "foot", box(1280, 545, 630, 525)),
    } } } })
    assert.same({ "foot", "foot-2", "foot-3" }, out.new_slots)
    assert.same({ [1] = "h[foot:2, v[foot-2, foot-3]]" }, texts(out.trees))
    -- spec.from_window's: foot's title rule names a window by its title (session) too.
    assert.same({ foot = "foot/foot", ["foot-2"] = "foot/foot", ["foot-3"] = "foot/foot" }, out.specs)
    assert.same({ ["0x101"] = "foot", ["0x102"] = "foot-2", ["0x103"] = "foot-3" }, out.assign)
  end)

  it("keeps the slot a window holds on the workspace, and its spec when that matches it", function()
    local out = plan({
      slots = { main = {} },
      specs = { main = assert(spec.parse("foot/deltaf")) },
      assignments = { ["0x101"] = { workspace = 3, slot = "main" } },
      screens = { { windows = {
        win(1, "foot", box(0, 0, 950, 1080), { title = "deltaf | zellij" }),
        win(2, "com.mitchellh.ghostty", box(960, 0, 960, 1080)),
      } } },
    })
    assert.same({ "ghostty" }, out.new_slots)
    assert.same({ [1] = "h[main, ghostty]" }, texts(out.trees))
    assert.same({ ghostty = "com.mitchellh.ghostty" }, out.specs)
    assert.same({ ["0x101"] = "main", ["0x102"] = "ghostty" }, out.assign)
  end)

  it("puts a window into a free slot whose spec on the workspace matches it", function()
    local out = plan({
      slots = { chat = {} },
      specs = { chat = assert(spec.parse("slack")) },
      screens = { { windows = { win(1, "slack", box(0, 0, 1920, 1080)) } } },
    })
    assert.same({}, out.new_slots)
    assert.same({ ["0x101"] = "chat" }, out.assign)
    assert.same({}, out.specs)
  end)

  it("reuses a slot of the app's name the workspace leaves empty, and skips one it fills", function()
    local out = plan({
      slots = { foot = {}, ["foot-2"] = {} },
      specs = { foot = assert(spec.parse("kitty")) },
      screens = { { windows = { win(1, "foot", box(0, 0, 1920, 1080)) } } },
    })
    assert.same({}, out.new_slots)
    assert.same({ ["0x101"] = "foot-2" }, out.assign)
    assert.same({ ["foot-2"] = "foot/foot" }, out.specs)
  end)

  it("names apps left to right, then top to bottom", function()
    local out = plan({ screens = { { windows = {
      win(1, "google-chrome", box(960, 0, 960, 1080)),
      win(2, "google-chrome", box(0, 0, 950, 1080)),
    } } } })
    assert.same({ ["0x102"] = "chrome", ["0x101"] = "chrome-2" }, out.assign)
  end)

  it("records a scrolling screen as a scroll branch in column order, half or full width as its columns are", function()
    local out = plan({ screens = {
      { scroll = true, windows = {
        win(1, "foot", box(0, 0, 950, 1080), { column = 1, column_width = 0.5 }),
        win(2, "kitty", box(0, 0, 950, 1080), { column = 0, column_width = 0.5 }),
      } },
      { scroll = true, windows = { win(3, "slack", box(0, 0, 1900, 1080), { column = 0, column_width = 0.99 }) } },
    } })
    assert.same({ [1] = "scroll:0.5[kitty, foot]", [2] = "scroll[slack]" }, texts(out.trees))
  end)

  it("keeps the width of the scroll branch the screen has", function()
    local out = plan({ screens = { { scroll = true, current = parsed("scroll[a, b]"), windows = {
      win(1, "foot", box(0, 0, 950, 1080), { column = 0, column_width = 0.5 }),
    } } }, slots = { a = {}, b = {} } })
    assert.same({ [1] = "scroll[foot, a, b]" }, texts(out.trees))
  end)

  it("keeps the slots a screen's tree had and no window fills at its end, and takes captured ones off other screens", function()
    local out = plan({
      slots = { main = {}, side = {}, notes = {}, chat = {} },
      assignments = { ["0x101"] = { workspace = 3, slot = "side" } },
      screens = {
        { current = parsed("h[main, notes]"), windows = { win(1, "foot", box(0, 0, 1920, 1080)) } },
        { current = parsed("v[side, chat]"), windows = {} },
      },
    })
    assert.same({ [1] = "h[side, main, notes]", [2] = "chat" }, texts(out.trees))
  end)

  it("leaves a screen with nothing left no tree", function()
    local out = plan({
      slots = { side = {} },
      assignments = { ["0x101"] = { workspace = 3, slot = "side" } },
      screens = {
        { windows = { win(1, "foot", box(0, 0, 1920, 1080)) } },
        { current = parsed("side"), windows = {} },
      },
    })
    assert.same({ [1] = "side", [2] = false }, texts(out.trees))
  end)

  it("refuses windows that overlap, and a workspace with no windows", function()
    local _, err = capture.plan({ workspace = 3, slots = {}, specs = {}, assignments = {}, screens = { { windows = {
      win(1, "foot", box(0, 0, 1000, 1000)), win(2, "kitty", box(500, 500, 1000, 1000)),
    } } } })
    assert.matches("overlap", err)
    _, err = capture.plan({ workspace = 3, slots = {}, specs = {}, assignments = {}, screens = { { windows = {} } } })
    assert.equal("no windows on workspace 3 to capture", err)
  end)
end)
