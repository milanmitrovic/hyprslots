local tree = require("hyprslots.tree")

local function parse(text)
  local node, err = tree.parse(text)
  assert(node, err)
  return node
end

-- Area helpers: x, y, w, h.
local function area(x, y, w, h) return { x = x, y = y, w = w, h = h } end

describe("tree.parse", function()
  it("reads a bare name as a single slot", function()
    assert.are.same({ "main" }, tree.slots(parse("main")))
  end)

  it("reads a split's slots in order", function()
    assert.are.same({ "left", "main", "right" }, tree.slots(parse("h[left, main, right]")))
  end)

  it("reads nested splits depth first", function()
    assert.are.same({ "left", "main", "right" }, tree.slots(parse("h[left, v[main:1, right:2]:2]")))
  end)

  it("tolerates missing and extra whitespace", function()
    assert.are.same({ "a", "b" }, tree.slots(parse("  h[ a:2 ,b ]  ")))
  end)

  it("treats h and v as slot names when no bracket follows", function()
    assert.are.same({ "h", "v" }, tree.slots(parse("h[h, v]")))
  end)

  local function rejects(text, pattern)
    local node, err = tree.parse(text)
    assert.is_nil(node)
    assert.is_string(err)
    assert.matches(pattern, err)
  end

  it("rejects an unclosed split", function() rejects("h[a, b", "expected ']'") end)
  it("rejects an empty split", function() rejects("h[]", "slot name") end)
  it("rejects a zero weight", function() rejects("h[a:0, b]", "positive integer") end)
  it("rejects a fractional weight", function() rejects("h[a:1.5, b]", "positive integer") end)
  it("rejects a weight on the root", function() rejects("h[a, b]:2", "root") end)
  it("rejects trailing text", function() rejects("h[a, b] c", "unexpected") end)
  it("rejects a slot used twice", function() rejects("h[a, v[a, b]]", "'a' appears twice") end)
  it("rejects an unknown split kind", function() rejects("x[a, b]", "unexpected '%['") end)
  it("rejects an empty string", function() rejects("", "slot name") end)
  it("rejects a non-string", function()
    local node, err = tree.parse(42)
    assert.is_nil(node)
    assert.matches("string", err)
  end)
  it("reports where the error is", function() rejects("h[a, b;]", "position 7") end)
end)

