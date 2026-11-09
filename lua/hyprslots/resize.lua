-- Keyboard resize through the slots provider's layout_msg (docs/design.md §6).
--
--   hl.dispatch(hl.dsp.layout("nudge r 0.1"))   -- focused slot 10% wider, rightwards
--   hl.dispatch(hl.dsp.layout("nudge l 100px")) -- 100 px wider, leftwards
--   hl.dispatch(hl.dsp.layout("resize -100 0")) -- 100 px narrower (Omarchy's binds)
--   hl.dispatch(hl.dsp.layout("reset"))         -- back to the configured tree
--
-- Hyprland hands a layout message to the focused workspace's algorithm only,
-- so this always acts on the focused window's slot. A nudged tree replaces
-- the configured branch for that layout, workspace and screen, in memory
-- only (engine.resized["<layout>/<workspace>/<screen>"]): it survives monitor
-- hotplug (back to a desk using the same layout) but not a config reload. The
-- editor api's save writes it to slots.lua and clears it; its reload drops
-- it. effective_branch is the one answer to "which tree is in force", for
-- the layout and the api alike.

local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local edit = require("hyprslots.edit")
local tree = require("hyprslots.tree")

local M = {}

-- The override key of a layout's workspace on a screen.
function M.key(layout, workspace, screen)
  return string.format("%s/%s/%s", tostring(layout), tostring(workspace), tostring(screen))
end

local function key(engine, entry)
  return M.key(engine.active and engine.active.layout or "?", entry.workspace, entry.screen)
end

local function overrides(engine)
  engine.resized = engine.resized or {}
  return engine.resized
end

-- The tree in force for a layout's workspace on a screen: the nudged one
-- if there is one, else the config's (its own or the default; nil when the
-- config has none).
function M.effective_branch(engine, layout, workspace, screen)
  local nudged = overrides(engine)[M.key(layout, workspace, screen)]
  if nudged then
    return nudged
  end
  local entry = engine.cfg and engine.cfg.layouts[layout]
  local trees = config.trees_for(entry, workspace)
  return trees and trees[screen]
end

-- The tree recalculate lays out for a workspace entry ({ workspace, screen,
-- branch }) of the active desk: effective_branch, else the entry's own
-- branch.
function M.branch(engine, entry)
  local name = engine.active and engine.active.layout
  return (name and M.effective_branch(engine, name, entry.workspace, entry.screen)) or entry.branch
end

-- Each override as { key, layout, workspace, screen, tree }, sorted by key.
function M.overrides(engine)
  local out = {}
  for k, node in pairs(overrides(engine)) do
    local layout, workspace, screen = k:match("^(.*)/(%d+)/(%d+)$")
    out[#out + 1] = {
      key = k, layout = layout, workspace = math.tointeger(tonumber(workspace)),
      screen = math.tointeger(tonumber(screen)), tree = node,
    }
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

-- Every tree holds every slot, a keyboard-resized one too: after the config
-- changed (a slot added or removed, say), each override loses the slots its
-- configured branch no longer has and gets the ones it now has at its end
-- (tree.append), its nudges kept. An override whose branch is gone goes.
function M.conform(engine)
  local layouts = engine.cfg and engine.cfg.layouts or {}
  for _, o in ipairs(M.overrides(engine)) do
    local trees = config.trees_for(layouts[o.layout], o.workspace)
    local configured = trees and trees[o.screen]
    local node = configured and o.tree or nil
    if node then
      local want, have = {}, {}
      for _, slot in ipairs(tree.slots(configured)) do
        want[slot] = true
      end
      for _, slot in ipairs(tree.slots(o.tree)) do
        have[slot] = true
        if not want[slot] then
          node = node and edit.remove_leaf(node, slot)
        end
      end
      local missing = {}
      for _, slot in ipairs(tree.slots(configured)) do
        if not have[slot] then
          missing[#missing + 1] = slot
        end
      end
      if node and #missing > 0 then
        node = tree.append(node, missing)
      end
    end
    overrides(engine)[o.key] = node
  end
end

-- Drop one override, or every override (no arguments past engine).
function M.clear(engine, layout, workspace, screen)
  if layout == nil then
    engine.resized = {}
  else
    overrides(engine)[M.key(layout, workspace, screen)] = nil
  end
end

local function announce(engine)
  if engine.changed then
    engine:changed()
  end
end

-- The focused window's { workspace entry, slot }, or nil and why not.
local function focused(engine)
  local window = adapter.active_window()
  if not window or not window.address then
    return nil, "no focused window"
  end
  local entry = engine:entry_of_workspace(window.workspace_id)
  if not entry then
    return nil, "the focused window is not on a hyprslots workspace"
  end
  local assignment = engine.assignments[window.address] or engine:assign(window)
  if not assignment or assignment.workspace ~= entry.workspace then
    return nil, "the focused window has no slot on this workspace"
  end
  return entry, assignment.slot
end

-- "0.1" -> 0.1 (a fraction of the split), "100px" -> 100, true (pixels).
local function amount(text)
  local px = text and text:match("^([-+]?%d+)px$")
  if px then
    return tonumber(px), true
  end
  return tonumber(text), false
end

-- `present(entry)`, when given, is the set of slots the layout shows on that
-- workspace entry (layout.present), so the nudge acts on the tree as laid out.
-- `quiet` leaves the change event to the caller (resize, which may nudge on
-- both axes and announces once).
local function nudge(engine, ctx, dir, text, present, quiet)
  local delta, pixels = amount(text)
  if not delta then
    return nil, "a nudge must be a fraction (0.1) or pixels (100px), got '" .. tostring(text) .. "'"
  end
  local entry, slot = focused(engine)
  if not entry then
    return nil, slot
  end
  local nudged, err = tree.nudge(M.branch(engine, entry), slot, dir, delta,
    { area = pixels and ctx.area or nil, present = present and present(entry) or nil })
  if not nudged then
    return nil, err
  end
  overrides(engine)[key(engine, entry)] = nudged
  engine.log:info("nudge %s %s %s on workspace %s", slot, dir, text, tostring(entry.workspace))
  if not quiet then
    announce(engine)
  end
  return true
end

local function reset(engine)
  local entry, err = focused(engine)
  if not entry then
    return nil, err
  end
  local had = overrides(engine)[key(engine, entry)] ~= nil
  overrides(engine)[key(engine, entry)] = nil
  engine.log:info("reset workspace %s screen %s", tostring(entry.workspace), tostring(entry.screen))
  if had then
    announce(engine)
  end
  return true
end

-- "resize <dx> <dy>" in pixels, as Omarchy's hl.dsp.window.resize binds say
-- it, with dwindle's feel: an edge of the focused slot moves by dx (its right
-- edge, or its left edge when nothing is to its right) and by dy (its bottom
-- edge, or its top edge). So dx = -100 ("Expand window left") narrows a slot
-- with a neighbour on its right and widens the rightmost slot. A resize on
-- both axes is one change for the editor: one event, not one per axis.
local function resize(engine, ctx, dx, dy, present)
  dx, dy = math.tointeger(tonumber(dx)), math.tointeger(tonumber(dy))
  if not dx or not dy then
    return nil, "resize takes whole pixels: resize <dx> <dy>"
  end
  local changed, err = false, nil
  for _, step in ipairs({ { dx, "r", "l" }, { dy, "d", "u" } }) do
    local delta, forward, backward = step[1], step[2], step[3]
    if delta ~= 0 then
      local ok
      ok, err = nudge(engine, ctx, forward, delta .. "px", present, true)
      if not ok then
        ok, err = nudge(engine, ctx, backward, -delta .. "px", present, true)
      end
      changed = changed or ok == true
    end
  end
  if changed then
    announce(engine) -- once, however many axes moved
    return true
  end
  return nil, err or "nothing to resize"
