-- scroll[...] branches on Hyprland's own scrolling layout (docs/design.md §6).
--
-- A screen whose tree is `scroll[a, b, c]` gets its workspace on
-- Hyprland's `scrolling` layout instead of lua:slots: the user's full-width
-- scrolling, with hyprslots keeping the columns in slot order (windows with
-- no slot in the branch where it places the overflow leaf, `scroll[a, *, b]`,
-- else after them, in the order they are in) and making the
-- columns that arrive as wide as the tree says (full width, or
-- `scroll:0.5[...]` half the screen). All of it runs in a deferred pass (20 ms
-- timer), never inside an event:
--
--   order  after a window opens or moves to a workspace, the workspace is
--          shown (a workspace switch included), a desk change, a re-route
--          or an edit: Hyprland's window.swap between pairs of windows, which
--          keeps the focus; the cursor is kept from warping to the swapped
--          window (cursor:no_warps for the duration).
--   widen  on the focused workspace only (Hyprland's colresize acts on the
--          focused workspace): when a column it has not widened before is
--          there, or the tree asks for another width, `colresize all
--          <width>` (the tree's: scroll:0.5[...] half the screen, scroll[...]
--          full width), then `fit_into_view` so the
--          focused column stays in view. A focus change runs this alone, so
--          a column the user moved or resized is never put back on one.
--
-- A workspace is managed only while its tiled layout is `scrolling` and
-- Omarchy has no saved mode for it: Super+L to any mode (side-by-side or
-- full-width scrolling included) saves one, and hyprslots leaves the
-- workspace alone until Super+L brings slots back, which removes it.
--
-- plan() and order() are pure; the rest goes through hl_adapter.

local adapter = require("hyprslots.hl_adapter")
local tree = require("hyprslots.tree")

local M = {}

-- A column narrower or wider than this (a fraction of the screen) counts as
-- not full width.
local WIDTH_TOLERANCE = 0.005

-- Deferral for the pass, after the event that asked for it.
local DEFER_MS = 20

-- Full width (scroll[...] with no width of its own): Omarchy's full-width
-- stop, a hair under the screen.
M.FULL_WIDTH = 0.99

-- Windows ({ address, column, row }) in column order: left to right, then
-- down a column.
function M.order(windows)
  local out = {}
  for i, window in ipairs(windows) do
    out[i] = window
  end
  table.sort(out, function(a, b)
    if a.column ~= b.column then
      return a.column < b.column
    end
    if (a.row or 0) ~= (b.row or 0) then
      return (a.row or 0) < (b.row or 0)
    end
    return a.address < b.address
  end)
  return out
end

