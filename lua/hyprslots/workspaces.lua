-- Workspace switching on top of Omarchy's per-monitor workspaces (docs/design.md §5).
--
-- Workspace N on a screen is o.workspaces.focus(N, <its connector>). A
-- workspace switch shows workspace N on every non-pinned screen of the active
-- desk, the focused screen (the origin) last, then refocuses the origin.
-- With no desk it switches the focused screen alone, as Omarchy's Super+N
-- does.

local adapter = require("hyprslots.hl_adapter")

local M = {}

-- How many workspaces the engine manages (config `workspaces`, default 10).
function M.count(engine)
  return engine and engine.cfg and engine.cfg.workspaces or 10
end

-- Whether `workspace` is one of 1..count (default all ten of Omarchy's).
function M.valid(workspace, count)
  return math.type(workspace) == "integer" and workspace >= 1 and workspace <= (count or 10)
end

-- Activate workspace N. Returns true, or nil and why not.
function M.activate(engine, workspace)
  local count = M.count(engine)
  if not M.valid(workspace, count) then
    return nil, "a workspace must be an integer from 1 to " .. count .. ", got " .. tostring(workspace)
  end
  if engine.refused then
    return nil, "hyprslots is not running: " .. engine.refused
  end
  local origin = adapter.active_monitor_name()
  if not origin then
    return nil, "no focused monitor"
  end

  engine.active_workspace = workspace
  local screens = M.screens(engine, origin)
  engine.log:info("workspace %d on %s", workspace, #screens > 0 and table.concat(screens, ", ") or "no screen")
  for _, monitor in ipairs(screens) do
    adapter.focus_workspace(workspace, monitor)
  end
  adapter.focus_monitor(origin)
  -- Scroll branches back in slot order, even where the workspace was showing.
  if engine.rearrange then
    engine.rearrange("event")
  end
  return true
end

-- The connectors a workspace switch shows the workspace on, in order: every
-- non-pinned screen of the active desk, left to right, the origin last; or
-- just the origin when no desk is active.
function M.screens(engine, origin)
  local active = engine.active
  if not active then
    return { origin }
  end
  local pinned = active.pinned or {}
  local out, origin_switches = {}, false
  for screen, monitor in ipairs(active.monitors) do
    if not pinned[screen] then
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

-- Show the active workspace (the last one switched to) on screens that were
-- just plugged in, unless they are pinned, then refocus the focused screen.
-- `monitors` is a set of connector names. Does nothing before the first
-- workspace switch or with no active desk.
function M.show_active(engine, monitors)
  local workspace, active = engine.active_workspace, engine.active
  if not workspace or not active or engine.refused then
    return
  end
  local pinned = active.pinned or {}
  local shown = {}
  for screen, monitor in ipairs(active.monitors) do
    if monitors[monitor] and not pinned[screen] then
      shown[#shown + 1] = monitor
    end
  end
  if #shown == 0 then
    return
  end
  local origin = adapter.active_monitor_name()
  engine.log:info("workspace %d on returning %s", workspace, table.concat(shown, ", "))
  for _, monitor in ipairs(shown) do
    adapter.focus_workspace(workspace, monitor)
  end
  if origin then
    adapter.focus_monitor(origin)
  end
end

-- The action bound to SUPER + N in place of o.workspaces.focus(N). While
-- hyprslots is not running (refused, e.g. hyprmoncfg's workspace planner was
-- turned back on, or setup failed) the key does what Omarchy's own Super+N
-- does, through whatever o.workspaces.focus is now, so it never goes dead.
function M.action(engine_ref, workspace)
  local action = function()
    local engine = engine_ref()
    if not engine or engine.refused then
      if M.valid(workspace) and adapter.omarchy_workspaces() then
        adapter.focus_workspace(workspace)
      end
      if engine then
        engine.log:warn("workspace %s: hyprslots is not running, Omarchy's switch instead", tostring(workspace))
      end
      return
    end
    local ok, err = M.activate(engine, workspace)
    if not ok then
      engine.log:warn("workspace %s: %s", tostring(workspace), err)
    end
  end
  return adapter.bind_expression(action, "hyprslots.workspace(" .. tostring(workspace) .. ")")
end

-- Rebind SUPER + 1..0 (key codes 10..19, as Omarchy binds them) to workspace
-- switching, as many as the engine manages (config `workspaces`: with 9,
-- Super+0 stays Omarchy's). Not called by setup(): the cutover calls it from
-- the user's config once hyprslots should own those keys.
function M.bind_keys(engine_ref)
  for workspace = 1, M.count(engine_ref()) do
    local keys = "SUPER + code:" .. tostring(workspace + 9)
    adapter.rebind(keys, "Switch to workspace " .. workspace .. " on every screen", M.action(engine_ref, workspace))
  end
end

return M
