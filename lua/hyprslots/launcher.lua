-- Launching apps, the engine's half (docs/design.md §9, Launching apps):
-- launch.lua says what to launch; this runs it. It finds an app's desktop
-- entry (desktop.lua), starts the apps a workspace's empty slots wait for
-- (on demand: the api's launch_missing; at login: Hyprland's start), and
-- holds each launch's claim on its slot (`engine.launching`, "<n>/<slot>")
-- until the app's window opens and takes it (launched_for) or the claim
-- runs out.

local adapter = require("hyprslots.hl_adapter")
local desktop = require("hyprslots.desktop")
local edit = require("hyprslots.edit")
local edits = require("hyprslots.edits")
local launch = require("hyprslots.launch")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local M = {}

-- How long an app launched for a slot counts as on its way (no second
-- launch for the slot meanwhile).
local LAUNCH_WAIT_MS = 20000
-- At login: the wait after Hyprland's start, and between two apps.
local LOGIN_WAIT_MS = 1500
local LOGIN_STAGGER_MS = 400

-- fn(class) -> desktop id, command: the entry the data recorded for the
-- class, else the one desktop.resolve finds; cached for the Lua state.
local function desktop_resolver(engine)
  engine.desktop_cache = engine.desktop_cache or {}
  return function(class)
    local stored = engine.cfg and engine.cfg.desktop_ids and engine.cfg.desktop_ids[class]
    local key = class .. "\0" .. (stored or "")
    if engine.desktop_cache[key] == nil then
      local dirs = engine.desktop_dirs or desktop.dirs()
      local id, command
      if stored then
        id, command = stored, desktop.command(stored, dirs)
      end
      if not command then
        id, command = desktop.resolve(class, dirs)
      end
      engine.desktop_cache[key] = command and { id = id, command = command } or false
    end
    local hit = engine.desktop_cache[key]
    if hit then
      return hit.id, hit.command
    end
    return nil
  end
end

-- How a spec's app launches (launch.command): { command } or { reason }.
function M.command(engine, entry)
  return launch.command(entry, engine.cfg and engine.cfg.launch_commands, desktop_resolver(engine))
end

-- The data with the desktop id of the app of each spec of `texts` that
-- names a class recorded, where one is found, it is new and the data's to
-- hold (a title spec's too: its app is known, though launching it takes a
-- command of config.lua's).
function M.with_desktop_ids(engine, data, texts)
  if not edit.editable(edits.read_only_paths(engine.cfg), "desktop_ids") then
    return data
  end
  local resolve = desktop_resolver(engine)
  for _, text in ipairs(texts) do
    local entry = spec.parse(text, engine.cfg and engine.cfg.title_matching)
    if entry and entry.class then
      local id = resolve(entry.class)
      local known = type(data.desktop_ids) == "table" and data.desktop_ids[entry.class]
      if id and known ~= id then
        data = edit.set_desktop_id(data, entry.class, id) or data
      end
    end
  end
  return data
end

-- The workspace id slot `slot` of workspace n is on: its screen's, else
-- the first screen's.
local function slot_workspace_id(engine, n, slot)
  for id, entry in pairs(engine.workspaces) do
    if entry.workspace == n then
      for _, s in ipairs(tree.slots(entry.branch)) do
        if s == slot then
          return id
        end
      end
    end
  end
  if engine.active and engine.active.monitors[1] then
    return adapter.workspace_id(engine.active.monitors[1], n)
  end
  return n
end

-- Launch the apps workspace n's empty slots wait for (launch.missing), each
-- onto its slot's workspace, silently; `stagger` ms apart when given.
-- Returns launch.missing's plan.
function M.workspace(engine, n, stagger)
  engine.launching = engine.launching or {}
  local pending = {}
  for key in pairs(engine.launching) do
    local ws, slot = key:match("^(%d+)/(.+)$")
    if tonumber(ws) == n then
      pending[slot] = true
    end
  end
  local plan = launch.missing({
    workspace = n,
    specs = engine.cfg.specs[n] or {},
    assignments = engine.assignments,
    windows = adapter.windows(),
    pending = pending,
    command = function(entry) return M.command(engine, entry) end,
  })
  for i, item in ipairs(plan.launch) do
    local key = n .. "/" .. item.slot
    local id = slot_workspace_id(engine, n, item.slot)
    engine.launching[key] = true
    engine.log:info("launch %s for %s on workspace %d: %s", item.spec, item.slot, n, item.command)
    local function run()
      engine:guard("launch " .. item.command, adapter.exec, item.command, id)
    end
    if stagger and i > 1 then
      adapter.defer(run, (i - 1) * stagger)
    else
      run()
    end
    adapter.defer(function() engine.launching[key] = nil end, LAUNCH_WAIT_MS)
  end
  return plan
end

-- At Hyprland's start (never on a config reload): after a wait, the
-- missing apps of every workspace set to launch at login, one after
-- another.
function M.at_login(engine)
  adapter.defer(function()
    if not engine.cfg or engine.refused then
      return
    end
    local list = {}
    for n, mode in pairs(engine.cfg.launch) do
      if mode == "at_login" then
        list[#list + 1] = n
      end
    end
    table.sort(list)
    for i, n in ipairs(list) do
      local function run()
        engine:guard("launch at login", M.workspace, engine, n, LOGIN_STAGGER_MS)
      end
      if i == 1 then
        run()
      else
        adapter.defer(run, (i - 1) * LOGIN_STAGGER_MS * 4)
      end
    end
  end, LOGIN_WAIT_MS)
end

-- The slot an app was launched for (M.workspace: the api's launch_missing,
-- at login) that this window, opening, is: one still on its way, empty,
-- whose spec matches it. The claim is used up. Nil for none. The first by
-- workspace, as a number (5 before 10), then by slot name.
function M.launched_for(engine, window)
  if not engine.launching or next(engine.launching) == nil then
    return nil
  end
  local waiting = {}
  for key in pairs(engine.launching) do
    local n, slot = key:match("^(%d+)/(.+)$")
    if n then
      waiting[#waiting + 1] = { key = key, workspace = tonumber(n), slot = slot }
    end
  end
  table.sort(waiting, function(a, b)
    if a.workspace ~= b.workspace then
      return a.workspace < b.workspace
    end
    return a.slot < b.slot
  end)
  local taken = {}
  for _, a in pairs(engine.assignments) do
    taken[a.workspace .. "/" .. a.slot] = true
  end
  for _, w in ipairs(waiting) do
    local entry = engine.cfg.specs[w.workspace] and engine.cfg.specs[w.workspace][w.slot]
    if entry and not taken[w.key] and spec.match(entry, window) then
      engine.launching[w.key] = nil
      return { workspace = w.workspace, slot = w.slot }
    end
  end
  return nil
end

return M
