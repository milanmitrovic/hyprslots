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

-- The active desk for these monitors ({ name, description, serial, x, y }
-- each), or nil when no desk is them:
--   { desk = name, layout = layout name, entry = cfg.layouts[layout],
--     monitors = screen -> connector, screens = connector -> screen }
function M.select(cfg, monitors)
  monitors = M.usable(monitors)
  for _, name in ipairs(cfg.desk_names or {}) do
    local desk = cfg.desks[name]
    if M.match(desk.monitors, monitors) then
      local by_screen, by_monitor = {}, {}
      for i, monitor in ipairs(M.order(monitors)) do
        by_screen[i] = monitor.name
        by_monitor[monitor.name] = i
      end
      return { desk = name, layout = desk.layout, entry = cfg.layouts[desk.layout], monitors = by_screen,
        screens = by_monitor }
    end
  end
  return nil
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

local function slug(text)
  local out = tostring(text):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return out
end

-- A short name for one monitor: `laptop` for the laptop's panel, else the
-- last word of its description that is not its serial (the model, as in
-- "Samsung Electric Company Odyssey G95NC HNTW700044" -> g95nc), else its
-- connector (headless-2).
function M.short_name(monitor)
  if M.internal(monitor) then
    return "laptop"
  end
  local words = {}
  for word in tostring(monitor.description or ""):gmatch("%S+") do
    if word ~= monitor.serial then
      words[#words + 1] = word
    end
  end
  for i = #words, 1, -1 do
    local name = slug(words[i])
    if name ~= "" then
      return name
    end
  end
  local name = slug(monitor.name)
  return name ~= "" and name or "screen"
end

-- A name for a desk of these monitors that is not in `taken` (name -> any):
-- their short names left to right, joined with "+" (laptop+g95nc), then
-- "-2", "-3"... when it is taken.
function M.name_for(monitors, taken)
  local parts = {}
  for i, monitor in ipairs(M.order(monitors)) do
    parts[i] = M.short_name(monitor)
  end
  local base = table.concat(parts, "+")
  if base == "" then
    base = "desk"
  end
  local name, n = base, 1
  while taken and taken[name] ~= nil do
    n = n + 1
    name = base .. "-" .. n
  end
  return name
end

-- The trees of a new layout for these monitors (left to right), in data
-- form ({ [1] = "h[left, main, right]" }): screen 1 shows `left`, `main`
-- and `right` (those of them that are slots; else every slot, by name) side
-- by side, as a scroll branch when it is a laptop's panel; the other screens
-- show nothing. `slot_names` lists the global slots.
function M.default_trees(monitors, slot_names)
  local ordered = M.order(monitors)
  local defined, names = {}, {}
  for _, name in ipairs(slot_names or {}) do
    defined[name] = true
  end
  for _, name in ipairs({ "left", "main", "right" }) do
    if defined[name] then
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    for _, name in ipairs(slot_names or {}) do
      names[#names + 1] = name
    end
  end
  if #names == 0 or #ordered == 0 then
    return {}
  end
  local kind = M.internal(ordered[1]) and "scroll" or "h"
  local text = (#names == 1 and kind == "h") and names[1] or (kind .. "[" .. table.concat(names, ", ") .. "]")
  return { [1] = text }
end

-- The name a new layout for `count` screens with these trees (data form)
-- takes before a free one is found: what it arranges, never the desk's
-- name (a desks table reading "laptop -> laptop" says nothing): "scroll"
-- for one screen scrolling, else "<count>-screen".
function M.layout_name_for(count, trees)
  local first = trees and trees[1]
  if count == 1 and type(first) == "string" and first:match("^scroll%[") then
    return "scroll"
  end
  return count .. "-screen"
end

return M
