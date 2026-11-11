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

local vec2 -- defined below

-- Connected monitors that show workspaces of their own (mirrors excluded):
-- { name, description, serial, make?, model?, id, focused, x, y, width, height } (the
-- position orders a desk's screens left to right, desk.lua).
function M.monitors()
  local out = {}
  for _, monitor in ipairs(hl().get_monitors() or {}) do
    if not monitor.is_mirror then
      local px, py = vec2(monitor.position)
      out[#out + 1] = {
        name = monitor.name,
        description = monitor.description or "",
        serial = monitor.serial or "",
        make = monitor.make, -- not in HL.Monitor today; taken when Hyprland adds them
        model = monitor.model,
        id = monitor.id,
        focused = monitor.focused,
        x = monitor.x or px or 0,
        y = monitor.y or py or 0,
        width = monitor.width,
        height = monitor.height,
      }
    end
  end
  return out
end

-- An HL.Vec2-like value ({ x, y } or { [1], [2] }) as two numbers.
function vec2(value)
  if type(value) ~= "table" then
    return nil
  end
  local x, y = value.x or value[1], value.y or value[2]
  if type(x) == "number" and type(y) == "number" then
    return x, y
  end
  return nil
end

-- A window's box { x, y, w, h } from its at / size, or nil.
local function window_box(window)
  local x, y = vec2(window.at)
  local w, h = vec2(window.size)
  if x and w then
    return { x = x, y = y, w = w, h = h }
  end
  return nil
end

-- A plain copy of an HL.Window: { address, class, title, stable_id,
-- workspace_id, floating, box }.
function M.window(window)
  local workspace = window.workspace
  return {
    address = window.address,
    class = window.class,
    title = window.title,
    stable_id = window.stable_id,
    workspace_id = workspace and workspace.id,
    floating = window.floating == true,
    box = window_box(window),
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

-- Register (or, under a name Hyprland already has, replace) a window rule.
function M.window_rule(spec)
  return hl().window_rule(spec)
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

-- Workspace id of workspace N on a monitor (by connector name).
function M.workspace_id(monitor_name, workspace)
  return M.omarchy_workspaces().workspace_id({ name = monitor_name }, workspace)
end

-- Show workspace N on a monitor, the way Omarchy's Super+N does (the focused
-- monitor when monitor_name is nil).
function M.focus_workspace(workspace, monitor_name)
  return hl().dispatch(M.omarchy_workspaces().focus(workspace, monitor_name))
end

-- The connector of the monitor a workspace is on, or nil when it does not
-- exist.
function M.workspace_monitor(workspace_id)
  local workspace = hl().get_workspace(workspace_id)
  local monitor = workspace and workspace.monitor
  return monitor and monitor.name
end

-- Put a workspace on a monitor. A hidden workspace stays hidden there.
function M.move_workspace(workspace_id, monitor_name)
  return hl().dispatch(hl().dsp.workspace.move({ workspace = tostring(workspace_id), monitor = monitor_name }))
end

-- Focus a monitor (by connector name).
function M.focus_monitor(monitor_name)
  return hl().dispatch(hl().dsp.focus({ monitor = monitor_name }))
end

-- Replace whatever is bound to `keys`: through Omarchy's o.rebind when it is
-- loaded (so its keybindings menu lists the description), else hl directly.
function M.rebind(keys, description, action)
  local o = rawget(_G, "o")
  if type(o) == "table" and type(o.rebind) == "function" then
    return o.rebind(keys, description, action)
  end
  hl().unbind(keys)
  return hl().bind(keys, action, { description = description })
end

-- Register a bind action's replay expression with Omarchy's keybindings menu.
function M.bind_expression(action, expression)
  local o = rawget(_G, "o")
  if type(o) == "table" and type(o.bind_expressions) == "table" then
    o.bind_expressions[action] = expression
  end
  return action
end

-- Scrolling (scroll branches, see scroll.lua). ------------------------------

-- The tiled layout of workspace `id` ("scrolling", "lua:slots", ...), or nil
-- when it does not exist.
function M.workspace_tiled_layout(id)
  local workspace = hl().get_workspace(id)
  return workspace and workspace.tiled_layout
end

-- Omarchy's state directory (its paths module when it is loaded, else the
-- XDG default).
local function state_home()
  local ok, paths = pcall(require, "default.hypr.paths")
  if ok and type(paths) == "table" and type(paths.state_home) == "string" then
    return paths.state_home
  end
  local base = os.getenv("XDG_STATE_HOME")
  if not base or base == "" then
    base = (os.getenv("HOME") or "") .. "/.local/state"
  end
  return base
