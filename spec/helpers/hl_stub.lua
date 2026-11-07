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
-- Groups: M.group({ w1, w2 }) puts windows in an HL.Group-like group;
-- dispatching group.toggle / window.move{out_of_group} changes membership the
-- way Hyprland would, and HL.Group:add is recorded in hl.group_adds.

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
-- so desk N on a monitor is block * 10 + N. Every focus action that runs is
-- recorded in `o.workspaces.focused` as { desk, monitor }.
function M.omarchy(blocks)
  local workspaces = { slots = 10, focused = {} }

  function workspaces.workspace_id(monitor, slot)
    return (blocks[monitor.name] or 0) * 10 + slot
  end

  function workspaces.focus(slot, monitor_name)
    return function()
      workspaces.focused[#workspaces.focused + 1] = { desk = slot, monitor = monitor_name }
    end
  end

  return { workspaces = workspaces, bind_expressions = {} }
end

function M.new(opts)
  opts = opts or {}

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
    window = { move = dispatcher("window.move"), resize = dispatcher("window.resize") },
    group = { toggle = dispatcher("group.toggle") },
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

  hl.group_adds = {}

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

-- An HL.Group-like group. `size` and `current` are derived from `members`,
-- as Hyprland's are live.
local Group = {}

local function group_index(self, key)
  if key == "size" then
    return #rawget(self, "members")
  elseif key == "current" then
    return rawget(self, "members")[rawget(self, "current_index")]
  end
  return Group[key]
end

function Group.add(self, window, index)
  local members = rawget(self, "members")
  table.insert(members, index or (#members + 1), window)
  window.group = self
  if self.hl then
    self.hl.group_adds[#self.hl.group_adds + 1] = { window = window.address, into = members[1].address }
  end
end

function Group.remove(self, window)
  local members = rawget(self, "members")
  for i, member in ipairs(members) do
    if member == window then
      table.remove(members, i)
      window.group = nil
      if rawget(self, "current_index") > #members then
        rawset(self, "current_index", math.max(1, #members))
      end
      return
    end
  end
end

-- Group `windows` (HL.Window-like tables); `current` is the index shown.
function M.group(windows, current, hl)
  local group = setmetatable({ members = {}, current_index = current or 1, hl = hl }, { __index = group_index })
  for _, window in ipairs(windows) do
    rawget(group, "members")[#rawget(group, "members") + 1] = window
    window.group = group
  end
  return group
end

-- What dispatching a described dispatcher does to the stub's windows.
M.effects = {
  ["group.toggle"] = function(hl, args)
    local window = hl.get_window(args.window)
    if not window then
      return
    end
    if window.group then
      for _, member in ipairs(rawget(window.group, "members")) do
        member.group = nil
      end
    else
      M.group({ window }, 1, hl)
    end
  end,
  ["window.move"] = function(hl, args)
    if args.out_of_group then
      local window = hl.get_window(args.window)
      if window and window.group then
        window.group:remove(window)
      end
    end
  end,
}

return M
