-- The "slots" layout provider (docs/design.md §6), used as `lua:slots`.
--
-- recalculate(ctx) is arithmetic only: find the workspace's desk and screen
-- role, take that branch of the active arrangement's tree, divide ctx.area by
-- its integer weights, and place each target in its window's slot. It never
-- dispatches. Targets with no slot in the branch stack equally in its
-- overflow leaf (`*`), or in a column appended at 3 : 1 when it has none; an
-- empty overflow leaf closes up. An accordion's group is one target and gets
-- the accordion's box; a layout pass that finds an accordion split over
-- several targets, or a stranger in its group, asks groups.lua for a deferred
-- regroup (it never dispatches itself). Any error is caught, logged, and the
-- targets are tiled in plain columns instead, so a bug never leaves windows
-- unplaced.

local tree = require("hyprslots.tree")

local M = {}

local function columns(n)
  local children = {}
  for i = 1, n do
    children[i] = { slot = i, weight = 1 }
  end
  return { split = "h", weight = 1, children = children }
end

local function place_columns(ctx)
  local boxes = tree.boxes(columns(#ctx.targets), ctx.area)
  for i, target in ipairs(ctx.targets) do
    target:place(boxes[i])
  end
end

local function workspace_of(ctx)
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    local workspace = window and window.workspace
    if workspace then
      return workspace.id
    end
  end
  return nil
end

-- Boxes for `n` rows stacked equally in `area`.
local function rows(area, n)
  local children = {}
  for i = 1, n do
    children[i] = { slot = i, weight = 1 }
  end
  return tree.boxes({ split = "v", weight = 1, children = children }, area)
end

-- The slot a target's window stands for. A group is one target showing its
-- current window; it stands for the first accordion member among its windows,
-- so a group showing a stranger still fills the accordion's box.
local function target_slot(window, slot_in_branch, accordion_of)
  local group = window.group
  if group then
    for _, member in ipairs(group.members or {}) do
      local slot = slot_in_branch(member)
      if slot and accordion_of[slot] then
        return slot
      end
    end
  end
  return slot_in_branch(window)
end

-- Whether a target's window (or group) holds only members of `accordion`.
local function group_is_accordion(window, slot_in_branch, accordion_of, accordion)
  for _, member in ipairs(window.group and window.group.members or {}) do
    local slot = slot_in_branch(member)
    if not slot or accordion_of[slot] ~= accordion then
      return false
    end
  end
  return true
end

local function place_slots(engine, ctx)
  if #ctx.targets == 0 then
    return
  end

  local desk = engine:desk_of_workspace(workspace_of(ctx))
  if not desk then
    place_columns(ctx)
    return
  end

  local in_branch = {}
  for _, slot in ipairs(tree.slots(desk.branch)) do
    in_branch[slot] = true
  end

  local accordion_of = {}
  for i, members in ipairs(tree.accordions(desk.branch)) do
    for _, slot in ipairs(members) do
      accordion_of[slot] = i
    end
  end

  -- A window's slot when it is in this branch, else nil.
  local function slot_in_branch(window)
    local assignment = engine:slot_of(window)
    if assignment and assignment.desk == desk.desk and in_branch[assignment.slot] then
      return assignment.slot
    end
    return nil
  end

  local slotted, overflow, present = {}, {}, {}
  local targets_of_accordion, regroup = {}, false
  for _, target in ipairs(ctx.targets) do
    local slot = target.window and target_slot(target.window, slot_in_branch, accordion_of)
    local accordion = slot and accordion_of[slot]
    if accordion then
      targets_of_accordion[accordion] = (targets_of_accordion[accordion] or 0) + 1
      if targets_of_accordion[accordion] > 1 or not group_is_accordion(target.window, slot_in_branch, accordion_of, accordion) then
        regroup = true
      end
    end
    if slot and not present[slot] then
      slotted[slot] = target
      present[slot] = true
    else
      overflow[#overflow + 1] = target
    end
  end
  if regroup and engine.regroup then
    engine.regroup("layout")
  end

  if next(slotted) == nil then
    place_columns(ctx)
    return
  end

  if #overflow > 0 then
    present[tree.OVERFLOW] = true
  end
  local boxes = tree.boxes(tree.with_overflow(desk.branch), ctx.area, present)
  for slot, target in pairs(slotted) do
    target:place(boxes[slot])
  end
  if #overflow > 0 then
    local stacked = rows(boxes[tree.OVERFLOW], #overflow)
    for i, target in ipairs(overflow) do
      target:place(stacked[i])
    end
  end
end

-- The provider table for hl.layout.register.
function M.provider(engine)
  return {
    recalculate = function(ctx)
      local ok, err = pcall(place_slots, engine, ctx)
      if not ok then
        engine.log:error("recalculate failed, tiling in columns: %s", tostring(err))
        place_columns(ctx)
      end
    end,
  }
end

return M