end

-- Whether Omarchy has a saved mode for workspace `id`: the file its
-- workspace-layout toggle (and the user's Super+L cycle) writes, which its
-- workspace-layouts.lua loads after hyprslots on every config load.
function M.omarchy_mode_saved(id)
  local file = io.open(string.format("%s/omarchy/workspace-layouts/%s.lua", state_home(), tostring(id)), "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- The tiled windows on workspace `id` that Hyprland's scrolling layout has a
-- column for: { address, stable_id, column = its 0-based index, row = the
-- window's index in it, width = the column's width (a fraction of the
-- screen) }, from HL.Window.layout.
function M.scroll_windows(id)
  local out = {}
  for _, window in ipairs(hl().get_windows() or {}) do
    local workspace = window.workspace
    local layout = workspace and workspace.id == id and not window.floating and window.layout
    local column = type(layout) == "table" and layout.name == "scrolling" and layout.column
    if type(column) == "table" and type(column.index) == "number" then
      out[#out + 1] = {
        address = window.address,
        stable_id = window.stable_id,
        column = column.index,
        row = layout.index_in_column or 0,
        width = column.width,
      }
    end
  end
  return out
end

-- Swap windows in pairs ({ a, b } addresses), focus kept: Hyprland's
-- window.swap keeps the focus but warps the cursor to the moved window, so
-- warps are off meanwhile (with cursor:no_warps Hyprland still focuses the
-- monitor under that point, so the focused monitor is put back too).
function M.swap_windows(swaps)
  local no_warps = hl().get_config("cursor.no_warps")
  local monitor = M.active_monitor_name()
  hl().config({ cursor = { no_warps = true } })
  local ok, err = pcall(function()
    for _, swap in ipairs(swaps) do
      hl().dispatch(hl().dsp.window.swap({ window = "address:" .. swap.a, target = "address:" .. swap.b }))
    end
    if monitor and M.active_monitor_name() ~= monitor then
      M.focus_monitor(monitor)
    end
  end)
  hl().config({ cursor = { no_warps = no_warps == true or no_warps == 1 } })
  if not ok then
    error(err, 0)
  end
end

-- The focused window as a plain table (see M.window), or nil.
function M.active_window()
  local window = hl().get_active_window()
  return window and M.window(window)
end

-- The focused workspace's tiled layout ("dwindle", "lua:slots", ...), or nil.
function M.active_layout()
  local workspace = hl().get_active_workspace()
  return workspace and workspace.tiled_layout
end

-- Send a message to the focused workspace's layout.
function M.layout_msg(msg)
  return hl().dispatch(hl().dsp.layout(msg))
end

-- Hyprland's own relative resize of the focused window.
function M.resize_window(dx, dy)
  return hl().dispatch(hl().dsp.window.resize({ x = dx, y = dy, relative = true }))
end

-- The id of the focused monitor's active workspace, or nil.
function M.active_workspace_id()
  local workspace = hl().get_active_workspace()
  return workspace and workspace.id
end

-- Emit `custom>>text` on socket2 (hyprctl dispatch event).
function M.emit_event(text)
  return hl().dispatch(hl().dsp.event(text))
end

-- Make Hyprland lay out the workspace holding a tiled window again: a lua
-- layout recalculates on any resize request (CLuaTiledAlgorithm::resizeTarget
-- discards the delta), so a zero resize is a relayout.
function M.nudge(address)
  return hl().dispatch(hl().dsp.window.resize({ x = 0, y = 0, relative = true, window = "address:" .. address }))
end

return M
