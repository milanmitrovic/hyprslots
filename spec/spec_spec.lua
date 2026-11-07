local spec = require("hyprslots.spec")

local function parsed(text)
  local s, err = spec.parse(text)
  assert(s, err)
  return s
end

describe("spec", function()
  it("matches a window by its class", function()
    assert.is_true(spec.match(parsed("t-main"), { class = "t-main", title = "anything" }))
  end)

  it("does not match another class", function()
    assert.is_false(spec.match(parsed("t-main"), { class = "t-left" }))
  end)

  it("matches the class exactly, not as a pattern or prefix", function()
    assert.is_false(spec.match(parsed("t.main"), { class = "t-main" }))
    assert.is_false(spec.match(parsed("t-main"), { class = "t-main2" }))
  end)

  it("does not match a window with no class yet", function()
    assert.is_false(spec.match(parsed("t-main"), { class = "" }))
    assert.is_false(spec.match(parsed("t-main"), {}))
  end)

  it("keeps the text it was parsed from", function()
    assert.are.equal("kitty", parsed("kitty").text)
  end)

  it("trims surrounding whitespace", function()
    assert.is_true(spec.match(parsed("  kitty "), { class = "kitty" }))
  end)

  it("rejects an empty spec", function()
    local s, err = spec.parse("  ")
    assert.is_nil(s)
    assert.matches("empty", err)
  end)

  it("rejects a non-string", function()
    local s, err = spec.parse({})
    assert.is_nil(s)
    assert.matches("string", err)
  end)

  it("rejects title and tag forms until the full grammar lands", function()
    for _, text in ipairs({ "kitty/deltaf", "[Work]/Default" }) do
      local s, err = spec.parse(text)
      assert.is_nil(s, text)
      assert.matches("only class specs", err)
    end
  end)
end)
