-- The serializer that writes the editor-owned slots.lua.

local serialize = require("hyprslots.serialize")
local tree = require("hyprslots.tree")

describe("serialize.tree", function()
  local function canonical(text)
    return serialize.tree(assert(tree.parse(text)))
  end

  it("writes a bare slot", function()
    assert.are.equal("main", canonical("main"))
  end)

  it("writes weights other than 1 and leaves out the 1s", function()
    assert.are.equal("h[main:2, right]", canonical("h[main:2, right:1]"))
  end)

  it("writes nested splits with their weights", function()
    assert.are.equal("h[left, v[main, right:2]:2]", canonical("h[ left ,v[main:1,right:2]:2 ]"))
  end)

  it("writes what tree.parse reads back to the same tree", function()
    for _, text in ipairs({ "a", "h[a, b:3]", "v[top, h[a:3, b:5]:2]", "h[v[a, b], v[c, d]:3]" }) do
      local node = assert(tree.parse(text))
      assert.are.same(node, assert(tree.parse(serialize.tree(node))))
    end
  end)

  it("writes the overflow leaf as *, as tree.parse reads it", function()
    for _, text in ipairs({ "h[x:2, v[d, *]]", "v[*:3, h[p, q]]" }) do
      local node = assert(tree.parse(text))
      assert.are.equal(text, serialize.tree(node))
      assert.are.same(node, assert(tree.parse(serialize.tree(node))))
    end
  end)

  it("writes a scroll branch as scroll[...], as tree.parse reads it", function()
    for _, text in ipairs({ "scroll[left, main, right]", "scroll[main]" }) do
      local node = assert(tree.parse(text))
      assert.are.equal(text, serialize.tree(node))
      assert.are.same(node, assert(tree.parse(serialize.tree(node))))
    end
  end)

  it("writes any other split kind the same way", function()
    local node = { split = "q", weight = 1, children = { { slot = "x", weight = 1 }, { slot = "y", weight = 1 } } }
    assert.are.equal("q[x, y]", serialize.tree(node))
  end)
end)

local DATA = {
  slots = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
    [1] = { ["web-1"] = "firefox", term = "kitty/deltaf" },
  },
  arrangements = {
    single = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "h[left, main, right]" } },
    },
    dual = {
      screens = { side = "HEADLESS-3", big = "HEADLESS-2" },
      desks = {
        [3] = { side = "left", big = "h[main:2, right]" },
        [1] = { big = "h[term, web-1]" },
      },
    },
  },
}

-- Load a dumped chunk the way config.lua's load_data does: empty environment.
local function load_text(text)
  local chunk = assert(load(text, "=slots.lua", "t", {}))
  return chunk()
end

describe("serialize.dump", function()
  it("loads back to the same data", function()
    assert.are.same(DATA, load_text(serialize.dump(DATA)))
  end)

  it("is deterministic: the same data always dumps to the same text", function()
    local copy = load_text(serialize.dump(DATA))
    assert.are.equal(serialize.dump(DATA), serialize.dump(copy))
  end)

  it("is a fixpoint: dumping what it loaded gives the same text", function()
    local text = serialize.dump(DATA)
    assert.are.equal(text, serialize.dump(load_text(text)))
  end)

  it("says the file belongs to the editor", function()
    local first = serialize.dump(DATA):match("^[^\n]*")
    assert.matches("^%-%- ", first)
    assert.matches("editor", serialize.dump(DATA))
    assert.matches("config%.lua", serialize.dump(DATA))
  end)

  it("writes a readable, fixed layout", function()
    local expected = [[
return {
  slots = {
    [1] = {
      term = "kitty/deltaf",
      ["web-1"] = "firefox",
    },
    [3] = {
      left = "t-left",
      main = "t-main",
      right = "t-right",
    },
  },
  arrangements = {
    dual = {
      screens = {
        big = "HEADLESS-2",
        side = "HEADLESS-3",
      },
      desks = {
        [1] = {
          big = "h[term, web-1]",
        },
        [3] = {
          big = "h[main:2, right]",
          side = "left",
        },
      },
    },
    single = {
      screens = {
        big = "HEADLESS-2",
      },
      desks = {
        [3] = {
          big = "h[left, main, right]",
        },
      },
    },
  },
}
]]
    local text = serialize.dump(DATA)
    local body = text:sub((text:find("\nreturn {", 1, true) or 0) + 1)
    assert.are.equal(expected, body)
  end)

  it("quotes strings so any content survives", function()
    local data = { slots = { [2] = { odd = 'a "quoted"\nline\\ ]] end' } } }
    assert.are.same(data, load_text(serialize.dump(data)))
  end)

  it("keeps numbers, booleans and lists", function()
    local data = { extra = { list = { "a", "b", "c" }, n = 3, f = 1.5, yes = true, no = false } }
    assert.are.same(data, load_text(serialize.dump(data)))
  end)

  it("puts known keys first in a fixed order, then the rest sorted", function()
    local text = serialize.dump({ zeta = 1, arrangements = {}, alpha = 2, slots = {} })
    local order = {}
    for key in text:gmatch("\n  ([%w_]+) = ") do
      order[#order + 1] = key
    end
    assert.are.same({ "slots", "arrangements", "alpha", "zeta" }, order)
  end)

  it("refuses what a data file cannot hold", function()
    assert.has_error(function() serialize.dump({ f = function() end }) end)
    local cyclic = {}
    cyclic.self = cyclic
    assert.has_error(function() serialize.dump(cyclic) end)
  end)
end)

describe("serialize.write", function()
  local dir

  before_each(function()
    dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
  end)

  after_each(function()
    os.execute("rm -rf '" .. dir .. "'")
  end)

  local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("a")
    file:close()
    return text
  end

  it("writes the dump to the path and leaves no temp file", function()
    local path = dir .. "/slots.lua"
    assert(serialize.write(path, DATA))
    assert.are.equal(serialize.dump(DATA), read(path))
    local listing = io.popen("ls -A '" .. dir .. "'"):read("a")
    assert.are.equal("slots.lua\n", listing)
  end)

  it("replaces an existing file", function()
    local path = dir .. "/slots.lua"
    local file = assert(io.open(path, "w"))
    file:write("old")
    file:close()
    assert(serialize.write(path, DATA))
    assert.are.same(DATA, load_text(read(path)))
  end)

  it("returns an error, not a raise, when it cannot write", function()
    local ok, err = serialize.write(dir .. "/missing/slots.lua", DATA)
    assert.is_nil(ok)
    assert.matches("missing", err)
  end)

  it("returns an error for data it cannot dump, writing nothing", function()
    local path = dir .. "/slots.lua"
    local ok, err = serialize.write(path, { f = function() end })
    assert.is_nil(ok)
    assert.is_string(err)
    assert.is_nil(read(path))
  end)
end)

describe("serialize.tree with sibling node kinds", function()
  it("writes a childless leaf with no slot as the overflow leaf *", function()
    local node = { split = "h", weight = 1, children = {
      { slot = "a", weight = 1 }, { overflow = true, weight = 2 } } }
    assert.are.equal("h[a, *:2]", serialize.tree(node))
  end)
end)
