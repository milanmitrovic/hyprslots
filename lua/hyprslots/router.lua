-- Window events -> slot assignment and moves (docs/design.md §7).
--
-- On window.open a window matching a slot is assigned to it (sticky) and,
-- when it opened on another workspace, moved to the slot's: workspace N on
-- the screen whose tree holds the slot under the active desk. Moves happen
-- here, in the event callback, never in recalculate. window.close frees the
-- slot (window.destroy's window has no address left in Hyprland 0.56.2). A
-- target workspace that does not exist yet is created where Hyprland puts it
-- (the focused monitor) and then moved to its screen.
--
-- Overflow: a window that matches some slot's spec while every such slot is
-- taken goes to the workspace of the first slot that matches it, in
-- precedence order, where the layout puts it in that branch's overflow leaf
-- (engine.overflow remembers it). It follows that workspace on hotplug and
-- edits, and takes a slot as soon as one it matches is freed. A window that matches
-- no spec at all stays where it opened.
--
-- Late titles: on window.title a window with no slot (overflowing or not) is
-- matched again once its title has been quiet for TITLE_DEBOUNCE_MS (one
-- oneshot timer per window, replaced on every change), against the title it
-- has then, and routed like a new window. A window with a slot never moves
-- because its title changed: assignment is sticky.
--
-- By hand (the editor's assign / unassign): assign puts a window into a slot
-- whatever its spec says; unassign takes it out, and it takes no slot until
-- it is assigned again or closes (engine.unassigned).

local adapter = require("hyprslots.hl_adapter")
local assign = require("hyprslots.assign")
local window_rules = require("hyprslots.window_rules")

local M = {}

M.TITLE_DEBOUNCE_MS = 150

local function find_window(address)
  for _, window in ipairs(adapter.windows()) do
    if window.address == address then
      return window
    end
  end
  return nil
end

function M.window_opened(engine, hl_window)
  if engine.refused or not engine.cfg then
    return
  end
  M.route(engine, adapter.window(hl_window))
end

-- Assign a plain window to a slot and move it to the slot's workspace, or,
-- when every slot it matches is taken, to the first such slot's workspace
-- (its overflow leaf).
function M.route(engine, window)
  if engine.unassigned[window.address] then
    return -- taken out of its slot by hand: it stays where it is
  end
  local had = engine.assignments[window.address]
  local assignment = engine:assign(window)
  if assignment and not had then
    window_rules.sync(engine)
  end
  local what = "slot"
  if assignment then
    engine.overflow[window.address] = nil
  else
    assignment = assign.first_match(engine.cfg, window)
    engine.overflow[window.address] = assignment
    if not assignment then
      engine.log:info("open %s (%s): no slot", tostring(window.class), tostring(window.address))
      return
    end
    what = "overflow of slot"
  end

  local target = engine:workspace_for(assignment)
  if not target then
    engine.log:info("open %s: %s %s on workspace %d is on no screen of the active desk",
      window.class, what, assignment.slot, assignment.workspace)
    return
  end

  if window.workspace_id == target then
    -- A generated window rule opened it there, possibly on a workspace it
    -- created on the focused screen.
    engine.log:info("open %s: %s %s, already on workspace %d", window.class, what, assignment.slot, target)
    M.keep_on_screen(engine, target)
    return
  end

  engine.log:info("open %s: %s %s, workspace %s -> %d", window.class, what, assignment.slot,
    tostring(window.workspace_id), target)
  M.place(engine, window.address, target)
end

-- Move a window to a workspace and make sure that workspace sits on its
-- screen. Hyprland creates a missing workspace on the FOCUSED monitor, and
-- there is no way to create one elsewhere without showing it, so it is moved
-- over afterwards; it is hidden, so neither screen's view nor focus changes.
function M.place(engine, address, target)
  adapter.move_window(address, target)
  M.keep_on_screen(engine, target)
end

-- Move a workspace to its screen when it is on another one.
function M.keep_on_screen(engine, target)
  local entry = engine.workspaces[target]
  local monitor = entry and entry.monitor
  local actual = adapter.workspace_monitor(target)
  if monitor and actual and actual ~= monitor then
    engine.log:info("workspace %d: %s -> %s", target, actual, monitor)
    adapter.move_workspace(target, monitor)
  end
end

-- Move every assigned window to its slot's workspace under the active desk
-- (after hotplug or an edit), and every overflowing window to its
-- workspace's. Windows that match no slot, or whose slot no screen of the
-- desk holds, stay where they are. Then ask for a deferred scroll
-- pass (scroll.lua), which must see the windows where they have just been
-- moved.
function M.reroute_all(engine)
  if engine.refused or not engine.active then
    return
  end
  for _, window in ipairs(adapter.windows()) do
    local assignment = window.address and engine.assignments[window.address]
    local what = "slot"
    if window.address and not assignment then
      assignment, what = engine.overflow[window.address], "overflow of slot"
    end
    local target = assignment and engine:workspace_for(assignment)
    if target and window.workspace_id ~= target then
      engine.log:info("re-route %s: %s %s, workspace %s -> %d", tostring(window.class), what, assignment.slot,
        tostring(window.workspace_id), target)
      M.place(engine, window.address, target)
    end
  end
  if engine.rearrange then
    engine.rearrange("event")
  end
end

function M.window_title(engine, hl_window)
  local address = hl_window and hl_window.address
  if engine.refused or not engine.cfg or not address or engine.assignments[address] then
    return
  end
  engine.title_timers = engine.title_timers or {}
  local pending = engine.title_timers[address]
  if pending then
    pending:set_enabled(false)
  end
  engine.title_timers[address] = adapter.defer(function()
    engine.title_timers[address] = nil
    engine:guard("window.title", function()
      if engine.assignments[address] then
        return
      end
      local window = find_window(address)
      if window then
        engine.log:info("title %s: %s", tostring(window.class), tostring(window.title))
        M.route(engine, window)
      end
    end)
  end, M.TITLE_DEBOUNCE_MS)
end

function M.window_destroyed(engine, hl_window)
  local address = hl_window and hl_window.address
  local pending = address and engine.title_timers and engine.title_timers[address]
  if pending then
    pending:set_enabled(false)
    engine.title_timers[address] = nil
  end
  if address then
    engine.overflow[address] = nil
    engine.unassigned[address] = nil
  end
  if address and engine.assignments[address] then
    local assignment = engine.assignments[address]
    engine.assignments[address] = nil
    engine.log:info("destroy %s: slot %s on workspace %d is free", address, assignment.slot, assignment.workspace)
    M.promote(engine)
    window_rules.sync(engine)
  end
end

-- Put a window ({ address, workspace_id, ... }) into a slot by hand (the
-- editor's assign): it holds the slot until it closes, through re-solves,
-- whatever its spec says (assign.lua honours `manual`). It is moved to the
-- slot's workspace like a routed window. The window that held the slot is
-- routed again, as if it had just opened: into another free slot it matches,
-- else its workspace's overflow. The slot the window leaves goes to the oldest
-- window overflowing on it. Returns the new assignment and the displaced
-- window's address.
function M.assign(engine, window, workspace, slot)
  local address = window.address
  local displaced
  for other, held in pairs(engine.assignments) do
    if other ~= address and held.workspace == workspace and held.slot == slot then
      displaced = other
    end
  end
  if displaced then
    engine.assignments[displaced] = nil
  end
  local previous = engine.assignments[address]
  local assignment = { workspace = workspace, slot = slot, manual = true }
  engine.assignments[address] = assignment
  engine.overflow[address] = nil
  engine.unassigned[address] = nil
  local target = engine:workspace_for(assignment)
  if target and window.workspace_id ~= target then
    engine.log:info("assign %s (%s) to slot %s on workspace %d, workspace %s -> %d", tostring(window.class), address,
      slot, workspace, tostring(window.workspace_id), target)
    M.place(engine, address, target)
  elseif target then
    M.keep_on_screen(engine, target)
  end
  local other = displaced and find_window(displaced)
  if other then
    engine.log:info("assign: %s (%s) gives up slot %s on workspace %d", tostring(other.class), displaced, slot,
      workspace)
    M.route(engine, other)
  end
  if previous and (previous.workspace ~= workspace or previous.slot ~= slot) then
    M.promote(engine) -- the slot it left
  end
  window_rules.sync(engine)
  if engine.rearrange then
    engine.rearrange("event")
  end
  engine:relayout()
  engine:changed()
  return assignment, displaced
end

-- Take a window out of its slot by hand (the editor's unassign). It stays
-- where it is and takes no slot until it closes or is assigned again
-- (engine.unassigned); the slot it held goes to the oldest window
-- overflowing on it. Returns the assignment it had, if any.
function M.unassign(engine, address)
  local previous = engine.assignments[address]
  engine.assignments[address] = nil
  engine.overflow[address] = nil
  engine.unassigned[address] = true
  if previous then
    engine.log:info("unassign %s: slot %s on workspace %d is free", address, previous.slot, previous.workspace)
    M.promote(engine)
  end
  window_rules.sync(engine)
  if engine.rearrange then
    engine.rearrange("event")
  end
  engine:relayout()
  engine:changed()
  return previous
end

-- Give freed slots to overflowing windows, oldest first, and route them.
function M.promote(engine)
  if next(engine.overflow) == nil then
    return
  end
  local waiting = {}
  for _, window in ipairs(adapter.windows()) do
    if window.address and engine.overflow[window.address] then
      waiting[#waiting + 1] = window
    end
  end
  table.sort(waiting, function(a, b)
    if a.stable_id ~= b.stable_id then
      return (a.stable_id or 0) < (b.stable_id or 0)
    end
    return a.address < b.address
  end)
  for _, window in ipairs(waiting) do
    if engine:assign(window) then
      engine.log:info("promote %s (%s) out of the overflow", tostring(window.class), window.address)
      M.route(engine, window)
    end
  end
end

return M
