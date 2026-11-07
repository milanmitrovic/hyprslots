-- The ratio grammar (ported from aerolayout's nested ratio editor,
-- tests/test_nested_ratio.py): one string sets every split of a tree.
--
--   ratio := term (':' term)*
--   term  := (number | '*') ('[' ratio ']')?

local ratio = require("hyprslots.ratio")
local tree = require("hyprslots.tree")

local function parse_tree(text)
  return assert(tree.parse(text))
end

local function terms(text)
  local parsed, err = ratio.parse(text)
  assert(parsed, err)
  return parsed
end

local function rejects(text, fragment)
  local parsed, err = ratio.parse(text)
  assert.is_nil(parsed)
  assert.is_truthy(err:lower():find(fragment, 1, true), "error was: " .. tostring(err))
end

-- A term as { weight, nested } for comparisons.
local function t(weight, nested)
  return { weight = weight, nested = nested }
end

describe("ratio.parse", function()
  it("reads a flat ratio", function()
    assert.are.same({ t(1), t(2), t(1) }, terms("1:2:1"))
  end)

  it("takes spaces as separators", function()
    assert.are.same({ t(1), t(2), t(1) }, terms("1 2 1"))
    assert.are.same({ t(1), t(2) }, terms(" 1 : 2 "))
  end)

  it("reads a nested term", function()
    assert.are.same({ t(2, { t(1), t(2) }), t(1) }, terms("2[1:2]:1"))
  end)

  it("reads two nested terms", function()
    local parsed = terms("1[1:3]:1[3:1]")
    assert.are.same({ t(1), t(3) }, parsed[1].nested)
    assert.are.same({ t(3), t(1) }, parsed[2].nested)
  end)

  it("reads deep nesting", function()
    assert.are.same({ t(1), t(1) }, terms("1[2[1:1]:1]:1")[1].nested[1].nested)
  end)

  it("reads decimal weights", function()
    assert.are.same({ t(1.5), t(1) }, terms("1.5:1"))
  end)

  it("reads a single value", function()
    assert.are.same({ t(3) }, terms("3"))
  end)

  it("reads * as a term, nested or not", function()
    assert.are.same({ t("*"), t(1), t("*") }, terms("*:1:*"))
    assert.are.same({ t("*", { t(1), t(2) }) }, terms("*[1:2]"))
  end)

  it("rejects zero and negatives", function()
    rejects("0:1", "greater than zero")
    rejects("-1:1", "greater than zero")
  end)

  it("rejects what is not a number", function() rejects("a:1", "not a number") end)
  it("rejects an unclosed bracket", function() rejects("2[1:2", "unclosed") end)
  it("rejects a trailing separator", function() rejects("1:", "stray") end)
  it("rejects a stray closing bracket", function() rejects("1:2]", "unexpected") end)
  it("rejects empty brackets", function() rejects("1[]:2", 'expected a number, found "]"') end)
  it("rejects a leading bracket", function() rejects("[1:2]:1", 'expected a number, found "["') end)
  it("rejects an empty ratio", function() rejects("", "empty") end)
  it("rejects a non-string", function()
    local parsed, err = ratio.parse(nil)
    assert.is_nil(parsed)
    assert.matches("string", err)
  end)
end)

-- The weights of a node's children, and of a nested child's children.
local function weights(node)
  local out = {}
  for i, child in ipairs(node.children) do
    out[i] = child.weight
  end
  return out
end

local function apply(text_tree, text_ratio)
  local applied, err = ratio.apply(parse_tree(text_tree), text_ratio)
  assert(applied, err)
  return applied
end

local function apply_rejects(text_tree, text_ratio, fragment)
  local node = parse_tree(text_tree)
  local applied, err = ratio.apply(node, text_ratio)
  assert.is_nil(applied)
  assert.is_truthy(err:find(fragment, 1, true), "error was: " .. tostring(err))
end

