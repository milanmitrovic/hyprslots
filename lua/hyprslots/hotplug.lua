-- Monitor events -> arrangement selection and re-routing (docs/design.md §8).
--
-- Hyprland reports a monitor change from inside it, so nothing happens in the
-- event itself. Two oneshot hops follow:
--
--   1. re-select the arrangement for the monitors now connected;
--   2. re-route every assigned window to its slot's workspace under it.
--
-- Omarchy's monitor-workspaces reconciles on monitor.removed from a oneshot
-- timer it creates in the same event (and on monitor.added inside the event),
-- renumbering an unplugged screen's workspaces into the block of the screen
-- they landed on (13 becomes 4). Hop 2 is created while hop 1 runs, so it
-- runs after that timer whichever order same-timeout timers fire in, and sees
-- the workspaces as Omarchy left them. Nothing here focuses a monitor or
-- changes what a screen shows, so pinned screens stay as they are, with one
-- exception: a non-pinned screen that was just plugged in shows the active
-- desk (the last one switched to), and focus goes back where it was.

local adapter = require("hyprslots.hl_adapter")
local desks = require("hyprslots.desks")
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
    engine:guard(event .. ": arrangement selection", engine.reselect, engine)
    engine:guard(event .. ": window rules", window_rules.sync, engine)
    adapter.defer(function()
      engine:guard(event .. ": re-route", router.reroute_all, engine)
      engine:guard(event .. ": active desk", desks.show_active, engine, added)
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
