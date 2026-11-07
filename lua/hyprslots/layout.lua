-- The "slots" layout provider (docs/design.md §6), used as `lua:slots`.
--
-- recalculate(ctx) is arithmetic only: find the workspace's desk and screen
-- role, take that branch of the active arrangement's tree, divide ctx.area by
-- its integer weights, and place each target in its window's slot. It never
-- dispatches. Targets with no slot share an overflow column (an interim
-- overflow leaf until slice 4). Any error is caught, logged, and the targets
-- are tiled in plain columns instead, so a bug never leaves windows unplaced.

local tree = require("hyprslots.tree")

local M = {}

local OVERFLOW_WEIGHT, TREE_WEIGHT = 1, 3

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

-- The tree to lay out: the branch alone, or the branch beside an overflow
-- column holding `overflow` rows keyed by target index.
local function with_overflow(branch, overflow)
  if #overflow == 0 then
    return branch
  end
  local rows = {}
  for i, target in ipairs(overflow) do
    rows[i] = { slot = target.index, weight = 1 }
  end
  local kept = {}
  for key, value in pairs(branch) do
    kept[key] = value
  end
  kept.weight = TREE_WEIGHT
  return {
    split = "h",
    weight = 1,
    children = { kept, { split = "v", weight = OVERFLOW_WEIGHT, children = rows } },
  }
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

  local slotted, overflow, present = {}, {}, {}
  for _, target in ipairs(ctx.targets) do
    local assignment = target.window and engine:slot_of(target.window)
    if assignment and assignment.desk == desk.desk and in_branch[assignment.slot] and not present[assignment.slot] then
      slotted[assignment.slot] = target
      present[assignment.slot] = true
    else
      overflow[#overflow + 1] = target
    end
  end

  if next(slotted) == nil then
    place_columns(ctx)
    return
  end

  for _, target in ipairs(overflow) do
    present[target.index] = true
  end
  local boxes = tree.boxes(with_overflow(desk.branch, overflow), ctx.area, present)
  for slot, target in pairs(slotted) do
    target:place(boxes[slot])
  end
  for _, target in ipairs(overflow) do
    target:place(boxes[target.index])
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