local H_WITH_V = "h[v[left, main], right]"
local GRID = "h[v[a, b], v[c, d]]"

describe("ratio.apply", function()
  it("sets both levels", function()
    local node = apply(H_WITH_V, "2[1:2]:1")
    assert.are.same({ 2, 1 }, weights(node))
    assert.are.same({ 1, 2 }, weights(node.children[1]))
  end)

  it("reaches a container with no window child", function()
    local node = apply(GRID, "3[1:3]:1[3:1]")
    assert.are.same({ 3, 1 }, weights(node))
    assert.are.same({ 1, 3 }, weights(node.children[1]))
    assert.are.same({ 3, 1 }, weights(node.children[2]))
  end)

  it("leaves sub-ratios alone when the entry is flat", function()
    local node = assert(ratio.apply(apply(H_WITH_V, "2[1:2]:1"), "5:1"))
    assert.are.same({ 5, 1 }, weights(node))
    assert.are.same({ 1, 2 }, weights(node.children[1]))
  end)

  it("turns decimals into the smallest integer ratio", function()
    assert.are.same({ 3, 2 }, weights(apply("h[a, b]", "1.5:1")))
    assert.are.same({ 1, 1, 2 }, weights(apply("h[a, b, c]", "0.25:0.25:0.5")))
    assert.are.same({ 137, 100 }, weights(apply("h[a, b]", "1.37:1")))
  end)

  it("reduces a common factor", function()
    assert.are.same({ 1, 2, 1 }, weights(apply("h[a, b, c]", "2:4:2")))
  end)

  it("returns a new tree and leaves the one it was given untouched", function()
    local node = parse_tree(H_WITH_V)
    local applied = assert(ratio.apply(node, "2[1:2]:1"))
    assert.are_not.equal(node, applied)
    assert.are.same({ 1, 1 }, weights(node))
    assert.are.same({ 1, 1 }, weights(node.children[1]))
  end)

  it("keeps slot names and split kinds", function()
    local node = apply(H_WITH_V, "2[1:2]:1")
    assert.are.same({ "left", "main", "right" }, tree.slots(node))
    assert.are.equal("h", node.split)
    assert.are.equal("v", node.children[1].split)
  end)

  it("refuses the wrong number of values", function()
    apply_rejects(H_WITH_V, "1:2:3", "expected 2 values for the outer container, got 3")
  end)

  it("names a deeper cell by position", function()
    apply_rejects(H_WITH_V, "2[1:2:3]:1", "expected 2 values for cell 1, got 3")
  end)

  it("names a cell three levels down with its parent", function()
    apply_rejects("h[v[a, h[b, c]], d]", "1[1:1[1:1:1]]:1", "expected 2 values for cell 1 > cell 2, got 3")
  end)

  it("says value, singular, for a one-child container", function()
    local node = { split = "h", weight = 1, children = { { split = "v", weight = 1, children = { { slot = "a", weight = 1 } } }, { slot = "b", weight = 1 } } }
    local applied, err = ratio.apply(node, "1[1:1]:1")
    assert.is_nil(applied)
    assert.is_truthy(err:find("expected 1 value for cell 1, got 2", 1, true), err)
  end)

  it("refuses nesting into a window, naming its slot", function()
    apply_rejects(H_WITH_V, "2:1[1:1]", "right is a window, so it has nothing to split")
  end)

  it("refuses a ratio for a tree that is a single window", function()
    apply_rejects("main", "1:1", "the outer container is a window, not a split")
  end)

  it("refuses a * among tiles, naming the container", function()
    apply_rejects("h[a, b]", "*:1", "* is an accordion pane with no share of its own, and the outer container is tiled")
    apply_rejects(H_WITH_V, "2[*:1]:1", "cell 1 is tiled")
  end)

  it("reports syntax errors", function()
    apply_rejects("h[a, b]", "1:", "stray")
  end)

  it("refuses a non-tree", function()
    local applied, err = ratio.apply(nil, "1:1")
    assert.is_nil(applied)
    assert.matches("tree", err)
  end)
end)

