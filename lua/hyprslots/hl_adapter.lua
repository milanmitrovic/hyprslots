-- The only module that touches Hyprland's `hl` and Omarchy's `o`.
--
-- Both globals are read at call time, never captured, so the engine always
-- talks to the current ones (and busted can swap in a stub per test). Hyprland
-- objects (HL.Monitor, HL.Window) are copied into plain tables at this
-- boundary; the pure modules never see them.

local M = {}

-- Hyprland notification icons (HL.NotificationOptions.icon).
local ICON = { warning = 0, info = 1, hint = 2, error = 3, confused = 4, ok = 5 }

local function hl()
  return _G.hl
end

-- Connected monitors that show workspaces of their own (mirrors excluded):
-- { name, description, serial, id, focused }.
function M.monitors()
  local out = {}
  for _, monitor in ipairs(hl().get_monitors() or {}) do
    if not monitor.is_mirror then
      out[#out + 1] = {
        name = monitor.name,
        description = monitor.description or "",
        serial = monitor.serial or "",
        id = monitor.id,
        focused = monitor.focused,
      }
    end
  end
  return out
end

-- A plain copy of an HL.Window: { address, class, title, stable_id, workspace_id }.
function M.window(window)
  local workspace = window.workspace
  return {
    address = window.address,
    class = window.class,
    title = window.title,
    stable_id = window.stable_id,
    workspace_id = workspace and workspace.id,
  }
end

function M.windows()
  local out = {}
  for _, window in ipairs(hl().get_windows() or {}) do
    out[#out + 1] = M.window(window)
  end
  return out
end

function M.active_monitor_name()
  local monitor = hl().get_active_monitor()
  return monitor and monitor.name
end

function M.on(event, callback)
  return hl().on(event, callback)
end

-- Run `callback` once, after the current event has returned.
function M.defer(callback, timeout_ms)
  return hl().timer(callback, { type = "oneshot", timeout = timeout_ms or 1 })
end

function M.notify(text, kind)
  return hl().notification.create({ text = text, timeout = 10000, icon = ICON[kind or "error"] })
end

function M.register_layout(name, provider)
  hl().layout.register(name, provider)
end

function M.workspace_layout(workspace_id, layout)
  return hl().workspace_rule({ workspace = tostring(workspace_id), layout = layout })
end

-- Move a window to a workspace without following it.
function M.move_window(address, workspace_id)
  return hl().dispatch(hl().dsp.window.move({
    workspace = tostring(workspace_id),
    window = "address:" .. address,
    follow = false,
  }))
end

-- Print to Hyprland's log.
function M.print(text)
  print(text)
end

-- Omarchy's per-monitor workspaces, or nil when they are not loaded.
function M.omarchy_workspaces()
  local o = rawget(_G, "o")
  return type(o) == "table" and o.workspaces or nil
end

-- Whether a planner (hyprmoncfg) has switched Omarchy's workspaces off.
function M.omarchy_disabled()
  local workspaces = M.omarchy_workspaces()
  return workspaces ~= nil and workspaces.enabled == false
end

-- Workspace id of desk N on a monitor (by connector name).
function M.workspace_id(monitor_name, desk)
  return M.omarchy_workspaces().workspace_id({ name = monitor_name }, desk)
end

-- Show desk N on a monitor, the way Omarchy's Super+N does.
function M.focus_desk(desk, monitor_name)
  return hl().dispatch(M.omarchy_workspaces().focus(desk, monitor_name))
end

-- Register a bind action's replay expression with Omarchy's keybindings menu.
function M.bind_expression(action, expression)
  local o = rawget(_G, "o")
  if type(o) == "table" and type(o.bind_expressions) == "table" then
    o.bind_expressions[action] = expression
  end
  return action
end

-- The focused window as a plain table (see M.window), or nil.
function M.active_window()
  local window = hl().get_active_window()
  return window and M.window(window)
end

return M
