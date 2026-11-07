-- hyprslots: deterministic named window layouts for Hyprland (docs/design.md).
--
--   hyprslots = require("hyprslots")
--   hyprslots.setup()
--
-- setup() never raises: any error becomes an hl.notification plus a log entry
-- (see hyprslots.dump()), and Hyprland keeps running. Lua state does not
-- survive a config reload, so every setup() rebuilds the engine from the
-- config and the live windows and monitors.

local adapter = require("hyprslots.hl_adapter")
local api = require("hyprslots.api")
local arrangement = require("hyprslots.arrangement")
local assign = require("hyprslots.assign")
local config = require("hyprslots.config")
local desks = require("hyprslots.desks")
local layout = require("hyprslots.layout")
local log = require("hyprslots.log")
local router = require("hyprslots.router")
local tree = require("hyprslots.tree")

local M = {}

local LAYOUT = "slots"
local BLOCKS = 10 -- Omarchy monitor blocks given lua:slots desk workspaces

local engine = nil

local Engine = {}
Engine.__index = Engine

local function new_engine()
  return setmetatable({
    log = log.new({
      sink = function(entry)
        if entry.level ~= "info" then
          adapter.print("[hyprslots] " .. entry.level .. ": " .. entry.text)
        end
      end,
    }),
    cfg = nil,
    config_error = nil,
    refused = nil,
    active = nil,
    workspaces = {}, -- workspace id -> { desk, role, monitor, branch }
    assignments = {}, -- window address -> { desk, slot }
    seq = 0, -- bumped on every change the editor should see
    started = false,
    config_dir = nil,
    data = nil, -- the editor-owned slots.lua data the running config came from
    dirty = false, -- data differs from slots.lua on disk
    ruled = {}, -- workspace ids given lua:slots
  }, Engine)
end

-- Stop managing windows, and say so once.
function Engine:refuse(reason)
  if self.refused then
    return
  end
  self.refused = reason
  self.log:error("refusing to start: %s", reason)
  adapter.notify("hyprslots is off: " .. reason, "error")
end