-- An accordion node, the way any split kind other than h/v reads here.
local function accordion(...)
  local children = {}
  for i, name in ipairs({ ... }) do
    children[i] = type(name) == "table" and name or { slot = name, weight = 1 }
  end
  return { split = "a", weight = 1, children = children }
end

describe("ratio on accordions", function()
  it("writes nothing for * and 1 cells", function()
    local acc = accordion("a", "b", "c")
    acc.children[1].weight = 3
    local applied = assert(ratio.apply(acc, "*:1:*"))
    assert.are.same({ 3, 1, 1 }, weights(applied))
  end)

  it("is a no-op as a cell of a tiled ratio", function()
    local node = { split = "h", weight = 1, children = { accordion("a", "b", "c"), { slot = "right", weight = 1 } } }
    local applied = assert(ratio.apply(node, "2[*:1:*]:1"))
    assert.are.same({ 2, 1 }, weights(applied))
    assert.are.same({ 1, 1, 1 }, weights(applied.children[1]))
  end)

  it("still applies the ratio of a tiled cell inside it", function()
    local acc = accordion("a", { split = "h", weight = 1, children = { { slot = "b", weight = 1 }, { slot = "c", weight = 1 } } })
    local applied = assert(ratio.apply(acc, "*:*[3:1]"))
    assert.are.same({ 3, 1 }, weights(applied.children[2]))
  end)

  it("refuses numbers on an accordion", function()
    local applied, err = ratio.apply(accordion("a", "b", "c"), "3:1:1")
    assert.is_nil(applied)
    assert.is_truthy(err:find("ratios don't apply to the outer container", 1, true), err)
    assert.is_truthy(err:find("accordion", 1, true), err)
  end)

  it("formats every accordion pane as *", function()
    local node = { split = "h", weight = 1, children = { accordion("a", "b", "c"), { slot = "right", weight = 1 } } }
    node.children[1].weight = 2
    assert.are.equal("2[*:*:*]:1", ratio.format(node))
  end)
end)

describe("ratio.format", function()
  it("renders equal shares as ones, never a word", function()
    assert.are.equal("1:1:1", ratio.format(parse_tree("h[a, b, c]")))
  end)

  it("renders every split below the root, set or not", function()
    assert.are.equal("1[1:1[1:1]]:1", ratio.format(parse_tree("h[v[a, h[b, c]], d]")))
    assert.are.equal("2[1:1]:1", ratio.format(parse_tree("h[v[a, b]:2, c]")))
  end)

  it("renders weights reduced", function()
    assert.are.equal("1:2:1", ratio.format(parse_tree("h[a:2, b:4, c:2]")))
  end)

  it("renders a single window as an empty string", function()
    assert.are.equal("", ratio.format(parse_tree("main")))
  end)

  local SHAPES = {
    { "h[a, b, c]", nil },
    { "h[a, b, c]", "1:2:1" },
    { H_WITH_V, "2[1:2]:1" },
    { GRID, "3[1:3]:1[3:1]" },
    { "h[v[a, h[b, c]], d]", "2[1:3[1:2]]:1" },
    { "h[a, b, c]", "1:1.37:2.5" },
    { "v[top, h[a:3, b:5]:2]", nil },
  }

  for _, shape in ipairs(SHAPES) do
    local text, entry = shape[1], shape[2]
    local label = text .. (entry and (" at " .. entry) or "")

    it("round-trips " .. label, function()
      local node = parse_tree(text)
      if entry then node = apply(text, entry) end
      local shown = ratio.format(node)
      local again = assert(ratio.apply(node, shown))
      assert.are.equal(shown, ratio.format(again))
      assert.are.same(node, again, "feeding the shown ratio back moves no share")
    end)
  end
end)
