-- Test seam S2: what the editor's Assignment view needs from the api
-- (docs/design.md §9): overflowing windows in `state`, and the `assign` /
-- `unassign` calls that put a window into a slot, or take it out, by hand.

local engine = require("helpers.engine")
local hl_stub = require("helpers.hl_stub")

local BLOCKS = { ["HEADLESS-2"] = 0, ["HEADLESS-3"] = 1 }

describe("the Assignment view's api", function()
  local hl, hyprslots

  local function open(id, class, workspace, title)
    local window = hl_stub.window(id, class, { title = title or class, workspace = hl.get_workspace(workspace) })
    hl.windows[#hl.windows + 1] = window
    hl.get_workspace(workspace).windows = hl.get_workspace(workspace).windows + 1
    hl.emit("window.open", window)
    return window
  end

  local function close(window)
    for i, w in ipairs(hl.windows) do
      if w == window then
        table.remove(hl.windows, i)
      end
    end
    hl.emit("window.close", window)
  end

  local function state()
    return engine.state(hyprslots)
  end

  local function call(name, args)
    return engine.call(hyprslots, name, require("hyprslots.dkjson").encode(args or {}))
  end

  local function window_entry(s, window)
    for _, entry in ipairs(s.windows) do
      if entry.address == window.address then
        return entry
      end
    end
  end

  before_each(function()
    hl = engine.stub({ "HEADLESS-2", "HEADLESS-3" }, BLOCKS)
    hl_stub.simulate(hl)
    hl.add_workspace(1, "HEADLESS-2")
    hl.add_workspace(3, "HEADLESS-2")
    hl.add_workspace(13, "HEADLESS-3")
    -- dual: side = "left", big = "h[main:2, right:1]"
    hyprslots = engine.setup(engine.TWO_SCREENS)
  end)

  after_each(engine.cleanup)

  describe("state", function()
    it("lists the windows that overflow, with the slot whose desk holds them", function()
      open(1, "t-left", 1)
      local extra = open(2, "t-left", 1)
      local s = state()
      assert.are.same({ [extra.address] = { desk = 3, slot = "left" } }, s.overflow)
      assert.are.same({ desk = 3, slot = "left" }, window_entry(s, extra).overflow)
    end)

    it("lists no overflow when every matched window has a slot", function()
      open(1, "t-left", 1)
      assert.are.same({}, state().overflow)
    end)
  end)

  describe("assign", function()
    it("puts a window into a slot by hand and moves it to the slot's workspace", function()
      local stranger = open(1, "firefox", 1)
      local reply = call("assign", { address = stranger.address, desk = 3, slot = "right" })
      assert.is_true(reply.ok, reply.error)
      assert.are.same({ desk = 3, slot = "right", manual = true }, state().assignments[stranger.address])
      assert.are.equal(3, stranger.workspace.id)
    end)

    it("refuses a window that is not open, a slot that is not defined, or no desk, and says why", function()
      local stranger = open(1, "firefox", 1)
      local seq = state().seq
      local gone = call("assign", { address = "0xdead", desk = 3, slot = "right" })
      assert.are.same({ ok = false, error = "no open window 0xdead" }, gone)
      local no_slot = call("assign", { address = stranger.address, desk = 3, slot = "nope" })
      assert.are.same({ ok = false, error = "no slot 'nope' (add it in the editor's Layout tab, s then a)" }, no_slot)
      local no_desk = call("assign", { address = stranger.address, desk = 11, slot = "main" })
      assert.are.same({ ok = false, error = "a desk must be an integer from 1 to 10, got 11" }, no_desk)
      assert.is_nil(state().assignments[stranger.address])
      assert.are.equal(seq, state().seq)
    end)

    it("puts a window into a global slot on a desk that has no spec for it, and keeps it there", function()
      local stranger = open(1, "firefox", 1)
      local reply = call("assign", { address = stranger.address, desk = 7, slot = "main" })
      assert.is_true(reply.ok, reply.error)
      assert.are.same({ desk = 7, slot = "main", manual = true }, state().assignments[stranger.address])
      assert.is_true(call("reload").ok)
      assert.are.same({ desk = 7, slot = "main", manual = true }, state().assignments[stranger.address])
    end)

    it("takes the slot from the window holding it, which overflows when no other slot takes it", function()
      local holder = open(1, "t-main", 1)
      local stranger = open(2, "firefox", 1)
      local reply = call("assign", { address = stranger.address, desk = 3, slot = "main" })
      assert.are.equal(holder.address, reply.displaced)
      local s = state()
      assert.are.same({ desk = 3, slot = "main", manual = true }, s.assignments[stranger.address])
      assert.is_nil(s.assignments[holder.address])
      assert.are.same({ desk = 3, slot = "main" }, s.overflow[holder.address])
      assert.are.same({ 3, 3 }, { stranger.workspace.id, holder.workspace.id })
    end)

    it("frees the window's own slot for the oldest window overflowing on it", function()
      local first = open(1, "t-main", 1)
      local extra = open(2, "t-main", 1)
      assert.are.same({ desk = 3, slot = "main" }, state().overflow[extra.address])
      call("assign", { address = first.address, desk = 3, slot = "left" })
      local s = state()
      assert.are.same({ desk = 3, slot = "left", manual = true }, s.assignments[first.address])
      assert.are.same({ desk = 3, slot = "main" }, s.assignments[extra.address])
      assert.are.same({}, s.overflow)
      assert.are.same({ 13, 3 }, { first.workspace.id, extra.workspace.id })
    end)

    it("swaps an overflowing window with the one holding its slot", function()
      local first = open(1, "t-main", 1)
      local extra = open(2, "t-main", 1)
      local reply = call("assign", { address = extra.address, desk = 3, slot = "main" })
      assert.are.equal(first.address, reply.displaced)
      local s = state()
      assert.are.same({ desk = 3, slot = "main", manual = true }, s.assignments[extra.address])
      assert.are.same({ [first.address] = { desk = 3, slot = "main" } }, s.overflow)
    end)

    it("makes a window's own slot hand-made, displacing nobody", function()
      local first = open(1, "t-main", 1)
      local reply = call("assign", { address = first.address, desk = 3, slot = "main" })
      assert.is_nil(reply.displaced)
      assert.are.same({ desk = 3, slot = "main", manual = true }, state().assignments[first.address])
    end)

    it("holds through a re-solve though the slot's spec does not match the window", function()
      local stranger = open(1, "firefox", 1)
      call("assign", { address = stranger.address, desk = 3, slot = "right" })
      local right = open(2, "t-right", 1)
      assert.is_true(call("reload").ok)
      local s = state()
      assert.are.same({ desk = 3, slot = "right", manual = true }, s.assignments[stranger.address])
      assert.are.same({ desk = 3, slot = "right" }, s.overflow[right.address])
    end)

    it("ends when the slot is gone from the config, and the window is matched as usual", function()
      local stranger = open(1, "firefox", 1)
      call("assign", { address = stranger.address, desk = 3, slot = "right" })
      local file = assert(io.open(state().config.data_file, "w"))
      file:write([[
return {
  slots = { [3] = { left = "t-left", main = "t-main" } },
  arrangements = {
    dual = { screens = { big = "HEADLESS-2", side = "HEADLESS-3" }, desks = { [3] = { side = "left", big = "main" } } },
  },
}
]])
      file:close()
      assert.is_true(call("reload").ok)
      assert.is_nil(state().assignments[stranger.address])
    end)

    it("tells the editor once, and replies with the new seq", function()
      local holder = open(1, "t-main", 1)
      local stranger = open(2, "firefox", 1)
      local before = #hl.dispatched_of("event")
      local reply = call("assign", { address = stranger.address, desk = 3, slot = "main" })
      assert.are.same({ ok = true, address = stranger.address, desk = 3, slot = "main", displaced = holder.address,
        seq = state().seq }, reply)
      assert.are.equal(before + 1, #hl.dispatched_of("event"))
    end)

    it("is refused while hyprslots is off", function()
      local stranger = open(1, "firefox", 1)
      _G.o.workspaces.enabled = false
      hl.emit("config.reloaded")
      local reply = call("assign", { address = stranger.address, desk = 3, slot = "main" })
      assert.is_false(reply.ok)
      assert.matches("hyprslots is off", reply.error)
    end)
  end)

  describe("unassign", function()
    it("takes a window out of its slot, leaves it where it is, and gives the slot to the oldest overflow", function()
      local first = open(1, "t-main", 1)
      local extra = open(2, "t-main", 1)
      local reply = call("unassign", { address = first.address })
      assert.is_true(reply.ok, reply.error)
      local s = state()
      assert.is_nil(s.assignments[first.address])
      assert.are.same({ desk = 3, slot = "main" }, s.assignments[extra.address])
      assert.are.same({}, s.overflow)
      assert.are.same({ first.address }, s.unassigned)
      assert.is_true(window_entry(s, first).unassigned)
      assert.are.same({ 3, 3 }, { first.workspace.id, extra.workspace.id })
    end)

    it("keeps the window out of every slot it matches: layout, title, re-solve", function()
      local first = open(1, "t-main", 1)
      call("unassign", { address = first.address })
      hl.layouts.slots.recalculate(hl_stub.layout_ctx({ x = 0, y = 0, w = 2400, h = 1350 }, { first }))
      first.title = "t-main again"
      hl.emit("window.title", first)
      hl.run_timers()
      assert.is_true(call("reload").ok)
      local s = state()
      assert.is_nil(s.assignments[first.address])
      assert.are.same({}, s.overflow)
      assert.are.same({ first.address }, s.unassigned)
    end)

    it("lasts until the window is assigned again", function()
      local first = open(1, "t-main", 1)
      call("unassign", { address = first.address })
      call("assign", { address = first.address, desk = 3, slot = "main" })
      local s = state()
      assert.are.same({ desk = 3, slot = "main", manual = true }, s.assignments[first.address])
      assert.are.same({}, s.unassigned)
    end)

    it("is forgotten when the window closes", function()
      local first = open(1, "t-main", 1)
      call("unassign", { address = first.address })
      close(first)
      assert.are.same({}, state().unassigned)
    end)

    it("refuses a window that is not open", function()
      assert.are.same({ ok = false, error = "no open window 0xdead" }, call("unassign", { address = "0xdead" }))
    end)

    it("replies with the slot the window gave up, and tells the editor once", function()
      local first = open(1, "t-main", 1)
      local before = #hl.dispatched_of("event")
      local reply = call("unassign", { address = first.address })
      assert.are.same({ ok = true, address = first.address, desk = 3, slot = "main", seq = state().seq }, reply)
      assert.are.equal(before + 1, #hl.dispatched_of("event"))
    end)
  end)
end)
