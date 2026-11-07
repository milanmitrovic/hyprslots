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

  function hl.get_windows()
    return hl.windows
  end

  function hl.get_workspaces()
    return hl.workspaces
  end

  function hl.dispatch(dispatcher)
    hl.dispatched[#hl.dispatched + 1] = dispatcher
    if type(dispatcher) == "function" then
      dispatcher()
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
    window = { move = dispatcher("window.move") },
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

  return hl
end

return M
