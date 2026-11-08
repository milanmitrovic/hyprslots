-- Which desk the connected monitors are, and what a new desk for them looks
-- like (docs/design.md §8).
--
-- A desk is a monitor setup: a set of monitor selectors, each a monitor
-- description, else serial, else connector name (the laptop panel reports
-- no description, so it is named by connector). The desk whose selectors
-- are exactly the connected monitors (every selector a distinct monitor, no
-- monitor left over) is the active one; ties go to the first name in sort
-- order. Its layout's screen i is the i-th monitor from the left (by x, then
-- y, then connector name). Pure.

local M = {}

local FIELDS = { "description", "serial", "name" }

-- Hyprland's placeholder output while no real monitor is connected.
local PLACEHOLDER = { FALLBACK = true }

local function resolve(selector, monitors, taken)
  for _, field in ipairs(FIELDS) do
    for _, monitor in ipairs(monitors) do
      local value = monitor[field]
      if value ~= nil and value ~= "" and value == selector and not taken[monitor.name] then
        return monitor
      end
    end
  end
  return nil
end

-- The monitors a desk is made of: the connected ones, Hyprland's FALLBACK
-- placeholder left out.
function M.usable(monitors)
  local out = {}
  for _, monitor in ipairs(monitors or {}) do
    if not PLACEHOLDER[monitor.name] then
      out[#out + 1] = monitor
    end
  end
  return out
end

-- Monitors left to right: by x, then y, then connector name.
function M.order(monitors)
  local out = {}
  for i, monitor in ipairs(monitors) do
    out[i] = monitor
  end
  table.sort(out, function(a, b)
    local ax, bx = tonumber(a.x) or 0, tonumber(b.x) or 0
    if ax ~= bx then
      return ax < bx
    end
    local ay, by = tonumber(a.y) or 0, tonumber(b.y) or 0
    if ay ~= by then
      return ay < by
    end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

-- The monitor each selector finds (selector -> monitor), when they are
-- exactly these monitors; else nil.
function M.match(selectors, monitors)
  if #selectors ~= #monitors or #monitors == 0 then
    return nil
  end
  local taken, found = {}, {}
  for _, selector in ipairs(selectors) do
    local monitor = resolve(selector, monitors, taken)
    if not monitor then
      return nil
    end
    taken[monitor.name] = true
    found[selector] = monitor
  end
  return found
end

-- The connected monitor a selector finds on its own, or nil.
function M.find(selector, monitors)
  return resolve(selector, monitors, {})
end

-- Whether a monitor is a laptop's own panel (by its connector).
function M.internal(monitor)
  local name = tostring(monitor and monitor.name or "")
  return name:match("^eDP") ~= nil or name:match("^LVDS") ~= nil or name:match("^DSI") ~= nil
end

-- What a new desk selects a monitor by: its description, else its serial,
-- else its connector.
function M.selector(monitor)
  if monitor.description ~= nil and monitor.description ~= "" then
    return monitor.description
  end
  if monitor.serial ~= nil and monitor.serial ~= "" then
    return monitor.serial
  end
  return monitor.name
end

return M
