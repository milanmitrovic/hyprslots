-- Test seam S3: each global slot's key (docs/design.md §4), the one letter
-- that picks it in every slot-choice prompt of the editor. slot_key.pick
-- chooses one for a new slot; slot_key.fill gives one to every slot that
-- has none (migration, normalization); slot_key.check says what is wrong
-- with a key.

local slot_key = require("hyprslots.slot_key")

describe("slot_key.pick", function()
  it("takes the name's first letter when no other slot uses it", function()
    assert.are.equal("m", slot_key.pick("main", {}))
    assert.are.equal("n", slot_key.pick("Notes", {}), "lower case")
  end)

  it("takes the name's next unused letter when the first is used", function()
    assert.are.equal("a", slot_key.pick("main", { m = true }))
    assert.are.equal("i", slot_key.pick("main", { m = true, a = true }))
    assert.are.equal("d", slot_key.pick("mmd", { m = true }), "a repeated letter is as used as the first")
  end)

  it("skips what is no letter in the name: digits jump workspaces", function()
    assert.are.equal("t", slot_key.pick("2nd-term", { n = true, d = true }))
    assert.are.equal("x", slot_key.pick("_x9", {}))
  end)

  it("takes the first unused letter a-z when every letter of the name is used", function()
    assert.are.equal("b", slot_key.pick("aa", { a = true }))
    assert.are.equal("c", slot_key.pick("ab", { a = true, b = true }))
  end)

  it("has none when every letter is used", function()
    local all = {}
    for code = string.byte("a"), string.byte("z") do
      all[string.char(code)] = true
    end
    assert.is_nil(slot_key.pick("main", all))
  end)
end)

describe("slot_key.fill", function()
  it("keys the user's slots left, main, right as l, m, r", function()
    local slots = { left = {}, main = { description = "the editor" }, right = {} }
    assert.is_true(slot_key.fill(slots))
    assert.are.same({ left = { key = "l" }, main = { key = "m", description = "the editor" }, right = { key = "r" } },
      slots)
  end)

  it("goes in slot name order, so the same slots always get the same keys", function()
    local slots = { mail = {}, main = {}, music = {} }
    slot_key.fill(slots)
    assert.are.same({ mail = { key = "m" }, main = { key = "a" }, music = { key = "u" } }, slots)
  end)

  it("keeps the keys slots have, and keys the rest around them", function()
    local slots = { main = { key = "x" }, mail = {}, xterm = {} }
    assert.is_true(slot_key.fill(slots))
    assert.are.same({ main = { key = "x" }, mail = { key = "m" }, xterm = { key = "t" } }, slots)
  end)

  it("says nothing changed when every slot has a key", function()
    local slots = { main = { key = "m" }, left = { key = "q" } }
    assert.is_false(slot_key.fill(slots))
    assert.are.same({ main = { key = "m" }, left = { key = "q" } }, slots)
  end)

  it("leaves a slot keyless once all 26 letters are taken, and a key it cannot read for validation", function()
    local slots = {}
    for code = string.byte("a"), string.byte("z") do
      slots["s" .. string.char(code)] = { key = string.char(code) }
    end
    slots.extra = {}
    slots.odd = { key = "1" }
    slot_key.fill(slots)
    assert.is_nil(slots.extra.key)
    assert.are.equal("1", slots.odd.key)
  end)

  it("passes over what is no slot table", function()
    local slots = { main = "kitty", [3] = {} }
    assert.is_false(slot_key.fill(slots))
    assert.is_false(slot_key.fill(nil))
  end)
end)

describe("slot_key.check", function()
  it("takes one lower-case letter", function()
    assert.is_nil(slot_key.check("m"))
  end)

  it("refuses anything else, saying a key is one letter a-z", function()
    for _, bad in ipairs({ "M", "1", "mm", "", " ", "-", 4 }) do
      assert.matches("one letter a%-z", slot_key.check(bad), tostring(bad))
    end
  end)
end)
