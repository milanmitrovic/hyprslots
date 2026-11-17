-- capture_apply.fingerprint: the short token a capture preview hands the
-- editor, which an apply must give back unchanged (the api's capture refuses
-- an apply whose plan changed since the preview, capture_api_spec.lua).

local capture_apply = require("hyprslots.capture_apply")

describe("capture_apply.fingerprint", function()
  local trees = { ["1"] = { tree = "h[main, aside]", ratio = "1:1" }, ["2"] = false }
  local new_slots = { { slot = "foot", key = "f" } }
  local windows = {
    { address = "0x1", slot = "main", spec = "firefox", new = false },
    { address = "0x2", slot = "foot", spec = "foot", new = true },
  }

  local function token(over)
    over = over or {}
    return capture_apply.fingerprint(over.n or 3, over.scope or "workspace",
      over.layout or "solo", over.trees or trees, over.new_slots or new_slots, over.windows or windows)
  end

  it("is eight hex digits", function()
    assert.is_truthy(token():match("^%x%x%x%x%x%x%x%x$"))
  end)

  it("is the same for the same capture", function()
    assert.are.equal(token(), token())
  end)

  it("counts no scope as \"all\", as a preview without one shows", function()
    assert.are.equal(capture_apply.fingerprint(3, nil, "solo", trees, new_slots, windows),
      capture_apply.fingerprint(3, "all", "solo", trees, new_slots, windows))
    assert.are_not.equal(token({ scope = "all" }), token())
  end)

  it("changes with the workspace, the layout and any screen's tree", function()
    local base = token()
    assert.are_not.equal(base, token({ n = 4 }))
    assert.are_not.equal(base, token({ layout = "other" }))
    assert.are_not.equal(base, token({ trees = { ["1"] = { tree = "h[main, aside]", ratio = "1:2" }, ["2"] = false } }))
    assert.are_not.equal(base, token({ trees = { ["1"] = trees["1"] } }), "a screen left with no tree counts")
  end)

  it("changes with the new slots and their keys", function()
    assert.are_not.equal(token(), token({ new_slots = { { slot = "foot", key = "o" } } }))
  end)

  it("changes when a window opens, closes, moves slot, changes spec or newness", function()
    local base = token()
    local function with(change)
      local copy = {}
      for i, w in ipairs(windows) do
        copy[i] = { address = w.address, slot = w.slot, spec = w.spec, new = w.new }
      end
      change(copy)
      return token({ windows = copy })
    end
    assert.are_not.equal(base, with(function(c)
      c[#c + 1] = { address = "0x3", slot = "x", spec = "x", new = true }
    end))
    assert.are_not.equal(base, with(function(c) table.remove(c) end))
    assert.are_not.equal(base, with(function(c) c[1].slot = "aside" end))
    assert.are_not.equal(base, with(function(c) c[1].spec = "foot" end))
    assert.are_not.equal(base, with(function(c) c[2].new = false end))
  end)
end)
