-- Windows -> slots.
--
-- Every (workspace, slot) pair a workspace has a spec for is a candidate
-- (cfg.specs: slots are global, a workspace says which app fills which),
-- tried in workspace order then slot-name order; a window takes the first
-- free one whose spec matches it. Windows are
-- considered oldest first (by stable_id), so the result never depends on the
-- order Hyprland lists them in. Assignment is sticky: a previous assignment
-- whose slot still exists and whose spec still admits the window's class is
-- kept, whatever its title says now, before anything new is handed out; one
-- made by hand is kept whatever the window is, while the slot is defined
-- (with or without a spec on that workspace). Pure.

local spec = require("hyprslots.spec")

local M = {}

-- The (workspace, slot) pairs in the order they are tried.
local function candidates(cfg)
  local workspaces = {}
  for workspace in pairs(cfg.specs) do
    workspaces[#workspaces + 1] = workspace
  end
  table.sort(workspaces)

  local out = {}
  for _, workspace in ipairs(workspaces) do
    local names = {}
    for name in pairs(cfg.specs[workspace]) do
      names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
      out[#out + 1] = { workspace = workspace, slot = name, spec = cfg.specs[workspace][name] }
    end
  end
  return out
end

-- The (workspace, slot, spec) candidates in precedence order (for window_rules).
M.candidates = candidates

local function key(workspace, slot)
  return workspace .. "\0" .. slot
end

-- A previous assignment holds while its workspace's spec for the slot still
-- admits the window's class: a title that changed after the window won its
-- slot does not take the slot away (assignment is sticky, as in claim). One
-- made by hand (`manual`, the editor's assign) holds while the slot is
-- defined, spec or none.
local function still_holds(cfg, assignment, window)
  if assignment.manual then
    return cfg.slots[assignment.slot] ~= nil
  end
  local specs = cfg.specs[assignment.workspace]
  local parsed = specs and specs[assignment.slot]
  return parsed and spec.admits(parsed, window) or false
end

local function oldest_first(windows)
  local sorted = {}
  for i, window in ipairs(windows) do
    sorted[i] = window
  end
  table.sort(sorted, function(a, b)
    if a.stable_id ~= b.stable_id then
      return (a.stable_id or 0) < (b.stable_id or 0)
    end
    return a.address < b.address
  end)
  return sorted
end

local function first_free(pairs_, taken, window)
  for _, candidate in ipairs(pairs_) do
    if not taken[key(candidate.workspace, candidate.slot)] and spec.match(candidate.spec, window) then
      return { workspace = candidate.workspace, slot = candidate.slot }
    end
  end
  return nil
end

-- Assign every window ({ address, class, stable_id }). `previous` (address ->
-- { workspace, slot }) is honoured where it still matches; it is not modified.
-- Returns address -> { workspace, slot } for the windows that got a slot.
function M.solve(cfg, windows, previous)
  previous = previous or {}
  local ordered = oldest_first(windows)
  local result, taken = {}, {}

  for _, window in ipairs(ordered) do
    local before = previous[window.address]
    if before and not taken[key(before.workspace, before.slot)] and still_holds(cfg, before, window) then
      result[window.address] = { workspace = before.workspace, slot = before.slot, manual = before.manual }
      taken[key(before.workspace, before.slot)] = true
    end
  end

  local pairs_ = candidates(cfg)
  for _, window in ipairs(ordered) do
    if not result[window.address] then
      local assignment = first_free(pairs_, taken, window)
      if assignment then
        result[window.address] = assignment
        taken[key(assignment.workspace, assignment.slot)] = true
      end
    end
  end

  return result
end

-- The first (workspace, slot), in precedence order, whose spec matches the window,
-- taken or not, or nil: where a window that matches but finds every such
-- slot taken overflows (that workspace's overflow leaf).
function M.first_match(cfg, window)
  for _, candidate in ipairs(candidates(cfg)) do
    if spec.match(candidate.spec, window) then
      return { workspace = candidate.workspace, slot = candidate.slot }
    end
  end
  return nil
end

-- The slot for one window given the current assignments: its own when it has
-- one, else the first free matching slot, else nil. `current` is not modified.
function M.claim(cfg, current, window)
  local own = current[window.address]
  if own then
    return own
  end
  local taken = {}
  for _, assignment in pairs(current) do
    taken[key(assignment.workspace, assignment.slot)] = true
  end
  return first_free(candidates(cfg), taken, window)
end

return M
