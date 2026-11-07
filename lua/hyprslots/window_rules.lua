-- Generated window rules (docs/design.md §7b): a window whose class has a
-- class-only spec opens straight on that slot's workspace under the active
-- arrangement, instead of mapping on the focused workspace and jumping.
--
-- One rule per class, named "hyprslots-<class>": registering a rule under a
-- name Hyprland already has replaces it, so the rules are re-registered (only
-- when they change) after every arrangement change and every slot taken or
-- freed. Hyprland rules cannot be removed at runtime, only disabled, so a
-- rule with nothing to do is registered as { name, enabled = false }.
--
-- The rule for class C goes to the first free slot, in assignment precedence
-- order (desk, then slot name), whose spec could match a C window, or, when
-- every such slot is taken, to the first of them (the router sends an extra
-- C window to that desk's overflow leaf):
--   class-only spec  -> enabled, "<workspace> silent"
--   title or tag     -> disabled: only the title decides, so the router does
--   the slot is on no screen of the arrangement -> disabled
-- A rule is only an optimisation: the router places a window the same way
-- with or without it, and checks the workspace's screen either way.

local adapter = require("hyprslots.hl_adapter")
local assign = require("hyprslots.assign")

local M = {}

M.PREFIX = "hyprslots-"

-- A class as an anchored RE2 regex matching only itself.
function M.class_regex(class)
  return "^(" .. class:gsub("[%^%$%(%)%%%.%[%]%*%+%?%{%}|\\]", "\\%0") .. ")$"
end

-- class -> workspace id, or false, for every class some class-only spec names.
function M.desired(engine)
  local cfg = engine.cfg
  local candidates = assign.candidates(cfg)
  local taken = {}
  for _, assignment in pairs(engine.assignments) do
    taken[assignment.desk .. "\0" .. assignment.slot] = true
  end

  local classes = {}
  for _, candidate in ipairs(candidates) do
    if candidate.spec.kind == "class" then
      classes[candidate.spec.class] = false
    end
  end

  local decided = {}
  local function decide(class, value)
    if classes[class] ~= nil and not decided[class] then
      decided[class] = true
      classes[class] = value
    end
  end

  local function consider(candidate)
    local spec = candidate.spec
    if spec.kind == "class" then
      decide(spec.class, engine.active and engine:workspace_for(candidate) or false)
    elseif spec.kind == "title" then
      decide(spec.class, false)
    elseif spec.kind == "tag" then
      for class in pairs(spec.tm.browser_apps) do
        decide(class, false)
      end
    end
  end

  -- The first free slot that could take a window of the class ...
  for _, candidate in ipairs(candidates) do
    if not taken[candidate.desk .. "\0" .. candidate.slot] then
      consider(candidate)
    end
  end
  -- ... else, every such slot being taken, the first of them, whose desk's
  -- overflow leaf the router sends the window to (router.route).
  for _, candidate in ipairs(candidates) do
    consider(candidate)
  end
  return classes
end

-- Register every rule whose target changed since it was last registered.
function M.sync(engine)
  if engine.refused or not engine.cfg then
    return
  end
  engine.window_rules = engine.window_rules or {}
  local registered = engine.window_rules
  for class, workspace in pairs(M.desired(engine)) do
    if registered[class] ~= workspace then
      registered[class] = workspace
      local name = M.PREFIX .. class
      if workspace then
        engine.log:info("window rule %s: workspace %d", name, workspace)
        adapter.window_rule({
          name = name,
          enabled = true,
          match = { class = M.class_regex(class) },
          workspace = workspace .. " silent",
        })
      else
        engine.log:info("window rule %s: off", name)
        adapter.window_rule({ name = name, enabled = false })
      end
    end
  end
end

return M
