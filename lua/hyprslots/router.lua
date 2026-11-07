-- Window events -> slot assignment and moves (docs/design.md §7).
--
-- On window.open a window matching a slot is assigned to it (sticky) and,
-- when it opened on another workspace, moved to the slot's: desk N on the
-- screen whose tree holds the slot in the active arrangement. Moves happen
-- here, in the event callback, never in recalculate. window.destroy frees the
-- slot. A target workspace that does not exist yet is created where Hyprland
-- puts it (the focused monitor) and then moved to its screen.
--
-- Late titles: on window.title a window with no slot is matched again once
-- its title has been quiet for TITLE_DEBOUNCE_MS (one oneshot timer per
-- window, replaced on every change), against the title it has then, and
-- routed like a new window when it matches. A window with a slot never moves
-- because its title changed: assignment is sticky.

local adapter = require("hyprslots.hl_adapter")
local window_rules = require("hyprslots.window_rules")

local M = {}

M.TITLE_DEBOUNCE_MS = 150

function M.window_opened(engine, hl_window)
  if engine.refused or not engine.cfg then
    return
  end
  M.route(engine, adapter.window(hl_window))
end

-- Assign a plain window to a slot and move it to the slot's workspace.
function M.route(engine, window)
  local had = engine.assignments[window.address]
  local assignment = engine:assign(window)
  if assignment and not had then
    window_rules.sync(engine)
  end
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
    -- A generated window rule opened it there, possibly on a workspace it
    -- created on the focused screen.
    engine.log:info("open %s: slot %s, already on workspace %d", window.class, assignment.slot, target)
    M.keep_on_screen(engine, target)
    return
  end

  engine.log:info("open %s: slot %s, workspace %s -> %d", window.class, assignment.slot,
    tostring(window.workspace_id), target)
  M.place(engine, window.address, target)
end

-- Move a window to a desk workspace and make sure that workspace sits on its
-- screen. Hyprland creates a missing workspace on the FOCUSED monitor, and
-- there is no way to create one elsewhere without showing it, so it is moved
-- over afterwards; it is hidden, so neither screen's view nor focus changes.
function M.place(engine, address, target)
  adapter.move_window(address, target)
  M.keep_on_screen(engine, target)
end

-- Move a desk workspace to its screen when it is on another one.
function M.keep_on_screen(engine, target)
  local desk = engine.workspaces[target]
  local monitor = desk and desk.monitor
  local actual = adapter.workspace_monitor(target)
  if monitor and actual and actual ~= monitor then
    engine.log:info("workspace %d: %s -> %s", target, actual, monitor)
    adapter.move_workspace(target, monitor)
  end
end

-- Move every assigned window to its slot's workspace under the active
-- arrangement (after hotplug). Windows with no slot, or whose slot no screen
-- of the arrangement holds, stay where they are.
function M.reroute_all(engine)
  if engine.refused or not engine.active then
    return
  end
  for _, window in ipairs(adapter.windows()) do
    local assignment = window.address and engine.assignments[window.address]
    local target = assignment and engine:workspace_for(assignment)
    if target and window.workspace_id ~= target then
      engine.log:info("re-route %s: slot %s, workspace %s -> %d", tostring(window.class), assignment.slot,
        tostring(window.workspace_id), target)
      M.place(engine, window.address, target)
    end
  end
end

local function find_window(address)
  for _, window in ipairs(adapter.windows()) do
    if window.address == address then
      return window
    end
  end
  return nil
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
  if address and engine.assignments[address] then
    local assignment = engine.assignments[address]
    engine.assignments[address] = nil
    engine.log:info("destroy %s: slot %s on desk %d is free", address, assignment.slot, assignment.desk)
    window_rules.sync(engine)
  end
end

return M