-- The swaps ({ a, b } addresses) that put `windows` ({ address, slot = the
-- slot of `slots` it holds, or nil }, in column order) in slot order. The
-- windows with no slot keep the order they are in and go where `slots`
-- has tree.OVERFLOW (a scroll branch's columns, tree.columns), else after
-- the slotted ones.
function M.plan(slots, windows)
  local rank = {}
  for i, slot in ipairs(slots) do
    rank[slot] = i
  end
  local rest_rank = rank[tree.OVERFLOW] or (#slots + 1)
  local keyed = {}
  for i, window in ipairs(windows) do
    local slotted = window.slot and window.slot ~= tree.OVERFLOW and rank[window.slot]
    keyed[i] = { window = window, rank = slotted or rest_rank, index = i }
  end
  table.sort(keyed, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.index < b.index
  end)
  local wanted = {}
  for i, entry in ipairs(keyed) do
    wanted[i] = entry.window
  end

  local current = {}
  for i, window in ipairs(windows) do
    current[i] = window.address
  end
  local swaps = {}
  for i, window in ipairs(wanted) do
    if current[i] ~= window.address then
      for j = i + 1, #current do
        if current[j] == window.address then
          swaps[#swaps + 1] = { a = current[i], b = current[j] }
          current[i], current[j] = current[j], current[i]
          break
        end
      end
    end
  end
  return swaps
end

-- The column width a scroll branch gives its columns (a fraction of the
-- screen): its own (`scroll:0.5[...]`, tree.lua), else full width.
function M.width(branch)
  return branch and branch.width or M.FULL_WIDTH
end

-- The layout workspace `id` should have under the active desk:
-- "scrolling" for a scroll branch, else "lua:slots".
function M.layout_for(engine, id)
  local entry = engine.workspaces[id]
  if entry and tree.scroll(entry.branch) then
    return "scrolling"
  end
  return "lua:slots"
end

-- Whether hyprslots keeps workspace `id`'s columns: a scroll branch of the
-- active desk, on the scrolling layout, with no saved Omarchy mode.
function M.managed(engine, id)
  local entry = engine:entry_of_workspace(id)
  if not entry or not tree.scroll(entry.branch) then
    return false
  end
  if adapter.workspace_tiled_layout(id) ~= "scrolling" then
    return false
  end
  return not adapter.omarchy_mode_saved(id)
end

-- The windows a pass orders on workspace `id`, in column order, with the slot
-- each holds in the branch (nil for none), and the branch's columns
-- (tree.columns: its slots, tree.OVERFLOW where windows with no slot go).
-- Windows Hyprland reports no column for (a group, say) are left out.
local function columns(engine, id, entry)
  local slots = tree.columns(entry.branch)
  local in_branch = {}
  for _, slot in ipairs(slots) do
    if slot ~= tree.OVERFLOW then
      in_branch[slot] = true
    end
  end
  local out = {}
  for _, window in ipairs(adapter.scroll_windows(id)) do
    local assignment = engine.assignments[window.address]
    if assignment and assignment.workspace == entry.workspace and in_branch[assignment.slot] then
      window.slot = assignment.slot
    end
    out[#out + 1] = window
  end
  return M.order(out), slots
end

-- One pass over every managed scroll workspace. opts.order = false widens
-- only (a focus change); opts.widen_all widens every column of the focused
-- one, ones widened before included (the api's arrange: Super+L bringing
-- slots back, after which every column is a new one). Returns
-- { swaps = n, widened = { ids } }.
function M.arrange(engine, opts)
  local result = { swaps = 0, widened = {} }
  if engine.refused or not engine.cfg then
    return result
  end
  local reorder = not (opts and opts.order == false)
  if opts and opts.widen_all then
    engine.scroll_seen = {}
  end
  engine.scroll_seen = engine.scroll_seen or {}
  local active = adapter.active_window()
  engine.scroll_widths = engine.scroll_widths or {}

  local ids, scrolls = {}, {}
  for id, entry in pairs(engine.workspaces) do
    if tree.scroll(entry.branch) then
      ids[#ids + 1] = id
      scrolls[id] = true
    end
  end
  table.sort(ids)
  -- A workspace that is no scroll branch now forgets its columns: windows
  -- that come back to it come back in new, narrow columns.
  for id in pairs(engine.scroll_seen) do
    if not scrolls[id] then
      engine.scroll_seen[id] = nil
    end
  end
  for id in pairs(engine.scroll_widths) do
    if not scrolls[id] then
      engine.scroll_widths[id] = nil
    end
  end

  for _, id in ipairs(ids) do
    if not M.managed(engine, id) then
      engine.scroll_seen[id] = nil
    else
      local entry = engine.workspaces[id]
      local windows, slots = columns(engine, id, entry)
      local changed = false
      -- A tree that asks for another width makes every column a new one.
      local width = M.width(entry.branch)
      if engine.scroll_widths[id] ~= width then
        engine.scroll_seen[id] = nil
        engine.scroll_widths[id] = width
      end

      if reorder then
        local swaps = M.plan(slots, windows)
        if #swaps > 0 then
          for _, swap in ipairs(swaps) do
            engine.log:info("scroll on workspace %d: swap %s and %s", id, swap.a, swap.b)
          end
          engine:guard("scroll order", adapter.swap_windows, swaps)
          result.swaps = result.swaps + #swaps
          changed = true
        end
      end

      local focused = active and not active.floating and active.workspace_id == id
      local seen = engine.scroll_seen[id] or {}
      local now = {}
      local fresh_narrow = false
      for _, window in ipairs(windows) do
        now[window.address] = seen[window.address]
        if not seen[window.address] and math.abs((window.width or width) - width) > WIDTH_TOLERANCE then
          fresh_narrow = true
        end
      end
      if focused then
        if fresh_narrow then
          engine.log:info("scroll on workspace %d: columns to %s", id, tostring(width))
          engine:guard("scroll width", adapter.layout_msg, "colresize all " .. tostring(width))
          result.widened[#result.widened + 1] = id
          changed = true
        end
        for _, window in ipairs(windows) do
          now[window.address] = true
        end
        if changed then
          engine:guard("scroll view", adapter.layout_msg, "fit_into_view")
        end
      end
      engine.scroll_seen[id] = now
    end
  end
  return result
end

-- Give the engine `engine.rearrange(reason)`, which schedules one deferred
-- pass ("focus": widen only; anything else also orders), and ask for one on
-- the events that bring windows to a workspace or show one. Window close is
-- not among them: closing a column keeps the others in their order.
function M.attach(engine)
  local pending, order = false, false

  local function run()
    pending = false
    local opts = { order = order }
    order = false
    engine:guard("scroll pass", M.arrange, engine, opts)
  end

  function engine.rearrange(reason)
    if reason ~= "focus" then
      order = true
    end
    if not pending then
      pending = true
      adapter.defer(run, DEFER_MS)
    end
  end

  for _, event in ipairs({
    "window.open", "window.move_to_workspace", "workspace.active", "hyprland.start", "config.reloaded",
  }) do
    adapter.on(event, function()
      engine.rearrange("event")
    end)
  end
  adapter.on("window.active", function()
    engine.rearrange("focus")
  end)
end

-- Every scroll branch on a workspace of the active desk, for the
-- api's state: { workspace_id, workspace, screen, slots, width (its columns'),
-- layout = its tiled layout,
-- managed, columns = addresses in column order, members = slot -> address,
-- in_order = whether the columns are in slot order }.
function M.describe(engine)
  local out = {}
  if engine.refused or not engine.cfg then
    return out
  end
  local ids = {}
  for id, entry in pairs(engine.workspaces) do
    if tree.scroll(entry.branch) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = engine.workspaces[id]
    local windows, order_of = columns(engine, id, entry)
    local order, members = {}, {}
    for i, window in ipairs(windows) do
      order[i] = window.address
      if window.slot then
        members[window.slot] = window.address
      end
    end
    out[#out + 1] = {
      workspace_id = id, workspace = entry.workspace, screen = entry.screen, slots = tree.scroll(entry.branch),
      width = M.width(entry.branch),
      layout = adapter.workspace_tiled_layout(id), managed = M.managed(engine, id),
      columns = order, members = members, in_order = #M.plan(order_of, windows) == 0,
    }
  end
  return out
end

return M
