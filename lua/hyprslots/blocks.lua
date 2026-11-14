-- Which workspace ids each screen of the active desk shows (docs/design.md §5).
--
-- Omarchy gives every physical monitor a block of ten workspaces, kept by
-- monitor identity in its state file for good: the monitor seen first owns
-- 1-10 forever, even while it is turned off. hyprslots numbers by desk
-- instead: screen i of the active desk (the i-th monitor from the left)
-- holds block i-1, so screen 1 always shows workspaces 1-10, screen 2
-- 11-20, and a monitor that is off or unplugged holds none.
--
-- It drives Omarchy's monitor-workspaces rather than replacing it: it writes
-- the desk's blocks into Omarchy's own block table (hl_adapter), so Super+N,
-- moving a workspace to another monitor, the bar (which reads the state
-- file) and Omarchy's reconcile all see them, and runs ahead of every
-- Omarchy reconcile, renumbering the workspaces into their screen's block
-- first (plan, below), so Omarchy finds nothing to merge and only puts
-- each screen on a workspace of its own. While hyprslots is off (refused,
-- no desk for the monitors, or Omarchy's internals out of reach) Omarchy
-- numbers as it always did.

local M = {}

local SLOTS = 10

-- Workspaces renumbered out of the way first, so two screens can trade
-- blocks, sit at PARK + their id meanwhile.
M.PARK = 100000

-- connector -> block, for the screens left to right.
function M.of_screens(screens)
  local out = {}
  for i, name in ipairs(screens) do
    out[name] = i - 1
  end
  return out
end

local function by_id(a, b)
  return a.id < b.id
end

-- The steps that put every workspace holding windows into its screen's
-- block under its own number (13 becomes 3 on screen 1). `workspaces` are
-- { id, monitor (connector, or nil), windows } (every workspace, empty ones
-- too, so a number that is taken is known); `screens` the desk's connectors
-- left to right. A workspace on a monitor that is no screen (turned off,
-- unplugged) goes to the screen of its block, or screen 1 when that block
-- has none. Returns a list of
--   { op = "move", id, monitor }   put workspace id on that monitor
--   { op = "rename", id, to }      give workspace id another number
--   { op = "merge", id, into }     move workspace id's windows to another
-- to run in order. Empty and special workspaces are left alone.
function M.plan(workspaces, screens)
  local ops = {}
  if #screens == 0 then
    return ops
  end
  local block_of = M.of_screens(screens)

  local at = {} -- id -> { monitor } for every regular workspace, as the steps leave them
  local busy = {}
  for _, workspace in ipairs(workspaces) do
    if workspace.id > 0 then
      at[workspace.id] = { monitor = workspace.monitor }
      if (workspace.windows or 0) > 0 then
        busy[#busy + 1] = workspace
      end
    end
  end
  table.sort(busy, by_id)

  local stayers, movers, targets = {}, {}, {}
  for _, workspace in ipairs(busy) do
    local monitor = workspace.monitor
    if block_of[monitor] == nil then
      monitor = screens[(workspace.id - 1) // SLOTS + 1] or screens[1]
    end
    local target = block_of[monitor] * SLOTS + (workspace.id - 1) % SLOTS + 1
    if target == workspace.id then
      if monitor ~= workspace.monitor then
        stayers[#stayers + 1] = { id = workspace.id, monitor = monitor }
      end
    else
      movers[#movers + 1] = { id = workspace.id, from = workspace.monitor, monitor = monitor, target = target }
      targets[target] = true
    end
  end

  -- A number another workspace is to take is cleared first.
  for _, mover in ipairs(movers) do
    mover.at = mover.id
    if targets[mover.id] then
      mover.at = M.PARK + mover.id
      ops[#ops + 1] = { op = "rename", id = mover.id, to = mover.at }
      at[mover.at], at[mover.id] = at[mover.id], nil
    end
  end

  for _, stayer in ipairs(stayers) do
    ops[#ops + 1] = { op = "move", id = stayer.id, monitor = stayer.monitor }
    at[stayer.id].monitor = stayer.monitor
  end

  table.sort(movers, function(a, b)
    if a.target ~= b.target then
      return a.target < b.target
    end
    return a.id < b.id
  end)
  for _, mover in ipairs(movers) do
    local occupant = at[mover.target]
    if occupant then
      if occupant.monitor ~= mover.monitor then
        ops[#ops + 1] = { op = "move", id = mover.target, monitor = mover.monitor }
        occupant.monitor = mover.monitor
      end
      ops[#ops + 1] = { op = "merge", id = mover.at, into = mover.target }
    else
      if mover.from ~= mover.monitor then
        ops[#ops + 1] = { op = "move", id = mover.at, monitor = mover.monitor }
      end
      ops[#ops + 1] = { op = "rename", id = mover.at, to = mover.target }
      at[mover.target], at[mover.at] = { monitor = mover.monitor }, nil
    end
  end
  return ops
end

return M
