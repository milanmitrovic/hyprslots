-- Capture, the engine's half (docs/design.md §9, Capture): capture.lua
-- plans from what it is given; this gathers it from the live windows of a
-- workspace on every screen of the active desk, turns the plan into an edit
-- of the editor's data (edits.lua's pipeline checks it), fingerprints it so
-- an apply runs only the plan previewed, and applies it. The api's capture
-- call checks the arguments and shapes the reply.

local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local edit = require("hyprslots.edit")
local edits = require("hyprslots.edits")
local launcher = require("hyprslots.launcher")
local ratio = require("hyprslots.ratio")
local resize = require("hyprslots.resize")
local serialize = require("hyprslots.serialize")
local util = require("hyprslots.util")

local M = {}

-- What capture.plan reads of workspace n's screens: each screen's tiled
-- windows (a scrolling one's with their columns), whether it scrolls, and
-- its tree in force for the scope's trees.
function M.screens(engine, n, scope)
  local layout = engine.cfg.layouts[engine.active.layout]
  local current = scope == "all" and layout.default or (config.trees_for(layout, n) or {})
  local all = adapter.windows()
  local screens = {}
  for i, monitor in ipairs(engine.active.monitors) do
    local id = adapter.workspace_id(monitor, n)
    local scrolling = adapter.workspace_tiled_layout(id) == "scrolling"
    local columns = {}
    if scrolling then
      for _, w in ipairs(adapter.scroll_windows(id)) do
        columns[w.address] = w
      end
    end
    local windows = {}
    for _, window in ipairs(all) do
      if window.workspace_id == id and not window.floating and window.box and window.address then
        local column = columns[window.address]
        if not scrolling or column then
          if column then
            window.column, window.row, window.column_width = column.column, column.row, column.width
          end
          windows[#windows + 1] = window
        end
      end
    end
    screens[i] = { windows = windows, scroll = scrolling, current = current and current[i] or nil }
  end
  return screens
end

-- What a capture would do, as one short token: FNV-1a (32 bits, hex) over
-- its workspace, scope (none counts as "all", as it previews), layout, each
-- screen's tree and ratio, the slots it makes
-- with their keys and each window's address, slot, spec and newness, in
-- order. Two captures with the same token make the same edit.
function M.fingerprint(n, scope, layout, trees, new_slots, windows)
  local parts = { "workspace=" .. n, "scope=" .. (scope or "all"), "layout=" .. layout }
  for _, screen in ipairs(util.sorted_keys(trees)) do
    local t = trees[screen]
    parts[#parts + 1] = "screen " .. screen .. "=" .. (t and (t.tree .. " " .. t.ratio) or "none")
  end
  for _, s in ipairs(new_slots) do
    parts[#parts + 1] = "slot " .. s.slot .. "=" .. tostring(s.key)
  end
  for _, w in ipairs(windows) do
    parts[#parts + 1] = "window " .. w.address .. "=" .. tostring(w.slot) .. " " .. tostring(w.spec) .. " "
      .. tostring(w.new == true)
  end
  local text = table.concat(parts, "\n")
  local h = 2166136261
  for i = 1, #text do
    h = (h ~ text:byte(i)) * 16777619 & 0xffffffff
  end
  return string.format("%08x", h)
end

-- A capture plan's edit of the data: the new slots (keys picked as the slot
-- list's a picks them), workspace n's specs, the trees of layout `name` for
-- the scope. Returns data and the reply's trees (screen -> { tree, ratio },
-- or false), or nil and why.
function M.edit(engine, plan, name, n, scope)
  local data, err = engine.data, nil
  if #plan.new_slots > 0 then
    local ok, slots_err = edits.editable_slots(engine)
    if not ok then
      return nil, slots_err
    end
  end
  for _, slot in ipairs(plan.new_slots) do
    data, err = edit.add_slot(data, slot)
    if not data then
      return nil, err
    end
  end
  if next(plan.specs) ~= nil then
    local ok, specs_err = edits.editable_specs(engine, n)
    if not ok then
      return nil, specs_err
    end
  end
  local spec_texts = {}
  for _, slot in ipairs(util.sorted_keys(plan.specs)) do
    data, err = edit.set_spec(data, n, slot, plan.specs[slot])
    if not data then
      return nil, err
    end
    spec_texts[#spec_texts + 1] = plan.specs[slot]
  end
  data = launcher.with_desktop_ids(engine, data, spec_texts)
  local texts, trees = {}, {}
  for screen, node in pairs(plan.trees) do
    if node then
      texts[screen] = serialize.tree(node)
      trees[tostring(screen)] = { tree = texts[screen], ratio = ratio.format(node) }
    else
      trees[tostring(screen)] = false
    end
  end
  data, err = edit.replace_trees(data, name, scope == "workspace" and n or "default", texts,
    scope ~= "workspace" and n or nil)
  if not data then
    return nil, err
  end
  return data, trees
end

-- load_checked's check of a capture: the config took every new slot and
-- each of workspace n's specs from the data.
function M.check(plan, n)
  return function(cfg)
    for _, slot in ipairs(plan.new_slots) do
      if not cfg.slots[slot] then
        return edits.not_taken("the slots")
      end
    end
    for slot, text in pairs(plan.specs) do
      if edits.workspace_spec(cfg, n, slot) ~= text then
        return edits.not_taken("workspace " .. n .. "'s specs")
      end
    end
    return nil
  end
end

-- Run a capture's edit: each window into its slot first, so the re-solve
-- under the new specs keeps it there; the trees replaced lose their
-- keyboard-resized copies.
function M.apply(engine, plan, cfg, data, name, n, scope)
  for address, slot in pairs(plan.assign) do
    engine.assignments[address] = { workspace = n, slot = slot }
    engine.overflow[address] = nil
    engine.unassigned[address] = nil
  end
  for screen = 1, cfg.layouts[name].screens do
    resize.clear(engine, name, scope == "workspace" and n or "default", screen)
    if scope ~= "workspace" then
      resize.clear(engine, name, n, screen)
    end
  end
  engine:apply_config(cfg, data, true)
end

return M
