-- Monitor events -> desk selection and re-routing (docs/design.md §8).
--
-- Hyprland reports a monitor change from inside it, so nothing happens in the
-- event itself. Two oneshot hops follow:
--
--   1. re-select the desk for the monitors now connected;
--   2. re-route every assigned window to its slot's workspace under it,
--      which ends by asking for the scroll pass (scroll.lua), so scroll
--      columns are ordered only once the windows are where they belong.
--
-- Omarchy's monitor-workspaces reconciles on monitor.removed from a oneshot
-- timer it creates in the same event (and on monitor.added inside the event),
-- and blocks.lua runs ahead of that reconcile: the screens of the desk for
-- what is connected take their blocks and the workspaces are renumbered into
-- them (an unplugged screen 2's 13 joins screen 1's 3). Hop 1 re-selects
-- (Engine:reselect syncs the blocks again first, a no-op once Omarchy's timer
-- has run); hop 2 is created while hop 1 runs, so it runs after that timer
-- whichever order same-timeout timers fire in, and sees the workspaces
-- renumbered. A monitor turned off in the config is reported the same way,
-- as monitor.removed / monitor.added. Nothing here focuses a monitor or
-- changes what a screen shows, with one exception: a screen that was just
-- plugged in shows the active workspace (the last one switched to), and
-- focus goes back where it was.

local adapter = require("hyprslots.hl_adapter")
local workspaces = require("hyprslots.workspaces")
local router = require("hyprslots.router")
local window_rules = require("hyprslots.window_rules")

local M = {}

local function connected()
  local names = {}
  for _, monitor in ipairs(adapter.monitors()) do
    names[monitor.name] = true
  end
  return names
end

function M.monitors_changed(engine, event)
  adapter.defer(function()
    local before = engine.connected or {}
    engine.connected = connected()
    local added = {}
    for name in pairs(engine.connected) do
      if not before[name] then
        added[name] = true
      end
    end
    engine:guard(event .. ": desk selection", engine.reselect, engine)
    engine:guard(event .. ": window rules", window_rules.sync, engine)
    adapter.defer(function()
      engine:guard(event .. ": re-route", router.reroute_all, engine)
      engine:guard(event .. ": active workspace", workspaces.show_active, engine, added)
    end)
  end)
end

function M.attach(engine)
  engine.connected = connected()
  for _, event in ipairs({ "monitor.added", "monitor.removed" }) do
    adapter.on(event, function()
      M.monitors_changed(engine, event)
    end)
  end
end

return M
