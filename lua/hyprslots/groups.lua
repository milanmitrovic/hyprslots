-- Accordions as Hyprland groups (docs/design.md §3, §6).
--
-- An accordion `a[x, y, z]` is realized as ONE Hyprland group holding the
-- windows of its slots; the slots layout then sees the group as a single
-- target and gives it the accordion's box. Group membership is changed only
-- from a deferred timer, never inside recalculate: anything that may have
-- changed membership (a window opening, closing or changing workspace, a
-- layout pass that sees an accordion split over several targets, a new
-- arrangement) calls schedule(), and the reconcile pass then plans and runs
-- the moves for every desk workspace.
--
-- plan() is pure: given the accordions of a workspace's tree and its windows,
-- it returns the moves that leave each accordion with two or more windows in
-- exactly one group of its own:
--
--   { op = "out",    window = address }                 -- leave its group
--   { op = "create", window = address }                 -- a new group of one
--   { op = "add",    window = address, into = address } -- join into's group
--
-- A group holding a member of an accordion is that accordion's (the first such
-- group wins; the rest give their members up); other windows in it are taken
-- out. A lone member is left as it is, and so is a group of windows with no
-- accordion slot.

local adapter = require("hyprslots.hl_adapter")
local tree = require("hyprslots.tree")

local M = {}

-- Reconcile passes in a row, asked for by layout passes alone, that still
-- found moves to make before hyprslots stops asking (Hyprland refusing a
-- move must not become a loop). Any window event starts the count again.
local LAYOUT_RETRIES = 3

-- Deferral for the reconcile pass: after the event that asked for it, and
-- after the 1 ms arrangement re-selection a monitor event schedules.
local DEFER_MS = 20

local function group_key(group)
  return table.concat(group, ",")
end

-- accordions: list of member-slot lists, as tree.accordions returns.
-- windows: list of { address, slot = <slot in this tree, or nil>,
-- group = <member addresses in group order, or nil> }, in a stable order.
function M.plan(accordions, windows)
  local accordion_of_slot, rank = {}, {}
  for i, members in ipairs(accordions) do
    for j, slot in ipairs(members) do
      accordion_of_slot[slot] = i
      rank[slot] = j
    end
  end

  local accordion_of, wanted = {}, {}
  for i = 1, #accordions do
    wanted[i] = {}
  end
  for _, window in ipairs(windows) do
    local i = window.slot and accordion_of_slot[window.slot]
    if i then
      accordion_of[window.address] = i
      table.insert(wanted[i], window)
    end
  end
  for i = 1, #accordions do
    table.sort(wanted[i], function(a, b) return rank[a.slot] < rank[b.slot] end)
  end

  local ops = {}
  local owner_group = {} -- accordion -> group key
  local group_of = {} -- address -> group key, after the outs
  local seen = {}

  for _, window in ipairs(windows) do
    local group = window.group
    local key = group and group_key(group)
    if key and not seen[key] then
      seen[key] = true
      local owner
      for _, address in ipairs(group) do
        local i = accordion_of[address]
        if i and not owner_group[i] then
          owner = i
          break
        end
      end
      if owner then
        owner_group[owner] = key
      end
      for _, address in ipairs(group) do
        local i = accordion_of[address]
        if (owner and i ~= owner) or (not owner and i) then
          ops[#ops + 1] = { op = "out", window = address }
        else
          group_of[address] = key
        end
      end
    end
  end

  for i = 1, #accordions do
    local members = wanted[i]
    if #members >= 2 then
      local anchor
      for _, window in ipairs(members) do
        if owner_group[i] and group_of[window.address] == owner_group[i] then
          anchor = window.address
          break
        end
      end
      if not anchor then
        anchor = members[1].address
        ops[#ops + 1] = { op = "create", window = anchor }
      end
      for _, window in ipairs(members) do
        local address = window.address
        if address ~= anchor and not (owner_group[i] and group_of[address] == owner_group[i]) then
          ops[#ops + 1] = { op = "add", window = address, into = anchor }
        end
      end
    end
  end

  return ops
end

-- The tiled windows on desk workspace `id`, as plan() wants them, oldest first.
local function workspace_windows(engine, id, desk, all)
  local in_branch = {}
  for _, slot in ipairs(tree.slots(desk.branch)) do
    in_branch[slot] = true
  end
  local out = {}
  for _, window in ipairs(all) do
    if window.workspace_id == id and not window.floating then
      local assignment = engine.assignments[window.address]
      local slot = assignment and assignment.desk == desk.desk and in_branch[assignment.slot] and assignment.slot or nil
      out[#out + 1] = {
        address = window.address,
        slot = slot,
        group = window.group,
        stable_id = window.stable_id or 0,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.stable_id ~= b.stable_id then
      return a.stable_id < b.stable_id
    end
    return a.address < b.address
  end)
  return out
end

local RUN = {
  out = function(op) adapter.group_leave(op.window) end,
  create = function(op) adapter.group_create(op.window) end,
  add = function(op) adapter.group_add(op.window, op.into) end,
}

-- Plan and run the group moves for every desk workspace whose tree has an
-- accordion. Returns the number of moves made.
function M.reconcile(engine)
  if engine.refused or not engine.cfg then
    return 0
  end
  local ids = {}
  for id, desk in pairs(engine.workspaces) do
    if #tree.accordions(desk.branch) > 0 then
      ids[#ids + 1] = id
    end
  end
  if #ids == 0 then
    return 0
  end
  table.sort(ids)

  local all = adapter.group_windows()
  local moves = 0
  for _, id in ipairs(ids) do
    local desk = engine.workspaces[id]
    for _, op in ipairs(M.plan(tree.accordions(desk.branch), workspace_windows(engine, id, desk, all))) do
      engine.log:info("accordion on workspace %d: %s %s%s", id, op.op, op.window,
        op.into and (" into " .. op.into) or "")
      engine:guard("accordion " .. op.op, RUN[op.op], op)
      moves = moves + 1
    end
  end
  return moves
end

-- Give the engine `engine.regroup(reason)`, which schedules one deferred
-- reconcile pass (reason "layout" from recalculate, anything else from an
-- event), and ask for a pass on every event that can change membership.
function M.attach(engine)
  local pending, streak, gave_up = false, 0, false

  local function run()
    pending = false
    local moves = 0
    engine:guard("accordion groups", function()
      moves = M.reconcile(engine)
    end)
    streak = moves > 0 and streak + 1 or 0
  end

  function engine.regroup(reason)
    if reason ~= "layout" then
      streak, gave_up = 0, false
    elseif streak >= LAYOUT_RETRIES then
      if not gave_up then
        gave_up = true
        engine.log:error("accordion groups still not formed after %d passes; waiting for a window event", streak)
      end
      return
    end
    if not pending then
      pending = true
      adapter.defer(run, DEFER_MS)
    end
  end

  for _, event in ipairs({
    "window.open", "window.destroy", "window.move_to_workspace",
    "hyprland.start", "config.reloaded", "monitor.added", "monitor.removed",
  }) do
    adapter.on(event, function()
      engine.regroup("event")
    end)
  end
end

return M
