-- A stand-in for Hyprland's `hl` global, for driving hyprslots under busted
-- (test seam S2). Skeleton only: it grows with the Tracer slice.
--
--   local hl_stub = require("helpers.hl_stub")
--   local hl = hl_stub.new({ monitors = { { name = "HEADLESS-2", width = 1920, height = 1080 } } })
--   _G.hl = hl
--
-- Every dispatch is recorded in `hl.dispatched`, every event handler in
-- `hl.handlers[event]`, every registered layout in `hl.layouts[name]`.

local M = {}

function M.new(opts)
  opts = opts or {}

  local hl = {
    monitors = opts.monitors or {},
    windows = opts.windows or {},
    workspaces = opts.workspaces or {},
    dispatched = {},
    handlers = {},
    layouts = {},
    notifications = {},
  }

  function hl.get_monitors()
    return hl.monitors
  end

  function hl.get_windows()
    return hl.windows
  end

  function hl.get_workspaces()
    return hl.workspaces
  end

  function hl.dispatch(dispatcher)
    hl.dispatched[#hl.dispatched + 1] = dispatcher
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

  hl.layout = {
    register = function(name, provider)
      hl.layouts[name] = provider
    end,
  }

  hl.notification = {
    create = function(spec)
      hl.notifications[#hl.notifications + 1] = spec
    end,
  }

  return hl
end

return M