-- Re-pick the arrangement for the connected monitors and rebuild the map from
-- workspace id to desk and screen role.
function Engine:reselect()
  local previous = self.active and self.active.name
  self.active = nil
  self.workspaces = {}
  if not self.cfg or self.refused then
    return
  end

  local monitors = adapter.monitors()
  self.active = arrangement.select(self.cfg, monitors)

  if self.active then
    for desk, branches in pairs(self.active.arrangement.desks) do
      for role, branch in pairs(branches) do
        local monitor = self.active.monitors[role]
        local id = adapter.workspace_id(monitor, desk)
        self.workspaces[id] = { desk = desk, role = role, monitor = monitor, branch = branch }
      end
    end
  end

  local now = self.active and self.active.name
  if now ~= previous and self.started then
    self:changed()
  end
  if now ~= previous then
    local names = {}
    for _, monitor in ipairs(monitors) do
      names[#names + 1] = monitor.name
    end
    self.log:info("arrangement %s (monitors: %s)", tostring(now), table.concat(names, ", "))
  end
end

-- Assign every live window (on load: nothing survives a reload).
function Engine:assign_all()
  if not self.cfg then
    return
  end
  self.assignments = assign.solve(self.cfg, adapter.windows(), self.assignments)
end

-- The slot of a plain window ({ address, class, stable_id }), claiming one
-- when it has none yet. Nil when it matches no free slot.
function Engine:assign(window)
  if not self.cfg or not window.address then
    return nil
  end
  local assignment = assign.claim(self.cfg, self.assignments, window)
  if assignment and not self.assignments[window.address] then
    self.assignments[window.address] = assignment
  end
  return assignment
end

-- The slot of an HL.Window, for recalculate.
function Engine:slot_of(hl_window)
  local known = self.assignments[hl_window.address]
  if known then
    return known
  end
  return self:assign(adapter.window(hl_window))
end

-- { desk, role, monitor, branch } for a workspace id, or nil.
function Engine:desk_of_workspace(id)
  if self.refused or id == nil then
    return nil
  end
  return self.workspaces[id]
end

-- The workspace id an assignment lives on in the active arrangement, or nil.
function Engine:workspace_for(assignment)
  for id, desk in pairs(self.workspaces) do
    if desk.desk == assignment.desk then
      for _, slot in ipairs(tree.slots(desk.branch)) do
        if slot == assignment.slot then
          return id
        end
      end
    end
  end
  return nil
end

-- hyprmoncfg's planner replaces o.workspaces after hyprslots loads, so this
-- runs on hyprland.start / config.reloaded, not at require time.
function Engine:check_omarchy()
  if adapter.omarchy_workspaces() == nil then
    self:refuse("Omarchy's o.workspaces is not loaded")
  elseif adapter.omarchy_disabled() then
    self:refuse("o.workspaces.enabled = false (turn hyprmoncfg's workspace planner Off)")
  end
end

-- Run fn, turning an error into a log entry; returns whether it succeeded.
function Engine:guard(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    self.log:error("%s failed: %s", what, tostring(err))
  end
  return ok
end

local function load_config(self, dir)
  self.config_dir = dir
  local cfg, err, missing = config.load(dir)
  if cfg then
    self.cfg = cfg
    local file = cfg.data_files["slots.lua"]
    self.data = file and file.data
    self.log:info("config loaded: %d arrangement(s)", #cfg.arrangement_names)
    return
  end
  self.config_error = err
  if missing then
    self.log:info("%s", err)
  else
    self.log:error("config: %s", err)
    adapter.notify("hyprslots config error: " .. err, "error")
  end
end

-- lua:slots for desk N's workspace in every monitor block, for every desk
-- some arrangement has a tree for. Workspace rules apply when a workspace is
-- created, so they are set once, up front.
local function workspace_rules(cfg, ruled)
  local desks_with_trees = {}
  for _, name in ipairs(cfg.arrangement_names) do
    for desk in pairs(cfg.arrangements[name].desks) do
      desks_with_trees[desk] = true
    end
  end
  local list = {}
  for desk in pairs(desks_with_trees) do
    list[#list + 1] = desk
  end
  table.sort(list)
  for _, desk in ipairs(list) do
    for block = 0, BLOCKS - 1 do
      local id = block * 10 + desk
      if not ruled[id] then
        ruled[id] = true
        adapter.workspace_layout(id, "lua:" .. LAYOUT)
      end
    end
  end
end

local function start(self, opts)
  adapter.register_layout(LAYOUT, layout.provider(self))

  if adapter.omarchy_workspaces() == nil then
    self:refuse("Omarchy's o.workspaces is not loaded")
  end

  load_config(self, opts.config_dir)
  if self.cfg then
    workspace_rules(self.cfg, self.ruled)
  end

  local function on_start()
    self:guard("start check", function()
      self:check_omarchy()
      self:reselect()
      self:assign_all()
    end)
  end
  adapter.on("hyprland.start", on_start)
  adapter.on("config.reloaded", on_start)

  -- Hyprland reports monitor changes from inside them; re-select afterwards.
  local function on_monitors()
    adapter.defer(function()
      self:guard("arrangement selection", self.reselect, self)
    end)
  end
  adapter.on("monitor.added", on_monitors)
  adapter.on("monitor.removed", on_monitors)

  adapter.on("window.open", function(window)
    self:guard("window.open", router.window_opened, self, window)
    self:guard("change event", self.changed, self)
  end)
  adapter.on("window.destroy", function(window)
    self:guard("window.destroy", router.window_destroyed, self, window)
    self:guard("change event", self.changed, self)
  end)

  self:reselect()
  self:assign_all()
  self.started = true
end

-- Tell the editor something changed: hl.dsp.event("hyprslots changed <seq>"),
-- which reaches socket2 as custom>>hyprslots changed <seq>.
function Engine:changed()
  self.seq = self.seq + 1
  adapter.emit_event("hyprslots changed " .. self.seq)
end

-- Make Hyprland lay out every desk workspace of the active arrangement again
-- (one zero resize per workspace holding a tiled window).
function Engine:relayout()
  local nudged = {}
  for _, window in ipairs(adapter.windows()) do
    local id = window.workspace_id
    if id and self.workspaces[id] and not nudged[id] and not window.floating and window.address then
      nudged[id] = true
      adapter.nudge(window.address)
    end
  end
end

-- Run a newly loaded config: rules, arrangement, assignments, layout, event.
-- `data` is the slots.lua data it came from; `dirty` whether that differs
-- from the file.
function Engine:apply_config(cfg, data, dirty)
  self.cfg = cfg
  self.config_error = nil
  self.data = data
  self.dirty = dirty and true or false
  workspace_rules(cfg, self.ruled)
  self:reselect()
  self:assign_all()
  self:relayout()
  self:changed()
end

-- Re-read config.lua and slots.lua from disk, dropping unsaved edits. Returns
-- true, or nil and the error (the running config stays).
function Engine:reload()
  local cfg, err = config.load(self.config_dir)
  if not cfg then
    self.log:error("reload: %s", err)
    return nil, err
  end
  local file = cfg.data_files["slots.lua"]
  self:apply_config(cfg, file and file.data, false)
  self.log:info("config reloaded: %d arrangement(s)", #cfg.arrangement_names)
  return true
end

-- Set up hyprslots. opts.config_dir overrides $XDG_CONFIG_HOME/hyprslots.
function M.setup(opts)
  engine = new_engine()
  local self = engine
  local ok, err = pcall(start, self, opts or {})
  if not ok then
    self.log:error("setup failed: %s", tostring(err))
    pcall(adapter.notify, "hyprslots failed to start: " .. tostring(err), "error")
  end
  return ok
end

local function current()
  return engine
end

-- An action showing desk N, for hl.bind in place of o.workspaces.focus(N).
function M.desk(n)
  return desks.action(current, n)
end

M.api = {
  call = function(name, text)
    return api.call(engine, name, text)
  end,
  state = function()
    return api.state(engine)
  end,
}

function M.dump()
  return api.dump(engine)
end

-- Re-read the config files in place (no Hyprland config reload). Returns
-- true, or nil and the error.
function M.reload_config()
  if not engine then
    return nil, "hyprslots is not set up"
  end
  return engine:reload()
end

return M
