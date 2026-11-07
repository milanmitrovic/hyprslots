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

local resize = require("hyprslots.resize")
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

-- What a layout pass on desk entry `desk` sees in ctx.targets: the branch in
-- force, the target placed in each slot, the overflowing targets, the set of
-- slots present (tree.OVERFLOW when something overflows), and whether an
-- accordion is split over several targets or holds a stranger.
local function survey(engine, ctx, desk)
  local branch = resize.branch(engine, desk)
  local in_branch = {}
  for _, slot in ipairs(tree.slots(branch)) do
    in_branch[slot] = true
  end

  local accordions = tree.accordions(branch)
  local accordion_of = {}
  for i, members in ipairs(accordions) do
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
  for _, target in ipairs(ctx.targets or {}) do
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
  if #overflow > 0 then
    present[tree.OVERFLOW] = true
  end
  return {
    branch = branch,
    slotted = slotted,
    overflow = overflow,
    present = present,
    regroup = regroup,
    accordions = accordions,
  }
end

-- The slots a resize on desk entry `desk` sees laid out in ctx: the layout's
-- present set, with every member of a present accordion (a group is one
-- target standing for one member, whichever member is focused).
function M.present(engine, ctx, desk)
  local seen = survey(engine, ctx, desk)
  local out = {}
  for key in pairs(seen.present) do
    out[key] = true
  end
  for _, members in ipairs(seen.accordions) do
    local shown = false
    for _, slot in ipairs(members) do
      shown = shown or seen.present[slot] == true
    end
    if shown then
      for _, slot in ipairs(members) do
        out[slot] = true
      end
    end
  end
  return out
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

  local seen = survey(engine, ctx, desk)
  if seen.regroup and engine.regroup then
    engine.regroup("layout")
  end

  if next(seen.slotted) == nil then
    place_columns(ctx)
    return
  end

  local boxes = tree.boxes(tree.with_overflow(seen.branch), ctx.area, seen.present)
  for slot, target in pairs(seen.slotted) do
    target:place(boxes[slot])
  end
  if #seen.overflow > 0 then
    local stacked = rows(boxes[tree.OVERFLOW], #seen.overflow)
    for i, target in ipairs(seen.overflow) do
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

    -- Keyboard resize (resize.lua). Hyprland sends layout messages to the
    -- focused workspace's algorithm only. Returns true, or the reason the
    -- message did nothing (Hyprland shows a string reply as the error).
    layout_msg = function(ctx, msg)
      local present = function(desk)
        return M.present(engine, ctx, desk)
      end
      local ok, handled, err = pcall(resize.message, engine, ctx, msg, present)
      if not ok then
        engine.log:error("layout message '%s' failed: %s", tostring(msg), tostring(handled))
        return tostring(handled)
      end
      if not handled then
        engine.log:warn("layout message '%s': %s", tostring(msg), tostring(err))
        return err
      end
      return true
    end,
  }
end

return M