end

-- Handle one layout message. Returns true, or nil and why not. `present`
-- (optional) maps a workspace entry to the slots laid out on it (layout.present).
function M.message(engine, ctx, msg, present)
  local words = {}
  for word in tostring(msg):gmatch("%S+") do
    words[#words + 1] = word
  end
  local verb = words[1]
  if verb == "nudge" and #words == 3 then
    return nudge(engine, ctx, words[2], words[3], present)
  elseif verb == "reset" and #words == 1 then
    return reset(engine)
  elseif verb == "resize" and #words == 3 then
    return resize(engine, ctx, words[2], words[3], present)
  end
  return nil, "unknown layout message '" .. tostring(msg) .. "' (nudge <l|r|u|d> <fraction|Npx>, resize <dx> <dy>, reset)"
end

-- Omarchy's keyboard resize binds (default/hypr/bindings/tiling.lua):
-- keys, description, dx, dy. Kept in step with Omarchy by hand.
M.OMARCHY_KEYS = {
  { "SUPER + code:20", "Expand window left", -100, 0 },
  { "SUPER + code:21", "Shrink window left", 100, 0 },
  { "SUPER + SHIFT + code:20", "Shrink window up", 0, -100 },
  { "SUPER + SHIFT + code:21", "Expand window down", 0, 100 },
  { "SUPER + ALT + code:20", "Expand window left a little", -25, 0 },
  { "SUPER + ALT + code:21", "Shrink window left a little", 25, 0 },
  { "SUPER + SHIFT + ALT + code:20", "Shrink window up a little", 0, -25 },
  { "SUPER + SHIFT + ALT + code:21", "Expand window down a little", 0, 25 },
  { "SUPER + CTRL + code:20", "Expand window left a lot", -300, 0 },
  { "SUPER + CTRL + code:21", "Shrink window left a lot", 300, 0 },
  { "SUPER + CTRL + SHIFT + code:20", "Shrink window up a lot", 0, -300 },
  { "SUPER + CTRL + SHIFT + code:21", "Expand window down a lot", 0, 300 },
}

local SLOTS_LAYOUT = "lua:slots"

-- The action for one resize key: a "resize dx dy" layout message on a
-- lua:slots workspace (whatever its number), Omarchy's own relative window
-- resize everywhere else.
function M.key_action(dx, dy)
  local action = function()
    if adapter.active_layout() == SLOTS_LAYOUT then
      adapter.layout_msg(string.format("resize %d %d", dx, dy))
    else
      adapter.resize_window(dx, dy)
    end
  end
  return adapter.bind_expression(action, string.format("hyprslots.resize_key(%d, %d)", dx, dy))
end

-- Rebind Omarchy's resize keys to key_action. For the cutover's bindings,
-- after Omarchy's own; setup() does not call it.
function M.bind_keys()
  for _, key in ipairs(M.OMARCHY_KEYS) do
    adapter.rebind(key[1], key[2], M.key_action(key[3], key[4]))
  end
end

return M