describe("tree.boxes", function()
  it("gives a single slot the whole area", function()
    assert.are.same({ main = area(10, 20, 1920, 1080) }, tree.boxes(parse("main"), area(10, 20, 1920, 1080)))
  end)

  it("splits horizontally by integer weights", function()
    assert.are.same({
      main = area(0, 0, 1600, 1350),
      right = area(1600, 0, 800, 1350),
    }, tree.boxes(parse("h[main:2, right:1]"), area(0, 0, 2400, 1350)))
  end)

  it("splits evenly when no weights are given", function()
    assert.are.same({
      left = area(0, 0, 800, 1350),
      main = area(800, 0, 800, 1350),
      right = area(1600, 0, 800, 1350),
    }, tree.boxes(parse("h[left, main, right]"), area(0, 0, 2400, 1350)))
  end)

  it("splits vertically", function()
    assert.are.same({
      top = area(0, 0, 1920, 270),
      bottom = area(0, 270, 1920, 810),
    }, tree.boxes(parse("v[top:1, bottom:3]"), area(0, 0, 1920, 1080)))
  end)

  it("offsets boxes by the area's origin", function()
    assert.are.same({
      a = area(2400, 100, 960, 980),
      b = area(3360, 100, 960, 980),
    }, tree.boxes(parse("h[a, b]"), area(2400, 100, 1920, 980)))
  end)

  it("gives remainder pixels to the last child", function()
    assert.are.same({
      a = area(0, 0, 333, 10),
      b = area(333, 0, 333, 10),
      c = area(666, 0, 334, 10),
    }, tree.boxes(parse("h[a, b, c]"), area(0, 0, 1000, 10)))
  end)

  it("rounds a fractional area to whole pixels", function()
    assert.are.same({ a = area(0, 0, 1920, 1080) }, tree.boxes(parse("a"), area(0.4, -0.2, 1919.6, 1080.3)))
  end)

  -- aerolayout tests/test_sizing_invariant.py, on the 5100x1373 usable area of
  -- a 5120x1440 Odyssey (gaps are Hyprland's business here, not the tree's).
  describe("aerolayout sizing cases", function()
    local odyssey = area(10, 57, 5100, 1373)

    it("lands 1:2 on 1700 + 3400", function()
      local boxes = tree.boxes(parse("h[Left:1, Main:2]"), odyssey)
      assert.are.equal(1700, boxes.Left.w)
      assert.are.equal(3400, boxes.Main.w)
    end)

    it("lands 1:2:1 on 1275 + 2550 + 1275", function()
      local boxes = tree.boxes(parse("h[Left:1, Main:2, Right:1]"), odyssey)
      assert.are.same({ 1275, 2550, 1275 }, { boxes.Left.w, boxes.Main.w, boxes.Right.w })
      assert.are.same({ 10, 1285, 3835 }, { boxes.Left.x, boxes.Main.x, boxes.Right.x })
    end)

    it("lands a vertical 1:3", function()
      local boxes = tree.boxes(parse("v[Top:1, Bottom:3]"), odyssey)
      assert.are.same({ 343, 1030 }, { boxes.Top.h, boxes.Bottom.h })
      assert.are.same({ 57, 400 }, { boxes.Top.y, boxes.Bottom.y })
    end)

    it("renormalises each level of a nested ratio separately", function()
      local boxes = tree.boxes(parse("h[Left:1, v[Main:1, Right:2]:2]"), odyssey)
      assert.are.same(area(10, 57, 1700, 1373), boxes.Left)
      assert.are.same(area(1710, 57, 3400, 457), boxes.Main)
      assert.are.same(area(1710, 514, 3400, 916), boxes.Right)
    end)

    it("keeps the surviving ratio when a slot is empty", function()
      -- Three slots at 1:2:1 with only two apps running: 1:2 of 5100.
      local boxes = tree.boxes(parse("h[Left:1, Main:2, Right:1]"), odyssey, { Left = true, Main = true })
      assert.are.same({ Left = area(10, 57, 1700, 1373), Main = area(1710, 57, 3400, 1373) }, boxes)
    end)
  end)

  describe("with only some slots present", function()
    it("drops a whole branch whose slots are all absent", function()
      local boxes = tree.boxes(parse("h[a, v[b, c]]"), area(0, 0, 1000, 600), { a = true })
      assert.are.same({ a = area(0, 0, 1000, 600) }, boxes)
    end)

    it("keeps a branch with one survivor at the branch's weight", function()
      local boxes = tree.boxes(parse("h[a:1, v[b, c]:3]"), area(0, 0, 1000, 600), { a = true, c = true })
      assert.are.same({ a = area(0, 0, 250, 600), c = area(250, 0, 750, 600) }, boxes)
    end)

    it("places nothing when no slot is present", function()
      assert.are.same({}, tree.boxes(parse("h[a, b]"), area(0, 0, 1000, 600), {}))
    end)
  end)

  it("tiles the area exactly, whatever the weights", function()
    local cases = {
      { "h[a:7, b:3, c:11]", area(0, 0, 2561, 1439) },
      { "v[a:5, h[b:2, c:9, d:1]:4, e]", area(13, 7, 1366, 767) },
      { "h[v[a, b:3]:2, v[c:4, h[d, e:6]]:5]", area(0, 0, 5120, 1440) },
    }
    for _, case in ipairs(cases) do
      local text, a = case[1], case[2]
      local boxes = tree.boxes(parse(text), a)
      local covered = 0
      for slot, box in pairs(boxes) do
        assert.is_true(math.type(box.x) == "integer" and math.type(box.w) == "integer", slot)
        assert.is_true(box.w > 0 and box.h > 0, slot)
        assert.is_true(box.x >= a.x and box.y >= a.y, slot)
        assert.is_true(box.x + box.w <= a.x + a.w and box.y + box.h <= a.y + a.h, slot)
        covered = covered + box.w * box.h
      end
      assert.are.equal(a.w * a.h, covered, text)
      -- No two boxes overlap.
      for s1, b1 in pairs(boxes) do
        for s2, b2 in pairs(boxes) do
          if s1 < s2 then
            local apart = b1.x + b1.w <= b2.x or b2.x + b2.w <= b1.x or b1.y + b1.h <= b2.y or b2.y + b2.h <= b1.y
            assert.is_true(apart, text .. ": " .. s1 .. " overlaps " .. s2)
          end
        end
      end
    end
  end)
end)

