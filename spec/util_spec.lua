-- The helpers the engine's modules share (util.lua): one gcd, round, trim,
-- set_of, sorted_keys, shallow and deep_copy instead of a copy per module.

local util = require("hyprslots.util")

describe("util.gcd", function()
  it("is the greatest common divisor", function()
    assert.are.equal(6, util.gcd(12, 18))
    assert.are.equal(6, util.gcd(18, 12), "either order")
    assert.are.equal(1, util.gcd(7, 5), "coprime")
  end)

  it("is the other number when one is 0, so a fold can start from 0", function()
    assert.are.equal(4, util.gcd(0, 4))
    assert.are.equal(4, util.gcd(4, 0))
    local common = 0
    for _, n in ipairs({ 4, 6, 10 }) do
      common = util.gcd(common, n)
    end
    assert.are.equal(2, common)
  end)
end)

describe("util.round", function()
  it("rounds to the nearest integer, halves up", function()
    assert.are.equal(2, util.round(1.5))
    assert.are.equal(1, util.round(1.49))
    assert.are.equal(-1, util.round(-1.5))
    assert.are.equal(3, util.round(3))
  end)

  it("gives an integer, fit for pixel sizes", function()
    assert.are.equal("integer", math.type(util.round(2.7)))
  end)
end)

describe("util.trim", function()
  it("drops leading and trailing whitespace only", function()
    assert.are.equal("a b", util.trim("  a b \t\n"))
    assert.are.equal("", util.trim("   "))
    assert.are.equal("x", util.trim("x"))
  end)

  it("returns the text alone, not gsub's count", function()
    assert.are.equal(1, select("#", util.trim(" x ")))
  end)
end)

describe("util.set_of", function()
  it("maps each value to true", function()
    assert.are.same({ a = true, b = true }, util.set_of({ "a", "b", "a" }))
    assert.are.same({}, util.set_of({}))
  end)
end)

describe("util.sorted_keys", function()
  it("sorts numbers and strings by value", function()
    assert.are.same({ 1, 2, 10 }, util.sorted_keys({ [10] = true, [2] = true, [1] = true }))
    assert.are.same({ "a", "b", "c" }, util.sorted_keys({ c = 1, a = 1, b = 1 }))
  end)

  it("puts numbers before strings", function()
    assert.are.same({ 1, 3, "default", "x" }, util.sorted_keys({ x = 1, default = 1, [3] = 1, [1] = 1 }))
  end)

  it("orders any other key types without raising", function()
    local t = {}
    local keys = util.sorted_keys({ [true] = 1, [false] = 1, s = 1, [2] = 1, [t] = 1 })
    assert.are.same({ 2, false, true, "s", t }, keys)
  end)

  it("has no keys for nil or an empty table", function()
    assert.are.same({}, util.sorted_keys(nil))
    assert.are.same({}, util.sorted_keys({}))
  end)
end)

describe("util.shallow", function()
  it("copies one level: a new table sharing the inner ones", function()
    local inner = { 1 }
    local original = { a = 1, inner = inner }
    local copy = util.shallow(original)
    assert.are_not.equal(original, copy)
    assert.are.same(original, copy)
    assert.are.equal(inner, copy.inner)
  end)

  it("is an empty table for nil", function()
    assert.are.same({}, util.shallow(nil))
  end)
end)

describe("util.deep_copy", function()
  it("copies every level", function()
    local original = { a = { b = { 1, 2 } }, n = 3 }
    local copy = util.deep_copy(original)
    assert.are.same(original, copy)
    assert.are_not.equal(original.a, copy.a)
    assert.are_not.equal(original.a.b, copy.a.b)
    copy.a.b[1] = 9
    assert.are.equal(1, original.a.b[1])
  end)

  it("returns anything but a table as it is", function()
    assert.are.equal(5, util.deep_copy(5))
    assert.are.equal("s", util.deep_copy("s"))
    assert.is_nil(util.deep_copy(nil))
  end)
end)
