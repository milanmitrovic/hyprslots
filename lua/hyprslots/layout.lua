-- The "slots" layout provider (docs/design.md §6), used as `lua:slots`.
--
-- recalculate(ctx) is arithmetic only: find the workspace's desk and screen
-- role, take that branch of the active arrangement's tree, divide ctx.area by
-- its integer weights, and place each target in its window's slot. It never
-- dispatches. Targets with no slot in the branch stack equally in its
-- overflow leaf (`*`), or in a column appended at 3 : 1 when it has none; an
-- empty overflow leaf closes up. Any error is caught, logged, and the targets
-- are tiled in plain columns instead, so a bug never leaves windows unplaced.

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