describe("accordions (gone)", function()
  local function rejects(text, pattern)
    local node, err = tree.parse(text)
    assert.is_nil(node)
    assert.matches(pattern, err)
  end

  it("refuses a[...], pointing to scroll[...]", function()
    rejects("a[left, main, right]",
      "a%[...%] %(an accordion, a Hyprland group with tabs%) is gone: write scroll%[left, main, right%] for "
        .. "full%-width scrolling columns at position 1")
  end)

  it("refuses one inside a split too", function()
    rejects("h[a[x, y], d]", "a%[...%] %(an accordion, a Hyprland group with tabs%) is gone")
  end)

  it("still reads a as a slot name when no bracket follows", function()
    assert.are.same({ "a", "b" }, tree.slots(parse("h[a, b]")))
  end)
end)

describe("scroll containers", function()
  local function rejects(text, pattern)
    local node, err = tree.parse(text)
    assert.is_nil(node)
    assert.matches(pattern, err)
  end

  it("reads a scroll branch's slots in order", function()
    local node = parse("scroll[left, main, right]")
    assert.are.same({ "left", "main", "right" }, tree.slots(node))
    assert.are.same({ "left", "main", "right" }, tree.scroll(node))
  end)

  it("takes a single slot", function()
    assert.are.same({ "main" }, tree.scroll(parse("scroll[main]")))
  end)

  it("is no scroll branch when the tree is a split or a slot", function()
    assert.is_nil(tree.scroll(parse("h[left, main]")))
    assert.is_nil(tree.scroll(parse("main")))
  end)

  it("treats scroll as a slot name when no bracket follows", function()
    assert.are.same({ "scroll", "b" }, tree.slots(parse("h[scroll, b]")))
    assert.are.same({ "scroll", "b" }, tree.scroll(parse("scroll[scroll, b]")))
  end)

  it("rejects a scroll container below the root, saying it is the whole branch", function()
    rejects("h[scroll[x, y], d]", "scroll%[...%] is a whole screen's tree, found it inside a split at position 3")
  end)

  it("rejects a split inside a scroll container", function()
    rejects("scroll[x, v[y, z]]", "scroll%[...%] holds slots only, found 'v%[' inside it at position 11")
  end)

  it("rejects a weight inside a scroll container", function()
    rejects("scroll[x:2, y]", "columns of scroll%[...%] take no weight")
  end)

  it("places the overflow leaf among its columns, where windows with no slot go", function()
    local node = parse("scroll[left, main, *, right]")
    assert.are.same({ "left", "main", "right" }, tree.scroll(node))
    assert.are.same({ "left", "main", tree.OVERFLOW, "right" }, tree.columns(node))
    assert.is_true(tree.has_overflow(node))
  end)

  it("has no overflow column when the branch does not place one", function()
    assert.are.same({ "left", "main" }, tree.columns(parse("scroll[left, main]")))
    assert.is_false(tree.has_overflow(parse("scroll[left, main]")))
    assert.is_nil(tree.columns(parse("h[left, main]")))
  end)

  it("rejects the overflow leaf twice in a scroll container", function()
    rejects("scroll[x, *, *]", "more than one overflow leaf '%*'")
  end)

  it("rejects a weight on its overflow column", function()
    rejects("scroll[x, *:2]", "columns of scroll%[...%] take no weight")
  end)

  it("rejects a slot used twice", function()
    rejects("scroll[x, y, x]", "'x' appears twice")
  end)

  it("lays its columns out side by side when lua:slots has to show it", function()
    local boxes = tree.boxes(parse("scroll[x, y, z]"), area(0, 0, 2400, 1350))
    assert.are.same({ x = area(0, 0, 800, 1350), y = area(800, 0, 800, 1350), z = area(1600, 0, 800, 1350) }, boxes)
  end)

  it("closes up around absent columns", function()
    local boxes = tree.boxes(parse("scroll[x, y, z]"), area(0, 0, 2400, 1350), { x = true, z = true })
    assert.are.same({ x = area(0, 0, 1200, 1350), z = area(1200, 0, 1200, 1350) }, boxes)
  end)

  it("lays its overflow column out where it stands when lua:slots has to show it", function()
    local boxes = tree.boxes(tree.with_overflow(parse("scroll[x, *, y]")), area(0, 0, 2400, 1350))
    assert.are.same({ x = area(0, 0, 800, 1350), ["*"] = area(800, 0, 800, 1350), y = area(1600, 0, 800, 1350) }, boxes)
  end)
end)

