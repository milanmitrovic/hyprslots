-- Pick the arrangement that matches the connected monitors (docs/design.md §8).
--
-- Each arrangement names its screens: { role = "<description|serial|connector>" }.
-- A selector resolves to the monitor whose description equals it, else whose
-- serial does, else whose connector name does; empty descriptions and serials
-- never match (the laptop panel reports none, so it is named by connector).
-- An arrangement applies when every role resolves to a distinct monitor and no
-- monitor is left over. Ties go to the first name in sort order. Pure.

local M = {}

local FIELDS = { "description", "serial", "name" }

local function resolve(selector, monitors)
  for _, field in ipairs(FIELDS) do
    for _, monitor in ipairs(monitors) do
      local value = monitor[field]
      if value ~= nil and value ~= "" and value == selector then
        return monitor
      end
    end
  end
  return nil
end

local function match(arrangement, monitors)
  if #arrangement.roles ~= #monitors then
    return nil
  end
  local by_role, by_monitor = {}, {}
  for _, role in ipairs(arrangement.roles) do
    local monitor = resolve(arrangement.screens[role], monitors)
    if not monitor or by_monitor[monitor.name] then
      return nil
    end
    by_role[role] = monitor.name
    by_monitor[monitor.name] = role
  end
  return by_role, by_monitor
end

-- The active arrangement for these monitors ({ name, description, serial }
-- each), or nil when none matches:
--   { name, arrangement, monitors = role -> connector, roles = connector -> role }
function M.select(cfg, monitors)
  for _, name in ipairs(cfg.arrangement_names) do
    local arrangement = cfg.arrangements[name]
    local by_role, by_monitor = match(arrangement, monitors)
    if by_role then
      return { name = name, arrangement = arrangement, monitors = by_role, roles = by_monitor }
    end
  end
  return nil
end

return M
