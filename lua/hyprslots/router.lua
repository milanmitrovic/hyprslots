-- Window events -> slot assignment and moves (docs/design.md §7).
--
-- On window.open a window matching a slot is assigned to it (sticky) and,
-- when it opened on another workspace, moved to the slot's: desk N on the
-- screen whose tree holds the slot in the active arrangement. Moves happen
-- here, in the event callback, never in recalculate. window.destroy frees the
-- slot. Title-based re-routing arrives with the full spec grammar (slice 3).

local adapter = require("hyprslots.hl_adapter")

local M = {}

function M.window_opened(engine, hl_window)
  if engine.refused or not engine.cfg then
    return
  end

  local window = adapter.window(hl_window)
  local assignment = engine:assign(window)
  if not assignment then
    engine.log:info("open %s (%s): no slot", tostring(window.class), tostring(window.address))
    return
  end

  local target = engine:workspace_for(assignment)
  if not target then
    engine.log:info("open %s: slot %s on desk %d is on no screen of the active arrangement",
      window.class, assignment.slot, assignment.desk)
    return
  end

  if window.workspace_id == target then
    engine.log:info("open %s: slot %s, already on workspace %d", window.class, assignment.slot, target)
    return
  end

  engine.log:info("open %s: slot %s, workspace %s -> %d", window.class, assignment.slot,
    tostring(window.workspace_id), target)
  adapter.move_window(window.address, target)
end

function M.window_destroyed(engine, hl_window)
  local address = hl_window and hl_window.address
  if address and engine.assignments[address] then
    local assignment = engine.assignments[address]
    engine.assignments[address] = nil
    engine.log:info("destroy %s: slot %s on desk %d is free", address, assignment.slot, assignment.desk)
  end
end

return M