describe("the overflow leaf", function()
  local function rejects(text, pattern)
    local node, err = tree.parse(text)
    assert.is_nil(node)
    assert.matches(pattern, err)
  end

  it("is written * and is not a slot", function()
    local node = parse("h[main:2, v[right, *]]")
    assert.are.same({ "main", "right" }, tree.slots(node))
    assert.is_true(tree.has_overflow(node))
    assert.is_false(tree.has_overflow(parse("h[main, right]")))
  end)

  it("takes a weight like any leaf", function()
    local boxes = tree.boxes(parse("h[main:3, *:1]"), area(0, 0, 2400, 1350))
    assert.are.same({ main = area(0, 0, 1800, 1350), [tree.OVERFLOW] = area(1800, 0, 600, 1350) }, boxes)
  end)

  it("closes up when no window overflows", function()
    local boxes = tree.boxes(parse("h[main:3, *:1]"), area(0, 0, 2400, 1350), { main = true })
    assert.are.same({ main = area(0, 0, 2400, 1350) }, boxes)
  end)

  it("is laid out when present", function()
    local boxes = tree.boxes(parse("h[*, main]"), area(0, 0, 2400, 1350), { main = true, [tree.OVERFLOW] = true })
    assert.are.same({ [tree.OVERFLOW] = area(0, 0, 1200, 1350), main = area(1200, 0, 1200, 1350) }, boxes)
  end)

  -- aerolayout: validate_tree, "more than one overflow slot".
  it("rejects a second overflow leaf", function()
    rejects("h[*, v[main, *]]", "more than one overflow leaf")
  end)

  describe("tree.with_overflow", function()
    -- aerolayout TestOverflowGuarantee: a tree with no overflow leaf still
    -- places extra windows, at the end; an explicit position is respected.
    it("appends a column at 3 : 1 to a tree without one", function()
      local node = tree.with_overflow(parse("h[a, b]"))
      local boxes = tree.boxes(node, area(0, 0, 2400, 1350))
      assert.are.same({
        a = area(0, 0, 900, 1350),
        b = area(900, 0, 900, 1350),
        [tree.OVERFLOW] = area(1800, 0, 600, 1350),
      }, boxes)
    end)

    it("wraps a lone slot too", function()
      local boxes = tree.boxes(tree.with_overflow(parse("main")), area(0, 0, 2400, 1350))
      assert.are.same({ main = area(0, 0, 1800, 1350), [tree.OVERFLOW] = area(1800, 0, 600, 1350) }, boxes)
    end)

    it("respects an explicit overflow leaf", function()
      local node = parse("h[*, a]")
      assert.are.equal(node, tree.with_overflow(node))
    end)

    it("does not modify the tree it is given", function()
      local node = parse("h[a:2, b]")
      tree.with_overflow(node)
      assert.are.same({ "a", "b" }, tree.slots(node))
      assert.are.equal(2, node.children[1].weight)
      assert.are.equal(1, node.weight)
      assert.is_false(tree.has_overflow(node))
    end)
  end)
end)
