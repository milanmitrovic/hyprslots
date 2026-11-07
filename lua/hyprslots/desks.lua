-- Desk switching on top of Omarchy's per-monitor workspaces (docs/design.md §5).
--
-- Desk N on a screen is o.workspaces.focus(N, <its connector>). A desk switch
-- shows desk N on every non-pinned screen of the active arrangement, the
-- focused screen (the origin) last, then refocuses the origin. With no
-- arrangement it switches the focused screen alone, as Omarchy's Super+N does.

local adapter = require("hyprslots.hl_adapter")

local M = {}

function M.valid(desk)
  return math.type(desk) == "integer" and desk >= 1 and desk <= 10
end

-- Activate desk N. Returns true, or nil and why not.
function M.activate(engine, desk)
  if not M.valid(desk) then
    return nil, "a desk must be an integer from 1 to 10, got " .. tostring(desk)
  end
  if engine.refused then
    return nil, "hyprslots is not running: " .. engine.refused
  end
  local origin = adapter.active_monitor_name()
  if not origin then
    return nil, "no focused monitor"
  end

  engine.active_desk = desk
  local screens = M.screens(engine, origin)
  engine.log:info("desk %d on %s", desk, #screens > 0 and table.concat(screens, ", ") or "no screen")
  for _, monitor in ipairs(screens) do
    adapter.focus_desk(desk, monitor)
  end
  adapter.focus_monitor(origin)
  return true
end

-- The connectors a desk switch shows the desk on, in order: every non-pinned
-- screen of the active arrangement by role name, the origin last; or just
-- the origin when no arrangement is active.
function M.screens(engine, origin)
  local active = engine.active
  if not active then
    return { origin }
  end
  local pinned = engine.cfg and engine.cfg.pinned or {}
  local out, origin_switches = {}, false
  for _, role in ipairs(active.arrangement.roles) do
    local monitor = active.monitors[role]
    if not pinned[role] then
      if monitor == origin then
        origin_switches = true
      else
        out[#out + 1] = monitor
      end
    end
  end
  if origin_switches then
    out[#out + 1] = origin
  end
  return out
end

-- Show the active desk (the last one switched to) on screens that were just
-- plugged in, unless they are pinned, then refocus the focused screen.
-- `monitors` is a set of connector names. Does nothing before the first desk
-- switch or with no active arrangement.
function M.show_active(engine, monitors)
  local desk, active = engine.active_desk, engine.active
  if not desk or not active or engine.refused then
    return
  end
  local pinned = engine.cfg and engine.cfg.pinned or {}
  local shown = {}
  for _, role in ipairs(active.arrangement.roles) do
    local monitor = active.monitors[role]
    if monitors[monitor] and not pinned[role] then
      shown[#shown + 1] = monitor
    end
  end
  if #shown == 0 then
    return
  end
  local origin = adapter.active_monitor_name()
  engine.log:info("desk %d on returning %s", desk, table.concat(shown, ", "))
  for _, monitor in ipairs(shown) do
    adapter.focus_desk(desk, monitor)
  end
  if origin then
    adapter.focus_monitor(origin)
  end
end

-- The action bound to SUPER + N in place of o.workspaces.focus(N).
function M.action(engine_ref, desk)
  local action = function()
    local engine = engine_ref()
    if not engine then
      return
    end
    local ok, err = M.activate(engine, desk)
    if not ok then
      engine.log:warn("desk %s: %s", tostring(desk), err)
    end
  end
  return adapter.bind_expression(action, "hyprslots.desk(" .. tostring(desk) .. ")")
end

-- Rebind SUPER + 1..0 (key codes 10..19, as Omarchy binds them) to desk
-- switching. Not called by setup(): the cutover calls it from the user's
-- config once hyprslots should own those keys.
function M.bind_keys(engine_ref)
  for desk = 1, 10 do
    local keys = "SUPER + code:" .. tostring(desk + 9)
    adapter.rebind(keys, "Switch to desk " .. desk .. " on every screen", M.action(engine_ref, desk))
  end
end

return M
