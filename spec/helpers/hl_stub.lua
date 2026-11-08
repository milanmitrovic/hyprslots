-- A stand-in for Hyprland's `hl` global (and Omarchy's `o.workspaces`), for
-- driving hyprslots under busted (test seam S2). Shapes follow
-- /usr/share/hypr/stubs/hl.meta.lua for Hyprland 0.56.2.
--
--   local hl_stub = require("helpers.hl_stub")
--   local hl = hl_stub.new({ monitors = { hl_stub.monitor("HEADLESS-2") } })
--   _G.hl = hl
--   _G.o = hl_stub.omarchy({ ["HEADLESS-2"] = 0 })
--
-- Recorded side effects:
--   hl.dispatched       every hl.dispatch argument (functions are also run)
--   hl.handlers[event]  every hl.on callback
--   hl.layouts[name]    every registered layout provider
--   hl.workspace_rules  every hl.workspace_rule spec
--   hl.timers           every hl.timer; hl.run_timers() fires the pending ones
--   hl.notifications    every hl.notification.create spec
--   hl.window_rules     every hl.window_rule spec
--
-- Config: hl.config(t) merges t into hl.config_values (hl.config_calls keeps
-- every call); hl.get_config("a.b") reads it back.
--
-- Scrolling: M.scrolling(hl) keeps Hyprland's scrolling layout's columns per
-- workspace (see there).

local M = {}

-- An HL.Monitor-like table.
function M.monitor(name, fields)
  local monitor = { name = name, description = "", serial = "", id = 0, focused = false, is_mirror = false }
  for key, value in pairs(fields or {}) do
    monitor[key] = value
  end
  return monitor
end

-- An HL.Window-like table: M.window(1, "t-main", { workspace = 3 }).
function M.window(stable_id, class, fields)
  local window = {
    address = string.format("0x%x", 0x1000 + stable_id),
    stable_id = stable_id,
    class = class,
    initial_class = class,
    title = class,
    mapped = true,
    floating = false,
  }
  for key, value in pairs(fields or {}) do
    window[key] = value
  end
  if type(window.workspace) == "number" then
    window.workspace = { id = window.workspace, name = tostring(window.workspace) }
  end
  return window
end

-- An HL.LayoutContext-like table over `area` with one target per window.
-- Each target records the box it was placed in as `target.placed`.
function M.layout_ctx(area, windows)
  local targets = {}
  for i, window in ipairs(windows) do
    targets[i] = {
      index = i,
      window = window,
      box = { x = 0, y = 0, w = 0, h = 0 },
      place = function(self, box)
        self.placed = { x = box.x, y = box.y, w = box.w, h = box.h }
      end,
    }
    targets[i].set_box = targets[i].place
  end
  return { area = area, targets = targets }
end

-- The boxes a recalculate placed, keyed by window class.
function M.placed_by_class(ctx)
  local out = {}
  for _, target in ipairs(ctx.targets) do
    out[rawget(target.window, "class") or target.index] = target.placed
  end
  return out
end

