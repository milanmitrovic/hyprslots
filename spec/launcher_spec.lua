-- The engine's half of launching apps (launcher.lua): the claim a launch
-- holds on its slot (engine.launching, workspace -> slot -> claim, which
-- only launcher.lua touches) and launched_for, which hands a window that
-- opens the slot it was launched for. The calls that launch
-- (launch_missing, at login) are pinned in launch_api_spec.lua.

local hl_stub = require("helpers.hl_stub")
local launcher = require("hyprslots.launcher")
local spec = require("hyprslots.spec")

describe("launcher claims", function()
  local hl, saved_hl

  before_each(function()
    saved_hl = _G.hl
    hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2") } })
    _G.hl = hl
  end)

  after_each(function()
    _G.hl = saved_hl
  end)

  it("are none on an engine that never launched", function()
    local engine = {}
    assert.are.same({}, launcher.pending_for(engine, 3))
    assert.is_false(launcher.claimed(engine, 3, "main"))
    launcher.release(engine, 3, "main")
    assert.is_nil(engine.launching)
  end)

  it("hold a slot of a workspace, keyed by the workspace as a number", function()
    local engine = {}
    launcher.claim(engine, 10, "aside")
    launcher.claim(engine, 3, "main")
    launcher.claim(engine, 3, "a/b")
    assert.is_true(launcher.claimed(engine, 10, "aside"))
    assert.is_false(launcher.claimed(engine, "10", "aside"), "not as text")
    assert.are.same({ main = true, ["a/b"] = true }, launcher.pending_for(engine, 3))
    assert.are.same({ aside = true }, launcher.pending_for(engine, 10))
    assert.are.same({}, launcher.pending_for(engine, 1))
  end)

  it("pending_for is a copy: changing it leaves the claims", function()
    local engine = {}
    launcher.claim(engine, 3, "main")
    launcher.pending_for(engine, 3).main = nil
    assert.is_true(launcher.claimed(engine, 3, "main"))
  end)

  it("run out after their wait", function()
    local engine = {}
    launcher.claim(engine, 3, "main", 500)
    assert.equal(1, #hl.timers)
    assert.equal(500, hl.timers[1].opts.timeout)
    hl.run_timers()
    assert.is_false(launcher.claimed(engine, 3, "main"))
    assert.is_nil(engine.launching[3], "an emptied workspace goes")
  end)

  it("wait LAUNCH_WAIT_MS by default", function()
    launcher.claim({}, 3, "main")
    assert.equal(20000, hl.timers[1].opts.timeout)
  end)

  it("a claim's expiry leaves a later claim on the same slot", function()
    local engine = {}
    launcher.claim(engine, 3, "main")
    launcher.release(engine, 3, "main") -- its window took it
    launcher.claim(engine, 3, "main") -- launched again
    hl.timers[1].callback() -- the first claim's wait ends
    assert.is_true(launcher.claimed(engine, 3, "main"))
    hl.timers[2].callback()
    assert.is_false(launcher.claimed(engine, 3, "main"))
  end)

  it("release ends one slot's claim and leaves the others", function()
    local engine = {}
    launcher.claim(engine, 3, "main")
    launcher.claim(engine, 3, "aside")
    launcher.release(engine, 3, "main")
    assert.are.same({ aside = true }, launcher.pending_for(engine, 3))
    launcher.release(engine, 3, "gone")
    launcher.release(engine, 4, "main")
    assert.are.same({ aside = true }, launcher.pending_for(engine, 3))
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
    -- claims: { n, slot } pairs, held as launcher.claim holds them.
    local launching = {}
    for _, claim in ipairs(claims) do
      launching[claim[1]] = launching[claim[1]] or {}
      launching[claim[1]][claim[2]] = {}
    end
    return { cfg = { specs = parsed }, launching = launching, assignments = assignments or {} }
  end

  local foot = { address = "0x1", class = "foot", title = "~" }

  it("is nil with no launch on its way", function()
    assert.is_nil(launcher.launched_for(engine_with({ [3] = { main = "foot" } }, {}), foot))
    assert.is_nil(launcher.launched_for({ cfg = { specs = {} }, assignments = {} }, foot))
  end)

  it("gives the window the slot it was launched for and uses the claim up", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { { 3, "main" } })
    assert.are.same({ workspace = 3, slot = "main" }, launcher.launched_for(engine, foot))
    assert.is_false(launcher.claimed(engine, 3, "main"))
    assert.is_nil(launcher.launched_for(engine, foot), "once")
  end)

  it("takes the first waiting slot by workspace number, not as text", function()
    local engine = engine_with({ [5] = { main = "foot" }, [10] = { main = "foot" } }, { { 10, "main" }, { 5, "main" } })
    assert.are.same({ workspace = 5, slot = "main" }, launcher.launched_for(engine, foot))
    assert.is_true(launcher.claimed(engine, 10, "main"), "the other claim still waits")
  end)

  it("then by slot name", function()
    local engine = engine_with({ [3] = { main = "foot", aside = "foot" } }, { { 3, "main" }, { 3, "aside" } })
    assert.are.same({ workspace = 3, slot = "aside" }, launcher.launched_for(engine, foot))
  end)

  it("skips a slot whose spec the window does not match", function()
    local engine = engine_with({ [3] = { main = "firefox" } }, { { 3, "main" } })
    assert.is_nil(launcher.launched_for(engine, foot))
    assert.is_true(launcher.claimed(engine, 3, "main"), "the claim stays for its app")
  end)

  it("skips a slot a window already holds", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { { 3, "main" } },
      { ["0x9"] = { workspace = 3, slot = "main" } })
    assert.is_nil(launcher.launched_for(engine, foot))
  end)

  it("skips a claim whose slot has no spec any more, and one whose workspace has none", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { { 3, "gone" }, { 4, "main" }, { 3, "main" } })
    assert.are.same({ workspace = 3, slot = "main" }, launcher.launched_for(engine, foot))
    assert.is_true(launcher.claimed(engine, 3, "gone"), "left to run out")
    assert.is_true(launcher.claimed(engine, 4, "main"))
  end)

  it("drops a workspace whose last claim it uses up", function()
    local engine = engine_with({ [3] = { main = "foot" } }, { { 3, "main" } })
    launcher.launched_for(engine, foot)
    assert.is_nil(engine.launching[3])
  end)
end)
