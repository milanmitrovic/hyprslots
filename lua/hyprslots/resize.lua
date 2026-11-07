-- Keyboard resize through the slots provider's layout_msg (docs/design.md §6).
--
--   hl.dispatch(hl.dsp.layout("nudge r 0.1"))   -- focused slot 10% wider, rightwards
--   hl.dispatch(hl.dsp.layout("nudge l 100px")) -- 100 px wider, leftwards
--   hl.dispatch(hl.dsp.layout("resize -100 0")) -- 100 px narrower (Omarchy's binds)
--   hl.dispatch(hl.dsp.layout("reset"))         -- back to the configured tree
--
-- Hyprland hands a layout message to the focused workspace's algorithm only,
-- so this always acts on the focused window's slot. A nudged tree replaces
-- the configured branch for that arrangement, desk and screen role, in memory
-- only: it survives monitor hotplug (re-selecting the same arrangement) but
-- not a config reload. Persisting it is slice 6 (record + serializer).

local adapter = require("hyprslots.hl_adapter")
local tree = require("hyprslots.tree")

local M = {}

local function key(engine, desk)
  return string.format("%s/%s/%s", engine.active and engine.active.name or "?", desk.desk, desk.role)
end

local function overrides(engine)
  engine.resized = engine.resized or {}
  return engine.resized
end

-- The tree recalculate lays out for a desk entry ({ desk, role, branch }):
-- the nudged one if there is one, else the configured branch.
function M.branch(engine, desk)
  return overrides(engine)[key(engine, desk)] or desk.branch
end

-- The focused window's { desk entry, slot }, or nil and why not.
local function focused(engine)
  local window = adapter.active_window()
  if not window or not window.address then
    return nil, "no focused window"
  end
  local desk = engine:desk_of_workspace(window.workspace_id)
  if not desk then
    return nil, "the focused window is not on a desk workspace"
  end
  local assignment = engine.assignments[window.address] or engine:assign(window)
  if not assignment or assignment.desk ~= desk.desk then
    return nil, "the focused window has no slot on this desk"
  end
  return desk, assignment.slot
end

-- "0.1" -> 0.1 (a fraction of the split), "100px" -> 100, true (pixels).
local function amount(text)
  local px = text and text:match("^([-+]?%d+)px$")
  if px then
    return tonumber(px), true
  end
  return tonumber(text), false
end

local function nudge(engine, ctx, dir, text)
  local delta, pixels = amount(text)
  if not delta then
    return nil, "a nudge must be a fraction (0.1) or pixels (100px), got '" .. tostring(text) .. "'"
  end
  local desk, slot = focused(engine)
  if not desk then
    return nil, slot
  end
  local nudged, err = tree.nudge(M.branch(engine, desk), slot, dir, delta, pixels and { area = ctx.area } or nil)
  if not nudged then
    return nil, err
  end
  overrides(engine)[key(engine, desk)] = nudged
  engine.log:info("nudge %s %s %s on desk %s", slot, dir, text, tostring(desk.desk))
  return true
end

local function reset(engine)
  local desk, err = focused(engine)
  if not desk then
    return nil, err
  end
  overrides(engine)[key(engine, desk)] = nil
  engine.log:info("reset desk %s %s", tostring(desk.desk), desk.role)
  return true
end

-- "resize <dx> <dy>" in pixels, as Omarchy's hl.dsp.window.resize binds say
-- it, with dwindle's feel: an edge of the focused slot moves by dx (its right
-- edge, or its left edge when nothing is to its right) and by dy (its bottom
-- edge, or its top edge). So dx = -100 ("Expand window left") narrows a slot
-- with a neighbour on its right and widens the rightmost slot.
local function resize(engine, ctx, dx, dy)
  dx, dy = math.tointeger(tonumber(dx)), math.tointeger(tonumber(dy))
  if not dx or not dy then
    return nil, "resize takes whole pixels: resize <dx> <dy>"
  end
  local changed, err = false, nil
  for _, step in ipairs({ { dx, "r", "l" }, { dy, "d", "u" } }) do
    local delta, forward, backward = step[1], step[2], step[3]
    if delta ~= 0 then
      local ok
      ok, err = nudge(engine, ctx, forward, delta .. "px")
      if not ok then
        ok, err = nudge(engine, ctx, backward, -delta .. "px")
      end
      changed = changed or ok == true
    end
  end
  if changed then
    return true
  end
  return nil, err or "nothing to resize"
end

-- Handle one layout message. Returns true, or nil and why not.
function M.message(engine, ctx, msg)
  local words = {}
  for word in tostring(msg):gmatch("%S+") do
    words[#words + 1] = word
  end
  local verb = words[1]
  if verb == "nudge" and #words == 3 then
    return nudge(engine, ctx, words[2], words[3])
  elseif verb == "reset" and #words == 1 then
    return reset(engine)
  elseif verb == "resize" and #words == 3 then
    return resize(engine, ctx, words[2], words[3])
  end
  return nil, "unknown layout message '" .. tostring(msg) .. "' (nudge <l|r|u|d> <fraction|Npx>, resize <dx> <dy>, reset)"
end

return M