-- Omarchy's `o` with a fake `o.workspaces`: `blocks` maps connector -> block,
-- so workspace N on a monitor is block * 10 + N. Every focus action that runs is
-- recorded in `o.workspaces.focused` as { workspace, monitor }.
function M.omarchy(blocks)
  local workspaces = { slots = 10, focused = {} }

  function workspaces.workspace_id(monitor, slot)
    return (blocks[monitor.name] or 0) * 10 + slot
  end

  function workspaces.focus(slot, monitor_name)
    return function()
      workspaces.focused[#workspaces.focused + 1] = { workspace = slot, monitor = monitor_name }
    end
  end

  return { workspaces = workspaces, bind_expressions = {} }
end

function M.new(opts)
  opts = opts or {}

  -- Omarchy's paths module, for the saved-mode files hyprslots looks for:
  -- never the machine's own state directory (a spec may set its own first).
  package.loaded["default.hypr.paths"] = package.loaded["default.hypr.paths"]
    or { state_home = "/nonexistent/hyprslots-spec-state" }

  local hl = {
    monitors = opts.monitors or {},
    windows = opts.windows or {},
    workspaces = opts.workspaces or {},
    dispatched = {},
    handlers = {},
    layouts = {},
    workspace_rules = {},
    timers = {},
    notifications = {},
  }

  function hl.get_monitors()
    return hl.monitors
  end

  function hl.get_monitor(selector)
    for _, monitor in ipairs(hl.monitors) do
      if monitor.name == selector then
        return monitor
      end
    end
    return nil
  end

  function hl.get_active_monitor()
    for _, monitor in ipairs(hl.monitors) do
      if monitor.focused then
        return monitor
      end
    end
    return hl.monitors[1]
  end

  function hl.get_active_workspace()
    if hl.active_workspace then
      return hl.active_workspace
    end
    local monitor = hl.get_active_monitor()
    return monitor and monitor.active_workspace
  end

  function hl.get_windows()
    return hl.windows
  end

  function hl.get_workspaces()
    return hl.workspaces
  end

  function hl.get_workspace(selector)
    for _, workspace in ipairs(hl.workspaces) do
      if workspace.id == tonumber(selector) then
        return workspace
      end
    end
    return nil
  end

  function hl.dispatch(dispatcher)
    hl.dispatched[#hl.dispatched + 1] = dispatcher
    if type(dispatcher) == "function" then
      dispatcher()
    elseif type(dispatcher) == "table" and M.effects[dispatcher.dsp] then
      M.effects[dispatcher.dsp](hl, dispatcher.args or {})
    end
    return true
  end

  -- Dispatchers are plain descriptions: { dsp = "window.move", args = {...} }.
  local function dispatcher(name)
    return function(args)
      return { dsp = name, args = args }
    end
  end

  hl.dsp = {
    focus = dispatcher("focus"),
    exit = dispatcher("exit"),
    event = dispatcher("event"),
    layout = dispatcher("layout"),
    window = { move = dispatcher("window.move"), resize = dispatcher("window.resize"), swap = dispatcher("window.swap") },
    workspace = { move = dispatcher("workspace.move") },
  }

  -- The dispatches made so far whose `dsp` is `name`.
  function hl.dispatched_of(name)
    local out = {}
    for _, d in ipairs(hl.dispatched) do
      if type(d) == "table" and d.dsp == name then
        out[#out + 1] = d.args
      end
    end
    return out
  end

  function hl.on(event, callback)
    hl.handlers[event] = hl.handlers[event] or {}
    table.insert(hl.handlers[event], callback)
    return {
      is_active = function() return true end,
      remove = function() end,
    }
  end

  -- Fire an event the way Hyprland would, to every handler registered for it.
  function hl.emit(event, ...)
    for _, callback in ipairs(hl.handlers[event] or {}) do
      callback(...)
    end
  end

  function hl.timer(callback, timer_opts)
    local timer = { callback = callback, opts = timer_opts, pending = true }
    hl.timers[#hl.timers + 1] = timer
    return {
      is_enabled = function() return timer.pending end,
      set_enabled = function(_, enabled) timer.pending = enabled end,
      set_timeout = function() end,
    }
  end

  -- Fire every pending timer once (oneshots are then done).
  function hl.run_timers()
    local due = {}
    for _, timer in ipairs(hl.timers) do
      if timer.pending then
        due[#due + 1] = timer
        if timer.opts and timer.opts.type == "oneshot" then
          timer.pending = false
        end
      end
    end
    for _, timer in ipairs(due) do
      timer.callback()
    end
  end

  function hl.workspace_rule(spec)
    hl.workspace_rules[#hl.workspace_rules + 1] = spec
    return { is_enabled = function() return true end, set_enabled = function() end }
  end

  hl.window_rules = {}
  function hl.window_rule(spec)
    hl.window_rules[#hl.window_rules + 1] = spec
    return { is_enabled = function() return spec.enabled ~= false end, set_enabled = function() end }
  end

  hl.layout = {
    register = function(name, provider)
      hl.layouts[name] = provider
    end,
  }

  hl.notification = {
    create = function(spec)
      hl.notifications[#hl.notifications + 1] = spec
      return {}
    end,
  }

  hl.config_values, hl.config_calls = {}, {}
  local function merge(into, from)
    for key, value in pairs(from) do
      if type(value) == "table" then
        into[key] = into[key] or {}
        merge(into[key], value)
      else
        into[key] = value
      end
    end
  end
  function hl.config(values)
    hl.config_calls[#hl.config_calls + 1] = values
    merge(hl.config_values, values)
  end
  function hl.get_config(key)
    local value = hl.config_values
    for part in key:gmatch("[^%.]+") do
      if type(value) ~= "table" then
        return nil
      end
      value = value[part]
    end
    return value
  end

  -- HL.WindowSelector "address:0x..." over hl.windows.
  function hl.get_window(selector)
    local address = type(selector) == "string" and selector:match("^address:(.+)$")
    for _, window in ipairs(hl.windows) do
      if window.address == address then
        return window
      end
    end
    return nil
  end

  -- Keyboard resize (slice 5): the focused window and workspace are whatever
  -- the test sets as hl.active_window / hl.active_workspace (else the focused
  -- monitor's active_workspace); hl.binds maps
  -- keys -> { dispatcher, opts } and hl.unbound lists every hl.unbind.
  hl.binds, hl.unbound = {}, {}

  function hl.get_active_window()
    return hl.active_window
  end

  function hl.bind(keys, dispatcher, bind_opts)
    hl.binds[keys] = { dispatcher = dispatcher, opts = bind_opts }
    return {}
  end

  function hl.unbind(keys)
    hl.unbound[#hl.unbound + 1] = keys
    hl.binds[keys] = nil
  end

  return hl
end

-- Make `hl` keep workspaces the way Hyprland does, for specs that follow
-- windows and workspaces across screens. Opt-in; afterwards:
--   hl.workspaces          { id, name, monitor = <HL.Monitor>, windows }
--   hl.get_workspace(id)   by number or numeric string
--   window.move            moves a window in hl.windows (by "address:...")
--                          to a workspace, creating it on the FOCUSED
--                          monitor when it does not exist yet
--   workspace.move         puts a workspace on another monitor
--   hl.add_workspace(id, monitor_name) creates one directly
function M.simulate(hl)
  local function find_workspace(id)
    id = tonumber(id)
    for _, workspace in ipairs(hl.workspaces) do
      if workspace.id == id then
        return workspace
      end
    end
    return nil
  end

  -- Windows already in hl.windows on that id join it.
  function hl.add_workspace(id, monitor_name)
    local workspace = { id = id, name = tostring(id), monitor = hl.get_monitor(monitor_name), windows = 0 }
    for _, window in ipairs(hl.windows) do
      if window.workspace and window.workspace.id == id then
        window.workspace = workspace
        workspace.windows = workspace.windows + 1
      end
    end
    hl.workspaces[#hl.workspaces + 1] = workspace
    return workspace
  end

  function hl.get_workspace(selector)
    return find_workspace(selector)
  end

  local function find_window(selector)
    local address = type(selector) == "string" and selector:match("^address:(.+)$")
    for _, window in ipairs(hl.windows) do
      if window.address == address then
        return window
      end
    end
    return nil
  end

  local plain = hl.dispatch
  function hl.dispatch(dispatcher)
    local result = plain(dispatcher)
    if type(dispatcher) ~= "table" then
      return result
    end
    local args = dispatcher.args or {}
    if dispatcher.dsp == "window.move" and args.workspace then
      local window = find_window(args.window)
      local workspace = find_workspace(args.workspace)
        or hl.add_workspace(tonumber(args.workspace), hl.get_active_monitor().name)
      if window then
        local from = window.workspace and find_workspace(window.workspace.id)
        if from then
          from.windows = from.windows - 1
        end
        workspace.windows = workspace.windows + 1
        window.workspace = workspace
      end
    elseif dispatcher.dsp == "workspace.move" and args.workspace and args.monitor then
      local workspace = find_workspace(args.workspace)
      if workspace then
        workspace.monitor = hl.get_monitor(args.monitor)
      end
    end
    return result
  end

  return hl
end

-- Make `hl` keep Hyprland's scrolling layout (0.56.2,
-- src/layout/algorithm/tiled/scrolling) for the workspaces whose
-- `tiled_layout` is "scrolling", for the scroll-branch specs. Opt-in, after
-- M.simulate(hl); afterwards:
--   hl.columns[id]          { address, ... } in column order (one window per
--                           column), widths in hl.widths[address]
--   window.layout           { name = "scrolling", column = { index (0-based),
--                           width, windows }, index_in_column = 0 }, as
--                           HL.Window's `layout` reads, on every get_windows
--   hl.workspace_rule       a `layout` sets the workspace's tiled_layout
--   hl.open(window)         a window opening: its column goes after the
--                           focused column of its workspace, else at the end
--   window.move             a window moved in goes last (focus is elsewhere)
--   window.swap             { window, target }: the two trade places
--   layout "colresize all W" / "colresize W"  on the focused window's
--                           workspace / column; "fit_into_view" is recorded
-- New columns are DEFAULT_WIDTH (0.49, Omarchy's side-by-side) wide.
function M.scrolling(hl)
  local DEFAULT_WIDTH = 0.49
  hl.columns, hl.widths = {}, {}

  local function workspace(id)
    return hl.get_workspace(id)
  end

  local function scrolling(id)
    local ws = workspace(id)
    return ws and ws.tiled_layout == "scrolling"
  end

  local function remove(address)
    hl.widths[address] = nil -- a column that comes back is a new one
    for _, columns in pairs(hl.columns) do
      for i, column in ipairs(columns) do
        if column == address then
          table.remove(columns, i)
          return
        end
      end
    end
  end

  local function find(address)
    for _, window in ipairs(hl.windows) do
      if window.address == address then
        return window
      end
    end
  end

  -- Insert a tiled window's column on its workspace when that scrolls.
  local function insert(window, after_focused)
    local id = window.workspace and window.workspace.id
    remove(window.address)
    if not id or window.floating or not scrolling(id) then
      return
    end
    hl.columns[id] = hl.columns[id] or {}
    local columns = hl.columns[id]
    local at = #columns + 1
    local active = hl.active_window
    if after_focused and active and active.workspace and active.workspace.id == id then
      for i, address in ipairs(columns) do
        if address == active.address then
          at = i + 1
        end
      end
    end
    table.insert(columns, at, window.address)
    hl.widths[window.address] = DEFAULT_WIDTH
  end

  local function refresh()
    for _, window in ipairs(hl.windows) do
      window.layout = nil
    end
    for id, columns in pairs(hl.columns) do
      if scrolling(id) then
        for i, address in ipairs(columns) do
          local window = find(address)
          if window then
            window.layout = {
              name = "scrolling",
              column = { index = i - 1, width = hl.widths[address], windows = { window } },
              index_in_column = 0,
            }
          end
        end
      end
    end
  end

  -- A window opening (added to hl.windows if it is not there yet).
  function hl.open(window)
    if not find(window.address) then
      hl.windows[#hl.windows + 1] = window
    end
    insert(window, true)
  end

  -- Classes on workspace `id` in column order.
  function hl.column_classes(id)
    local out = {}
    for _, address in ipairs(hl.columns[id] or {}) do
      local window = find(address)
      out[#out + 1] = window and window.class or address
    end
    return out
  end

  local get_windows, get_window = hl.get_windows, hl.get_window
  function hl.get_windows(...)
    refresh()
    return get_windows(...)
  end
  function hl.get_window(...)
    refresh()
    return get_window(...)
  end

  -- Workspace rules apply when a workspace is created, too.
  local add_workspace = hl.add_workspace
  function hl.add_workspace(id, monitor_name)
    local ws = add_workspace(id, monitor_name)
    for _, spec in ipairs(hl.workspace_rules) do
      if tonumber(spec.workspace) == id and spec.layout then
        ws.tiled_layout = spec.layout
      end
    end
    for _, window in ipairs(hl.windows) do
      if window.workspace == ws then
        insert(window, false)
      end
    end
    return ws
  end

  local rule = hl.workspace_rule
  function hl.workspace_rule(spec)
    local result = rule(spec)
    local id = tonumber(spec.workspace)
    local ws = id and workspace(id)
    if ws and spec.layout then
      ws.tiled_layout = spec.layout
      hl.columns[id] = nil
      for _, window in ipairs(hl.windows) do
        if window.workspace and window.workspace.id == id then
          insert(window, false)
        end
      end
    end
    return result
  end

  local dispatch = hl.dispatch
  function hl.dispatch(dispatcher)
    local result = dispatch(dispatcher)
    if type(dispatcher) ~= "table" then
      return result
    end
    local args = dispatcher.args or {}
    if dispatcher.dsp == "window.move" and args.workspace then
      local window = hl.get_window(args.window)
      if window then
        insert(window, false)
      end
    elseif dispatcher.dsp == "window.swap" then
      local a, b = args.window and args.window:match("^address:(.+)$"), args.target and args.target:match("^address:(.+)$")
      for _, columns in pairs(hl.columns) do
        for i, address in ipairs(columns) do
          if address == a then
            columns[i] = b
          elseif address == b then
            columns[i] = a
          end
        end
      end
    elseif dispatcher.dsp == "layout" then
      local msg = args[1] or args
      local active = hl.active_window
      local id = active and active.workspace and active.workspace.id
      local all, width = tostring(msg):match("^colresize (all) ([%d%.]+)$")
      if not all then
        width = tostring(msg):match("^colresize ([%d%.]+)$")
      end
      if width and id and scrolling(id) then
        for _, address in ipairs(hl.columns[id] or {}) do
          if all or address == active.address then
            hl.widths[address] = tonumber(width)
          end
        end
      end
    end
    return result
  end

  return hl
end

-- What dispatching a described dispatcher does to the stub's windows (none
-- yet; M.simulate and M.scrolling layer their effects over hl.dispatch).
M.effects = {}

return M
