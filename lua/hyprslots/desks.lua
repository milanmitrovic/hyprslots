-- Desk switching on top of Omarchy's per-monitor workspaces (docs/design.md §5).
--
-- Slice 1 switches the focused screen only: desk N there is
-- o.workspaces.focus(N, <focused monitor>). Slice 2 extends this to every
-- connected, non-pinned screen, refocusing the origin afterwards.

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
  local monitor = adapter.active_monitor_name()
  if not monitor then
    return nil, "no focused monitor"
  end
  engine.log:info("desk %d on %s", desk, monitor)
  adapter.focus_desk(desk, monitor)
  return true
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

return M
