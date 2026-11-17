-- The engine's half of launching apps (launcher.lua): the claim a launch
-- holds on its slot ("<n>/<slot>" in engine.launching) and launched_for,
-- which hands a window that opens the slot it was launched for. The calls
-- that launch (launch_missing, at login) are pinned in launch_api_spec.lua.

local launcher = require("hyprslots.launcher")
local spec = require("hyprslots.spec")

describe("launcher claims", function()
  it("key a slot of a workspace as <n>/<slot>", function()
    assert.are.equal("3/main", launcher.claim_key(3, "main"))
    assert.are.equal("10/aside", launcher.claim_key(10, "aside"))
  end)

  it("read back to the workspace, as a number, and the slot", function()
    local n, slot = launcher.claim_of("10/aside")
    assert.are.equal(10, n)
    assert.are.equal("number", type(n))
    assert.are.equal("aside", slot)
  end)

  it("round-trip", function()
    for _, case in ipairs({ { 1, "main" }, { 9, "left" }, { 10, "notes" } }) do
      local n, slot = launcher.claim_of(launcher.claim_key(case[1], case[2]))
      assert.are.same(case, { n, slot })
    end
  end)

  it("keep everything after the first / as the slot", function()
    local n, slot = launcher.claim_of("4/a/b")
    assert.are.equal(4, n)
    assert.are.equal("a/b", slot)
  end)

  it("are nil for a key that is no claim", function()
    assert.is_nil(launcher.claim_of("main"))
    assert.is_nil(launcher.claim_of("x/main"))
    assert.is_nil(launcher.claim_of("3/"))
    assert.is_nil(launcher.claim_of(""))
  end)
end)

describe("launcher.launched_for", function()
  -- An engine with these specs (workspace -> slot -> text), claims and
  -- assignments.
  local function engine_with(specs, claims, assignments)
    local parsed = {}
    for n, entries in pairs(specs) do
      parsed[n] = {}
      for slot, text in pairs(entries) do
        parsed[n][slot] = assert(spec.parse(text))
      end
    end
    local launching = {}
    for _, key in ipairs(claims) do
      launching[key] = true
    end
    return { cfg = { specs = parsed }, launching = launching, assignments = assignments or {} }
  end

  local foot = { address = "0x1", class = "foot", title = "~" }

  it("is nil with no launch on its way", function()
    assert.is_nil(launcher.launched_for(engine_with({ [3] = { main = "foot" } }, {}), foot))
    assert.is_nil(launcher.launched_for({ cfg = { specs = {} }, assignments = {} }, foot))
  end)

  it("gives the window the slot it was launched for and uses the claim up", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { "3/main" })
    assert.are.same({ workspace = 3, slot = "main" }, launcher.launched_for(engine, foot))
    assert.is_nil(engine.launching["3/main"])
    assert.is_nil(launcher.launched_for(engine, foot), "once")
  end)

  it("takes the first waiting slot by workspace number, not as text", function()
    local engine = engine_with({ [5] = { main = "foot" }, [10] = { main = "foot" } }, { "10/main", "5/main" })
    assert.are.same({ workspace = 5, slot = "main" }, launcher.launched_for(engine, foot))
    assert.is_true(engine.launching["10/main"], "the other claim still waits")
  end)

  it("then by slot name", function()
    local engine = engine_with({ [3] = { main = "foot", aside = "foot" } }, { "3/main", "3/aside" })
    assert.are.same({ workspace = 3, slot = "aside" }, launcher.launched_for(engine, foot))
  end)

  it("skips a slot whose spec the window does not match", function()
    local engine = engine_with({ [3] = { main = "firefox" } }, { "3/main" })
    assert.is_nil(launcher.launched_for(engine, foot))
    assert.is_true(engine.launching["3/main"], "the claim stays for its app")
  end)

  it("skips a slot a window already holds", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { "3/main" },
      { ["0x9"] = { workspace = 3, slot = "main" } })
    assert.is_nil(launcher.launched_for(engine, foot))
  end)

  it("skips a claim whose slot has no spec any more, and a key that is no claim", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { "3/gone", "junk", "3/main" })
    assert.are.same({ workspace = 3, slot = "main" }, launcher.launched_for(engine, foot))
  end)
end)
