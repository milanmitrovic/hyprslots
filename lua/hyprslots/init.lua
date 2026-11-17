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
local edits = require("hyprslots.edits")
local assign = require("hyprslots.assign")
local blocks = require("hyprslots.blocks")
local config = require("hyprslots.config")
local desk = require("hyprslots.desk")
local workspaces = require("hyprslots.workspaces")
local hotplug = require("hyprslots.hotplug")
local layout = require("hyprslots.layout")
local log = require("hyprslots.log")
local monitor_name = require("hyprslots.monitor_name")
local persist = require("hyprslots.persist")
local resize = require("hyprslots.resize")
local router = require("hyprslots.router")
local scroll = require("hyprslots.scroll")
local spec = require("hyprslots.spec")
local starter = require("hyprslots.starter")
local tree = require("hyprslots.tree")
local window_rules = require("hyprslots.window_rules")

local M = {}

local LAYOUT = "slots"
local BLOCKS = 10 -- Omarchy monitor blocks given lua:slots workspaces
local WORKSPACES = workspaces.DEFAULT -- config `workspaces` when unset
local NEW_DESK_DELAY = 1000 -- ms a monitor set no desk knows must hold before it gets a desk

local engine = nil

local workspace_rules -- defined below, used by Engine:reselect

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
    workspaces = {}, -- workspace id -> { workspace, screen, monitor, branch }
    assignments = {}, -- window address -> { workspace, slot }
    overflow = {}, -- window address -> { workspace, slot }: matches that slot, which is taken
    unassigned = {}, -- window address -> true: taken out of its slot by hand, takes none
    seq = 0, -- bumped on every change the editor should see
    started = false,
    config_dir = nil,
    data = nil, -- the editor-owned slots.lua data the running config came from
    dirty = false, -- data differs from slots.lua on disk
    since_save = {}, -- renames and removals since data was slots.lua's (api.lua's reset reads through them)
    ruled = {}, -- workspace id -> the layout hyprslots gave it ("lua:slots" or "scrolling")
    scroll_seen = {}, -- workspace id -> set of windows whose columns scroll.lua has widened
    resized = {}, -- "<layout>/<workspace>/<screen>" -> keyboard-resized tree (resize.lua)
    auto_desks = {}, -- desk name -> true: made for monitors no desk knew, not saved yet
    recent_layouts = {}, -- layout names, the most recently used first
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

-- Re-pick the desk for the connected monitors and rebuild the map from
-- workspace id to workspace number and screen (desk.lua; screen i is the
-- i-th monitor from the left). Monitors no desk knows get one of their own
-- (Engine:new_desk) once they have held for a second: hotplug passes through
-- sets on its way.
function Engine:reselect()
  local previous = self.active and (self.active.desk .. "\0" .. self.active.layout)
  self.active = nil
  self.workspaces = {}
  if not self.cfg or self.refused then
    return
  end

  -- Workspace ids follow the desk (blocks.lua): renumber before the map
  -- below is built from them. Not while the config loads: Omarchy's
  -- reconcile on hyprland.start / config.reloaded runs it first.
  if self.started then
    self:guard("workspace blocks", blocks.sync_and_settle, self)
  end

  local monitors = adapter.monitors()
  self.active = desk.select(self.cfg, monitors)

  if self.active then
    self:used_layout(self.active.layout)
    self:want_geometry()
    for n = 1, self.cfg.workspaces or WORKSPACES do
      for screen, branch in pairs(config.trees_for(self.active.entry, n) or {}) do
        local monitor = self.active.monitors[screen]
        if monitor then
          local id = adapter.workspace_id(monitor, n)
          self.workspaces[id] = { workspace = n, screen = screen, monitor = monitor, branch = branch }
        end
      end
    end
  elseif #desk.usable(monitors) > 0 then
    self:want_desk()
  end

  if self.started and self.cfg then
    workspace_rules(self, true)
  end

  local now = self.active and (self.active.desk .. "\0" .. self.active.layout)
  if now ~= previous and self.started then
    self:changed()
  end
  if now ~= previous then
    local names = {}
    for _, monitor in ipairs(monitors) do
      names[#names + 1] = monitor.name
    end
    self.log:info("desk %s, layout %s (monitors: %s)", tostring(self.active and self.active.desk),
      tostring(self.active and self.active.layout), table.concat(names, ", "))
  end
end

-- Remember that a layout ran (most recent first): a new desk takes the
-- most recently used layout for as many screens.
function Engine:used_layout(name)
  local recent = { name }
  for _, other in ipairs(self.recent_layouts) do
    if other ~= name then
      recent[#recent + 1] = other
    end
  end
  self.recent_layouts = recent
end

-- Record the active desk's geometry in slots.lua (persist.record_geometry),
-- deferred: reselect runs inside edits and saves.
function Engine:want_geometry()
  if self.geometry_pending then
    return
  end
  self.geometry_pending = true
  adapter.defer(function()
    self.geometry_pending = false
    self:guard("desk geometry", persist.record_geometry, self)
  end)
end

function Engine:want_desk()
  if self.desk_pending then
    return
  end
  self.desk_pending = true
  adapter.defer(function()
    self.desk_pending = false
    self:guard("new desk", self.new_desk, self)
  end, NEW_DESK_DELAY)
end

-- The layout a new desk of `count` monitors uses: the most recently used
-- one for that many screens, else the first by name, else nil.
local function layout_for_new_desk(self, count)
  for _, name in ipairs(self.recent_layouts) do
    local layout = self.cfg.layouts[name]
    if layout and layout.screens == count then
      return name
    end
  end
  for _, name in ipairs(self.cfg.layout_names) do
    if self.cfg.layouts[name].screens == count then
      return name
    end
  end
  return nil
end

local function free_name(base, ...)
  local name, n = base, 1
  local function taken(candidate, sets)
    for _, set in ipairs(sets) do
      if set and set[candidate] ~= nil then
        return true
      end
    end
    return false
  end
  local sets = { ... }
  while taken(name, sets) do
    n = n + 1
    name = base .. "-" .. n
  end
  return name
end

-- A desk for the connected monitors, when no desk is them (§8): named
-- after them, using the most recently used layout for as many screens, or
-- a new default one named for what it arranges (desk.layout_name_for). It is an edit like the editor's, in memory until
-- saved (the editor and the bar show unsaved edits); while there are no
-- slots it is saved at once, unless other edits are unsaved. Where
-- config.lua does not take desks from slots.lua it lives in the running
-- config only.
function Engine:new_desk()
  if not self.cfg or self.refused or self.active then
    return
  end
  local monitors = desk.order(desk.usable(adapter.monitors()))
  if #monitors == 0 or desk.select(self.cfg, monitors) then
    return
  end
  local data_desks = self.data and type(self.data.desks) == "table" and self.data.desks or nil
  local data_layouts = self.data and type(self.data.layouts) == "table" and self.data.layouts or nil
  local name = free_name(desk.name_for(monitors, nil, self.cfg.monitor_names, monitor_name.system_makes()),
    self.cfg.desks, data_desks)
  local selectors = {}
  for i, monitor in ipairs(monitors) do
    selectors[i] = desk.selector(monitor)
  end
  local layout = layout_for_new_desk(self, #monitors)
  local trees
  if not layout then
    trees = desk.default_trees(monitors, self.cfg.slot_names)
    layout = free_name(desk.layout_name_for(#monitors, trees), self.cfg.layouts, data_layouts)
  end

  -- Edits not yet saved (or a slots.lua of before, or a keyboard resize):
  -- the new desk then waits for Ctrl+S with them, never saved over them.
  local pending = self.dirty or next(self.resized or {}) ~= nil
  local made = self.data and edits.new_desk(self, name, selectors, layout, #monitors, trees)
  if not made then
    -- config.lua builds the desks (or loads no slots.lua): this run only.
    if trees then
      local parsed = {}
      for screen, text in pairs(trees) do
        parsed[screen] = assert(tree.parse(text))
      end
      self.cfg.layouts[layout] = { name = layout, screens = #monitors, default = parsed, workspaces = {} }
      self.cfg.layout_names[#self.cfg.layout_names + 1] = layout
      table.sort(self.cfg.layout_names)
    end
    self.cfg.desks[name] = { name = name, monitors = selectors, layout = layout }
    self.cfg.desk_names[#self.cfg.desk_names + 1] = name
    table.sort(self.cfg.desk_names)
    self:apply_config(self.cfg, self.data, self.dirty)
  end
  self.auto_desks[name] = true
  self.log:info("new desk %s (%s), layout %s", name, table.concat(selectors, ", "), layout)
  if #self.cfg.slot_names == 0 then
    -- Before the first slot (a first run): nothing to say, and nothing
    -- to review, so the desk and its layout are saved straight away
    -- unless other edits wait for Ctrl+S.
    if made and not pending then
      local saved = persist.save(self)
      if saved.ok == false then
        self.log:error("new desk %s: not saved: %s", name, tostring(saved.error))
      end
    end
    return
  end
  adapter.notify(string.format("hyprslots: new monitor setup — using layout '%s'.%s", layout,
    made and " Open the editor to change it." or ""), "info")
end

-- Assign every live window (on load: nothing survives a reload), except
-- those taken out of their slot by hand.
function Engine:assign_all()
  if not self.cfg then
    return
  end
  local windows, open = {}, {}
  for _, window in ipairs(adapter.windows()) do
    if window.address then
      open[window.address] = true
    end
    if not self.unassigned[window.address] then
      windows[#windows + 1] = window
    end
  end
  for address in pairs(self.unassigned) do
    if not open[address] then
      self.unassigned[address] = nil
    end
  end
  self.assignments = assign.solve(self.cfg, windows, self.assignments)
  self.overflow = {}
  for _, window in ipairs(windows) do
    if window.address and not self.assignments[window.address] then
      self.overflow[window.address] = assign.first_match(self.cfg, window)
    end
  end
end

-- The slot of a plain window ({ address, class, stable_id }), claiming one
-- when it has none yet. Nil when it matches no free slot, or was taken out
-- of its slot by hand (the editor's unassign).
function Engine:assign(window)
  if not self.cfg or not window.address or self.unassigned[window.address] then
    return nil
  end
  local assignment = self.assignments[window.address] or self:launched_for(window)
    or assign.claim(self.cfg, self.assignments, window)
  if assignment and not self.assignments[window.address] then
    self.assignments[window.address] = assignment
  end
  return assignment
end

-- The slot an app was launched for (api launch_missing, at login) that this
-- window, opening, is: one still on its way, empty, whose spec matches it.
-- The claim is used up. Nil for none. The first by workspace, as a number
-- (5 before 10), then by slot name.
function Engine:launched_for(window)
  if not self.launching or next(self.launching) == nil then
    return nil
  end
  local waiting = {}
  for key in pairs(self.launching) do
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
  for _, a in pairs(self.assignments) do
    taken[a.workspace .. "/" .. a.slot] = true
  end
  for _, w in ipairs(waiting) do
    local entry = self.cfg.specs[w.workspace] and self.cfg.specs[w.workspace][w.slot]
    if entry and not taken[w.key] and spec.match(entry, window) then
      self.launching[w.key] = nil
      return { workspace = w.workspace, slot = w.slot }
    end
  end
  return nil
end

-- The slot of an HL.Window, for recalculate.
function Engine:slot_of(hl_window)
  local known = self.assignments[hl_window.address]
  if known then
    return known
  end
  return self:assign(adapter.window(hl_window))
end

-- { workspace, screen, monitor, branch } for a workspace id, or nil.
function Engine:entry_of_workspace(id)
  if self.refused or id == nil then
    return nil
  end
  return self.workspaces[id]
end

-- The workspace id an assignment lives on under the active desk, or nil.
function Engine:workspace_for(assignment)
  for id, entry in pairs(self.workspaces) do
    if entry.workspace == assignment.workspace then
      for _, slot in ipairs(tree.slots(entry.branch)) do
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
  local cfg, err, missing = config.load(dir, { monitors = adapter.monitors() })
  if missing then
    -- A fresh install: a starter config.lua and an empty slots.lua, then
    -- run on them with zero slots (the editor's Layout tab makes the first).
    local written, why = starter.ensure(dir or config.dir())
    if not written then
      self.config_error = why
      self.log:error("first run: %s", why)
      adapter.notify("hyprslots: " .. why, "error")
      return
    end
    self.log:info("first run: wrote a starter %s in %s", table.concat(written, " and "), dir or config.dir())
    cfg, err, missing = config.load(dir, { monitors = adapter.monitors() })
  end
  if cfg then
    self.cfg = cfg
    local file = cfg.data_files["slots.lua"]
    self.data = file and file.data
    -- slots.lua in a shape of before: what runs differs from the file
    -- until it is saved.
    self.dirty = cfg.migrated == true and self.data ~= nil
    self.file_migrated = self.dirty
    self.log:info("config loaded: %d desk(s), %d layout(s)%s", #cfg.desk_names, #cfg.layout_names,
      cfg.migrated and " (migrated from a shape of before; save to keep it)" or "")
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

-- A layout for workspace N in every monitor block, for every workspace
-- some layout has a tree for (its own or the default ones): "scrolling"
-- where the active desk's layout has a scroll branch (scroll.lua), lua:slots
-- everywhere else. Workspace rules apply when a workspace is created, so
-- they are set up front, and again when the desk or the trees change, for
-- the workspaces whose layout
-- changed. A workspace with a saved Omarchy mode is left as it is, so
-- Super+L's choice stands until Super+L brings slots back. At load (the
-- loader runs from Omarchy's workspace-layouts folder, after its saved mode
-- files) a floating mode still gets the rule: floating keeps the tiled layout
-- underneath, which is the slots one, as when the mode files loaded last.
-- Later (`runtime`) any saved mode is left alone.
workspace_rules = function(self, runtime)
  local cfg, ruled = self.cfg, self.ruled
  local with_trees = {}
  for _, name in ipairs(cfg.layout_names) do
    for n = 1, cfg.workspaces or WORKSPACES do
      if next(config.trees_for(cfg.layouts[name], n) or {}) ~= nil then
        with_trees[n] = true
      end
    end
  end
  local list = {}
  for n in pairs(with_trees) do
    list[#list + 1] = n
  end
  table.sort(list)
  for _, n in ipairs(list) do
    for block = 0, BLOCKS - 1 do
      local id = block * 10 + n
      local layout = scroll.layout_for(self, id)
      if ruled[id] ~= layout then
        ruled[id] = layout
        local saved = adapter.omarchy_saved_mode(id)
        if saved ~= nil and (runtime or saved ~= "floating") then
          self.log:info("workspace %d: kept its saved Omarchy mode (hyprslots would give it %s)", id, layout)
        else
          adapter.workspace_layout(id, layout)
        end
      end
    end
  end
end

local function start(self, opts)
  self.desktop_dirs = opts.desktop_dirs -- the applications folders (tests); else the XDG ones
  adapter.register_layout(LAYOUT, layout.provider(self))

  if adapter.omarchy_workspaces() == nil then
    self:refuse("Omarchy's o.workspaces is not loaded")
  end

  load_config(self, opts.config_dir)
  blocks.attach(self)
  if self.cfg then
    self:reselect()
    workspace_rules(self, false)
  end

  local function on_start()
    self:guard("start check", function()
      self:check_omarchy()
      self:reselect()
      self:assign_all()
      window_rules.sync(self)
    end)
  end
  adapter.on("hyprland.start", function()
    on_start()
    -- Apps launched at login: on Hyprland's start only, never on a reload.
    self:guard("launch at login", api.launch_at_login, self)
  end)
  adapter.on("config.reloaded", on_start)

  hotplug.attach(self)

  adapter.on("window.open", function(window)
    self:guard("window.open", router.window_opened, self, window)
    self:guard("change event", self.changed, self)
  end)
  -- Hyprland 0.56.2 hands window.destroy a window whose address is already
  -- gone, so slots are freed on window.close, which still has it; destroy is
  -- handled the same way for any build that does pass it.
  for _, event in ipairs({ "window.close", "window.destroy" }) do
    adapter.on(event, function(window)
      if window and window.address then
        self:guard(event, router.window_destroyed, self, window)
        self:guard("change event", self.changed, self)
      end
    end)
  end
  adapter.on("window.title", function(window)
    self:guard("window.title", router.window_title, self, window)
  end)

  self:reselect()
  self:assign_all()
  window_rules.sync(self)

  -- Scroll branches: column order and width run deferred, after the events
  -- above.
  scroll.attach(self)
  self.started = true
end

-- Tell the editor something changed: hl.dsp.event("hyprslots changed <seq>"),
-- which reaches socket2 as custom>>hyprslots changed <seq>.
function Engine:changed()
  self.seq = self.seq + 1
  adapter.emit_event("hyprslots changed " .. self.seq)
end

-- Make Hyprland lay out every workspace of the active desk again (one zero
-- resize per workspace holding a tiled window), except those on Hyprland's
-- scrolling layout: a zero resize is a relayout on lua:slots
-- (CLuaTiledAlgorithm discards the delta), but on the scrolling layout it
-- collapses the window's column to 1 px, which the scroll pass, having seen
-- that column, never widens again (a scroll workspace's first window, after
-- a replug or an edit). A scroll workspace is the scroll pass's to arrange
-- (scroll.lua).
function Engine:relayout()
  local nudged = {}
  for _, window in ipairs(adapter.windows()) do
    local id = window.workspace_id
    if id and self.workspaces[id] and not nudged[id] and not window.floating and window.address then
      nudged[id] = true
      if adapter.workspace_tiled_layout(id) ~= "scrolling" then
        adapter.nudge(window.address)
      end
    end
  end
end

-- Run a newly loaded config: workspace rules, desk, assignments,
-- window rules and re-routing (an edit may have put a slot on another
-- screen), layout, event. `data` is
-- the slots.lua data it came from; `dirty` whether that differs from the
-- file.
function Engine:apply_config(cfg, data, dirty)
  -- The data as config.lua was handed it: read as today's shape, every tree
  -- holding every slot (migrate.data), which is what save writes.
  local file = data and cfg.data_files and cfg.data_files["slots.lua"]
  if file then
    data = file.data
  end
  self.cfg = cfg
  self.config_error = nil
  self.data = data
  resize.conform(self)
  self.dirty = dirty and true or false
  if not self.dirty then
    self.since_save = {}
  end
  self:reselect()
  self:assign_all()
  window_rules.sync(self)
  router.reroute_all(self)
  self:relayout()
  self:changed()
end

-- Re-read config.lua and slots.lua from disk, dropping unsaved edits. Returns
-- true, or nil and the error (the running config stays).
function Engine:reload()
  local cfg, err = config.load(self.config_dir, { monitors = adapter.monitors() })
  if not cfg then
    self.log:error("reload: %s", err)
    return nil, err
  end
  local file = cfg.data_files["slots.lua"]
  resize.clear(self) -- keyboard-resized trees are unsaved edits too
  self.auto_desks = {} -- a desk made for these monitors is made again if they still need one
  self.since_save = {} -- the renames made before are dropped with the edits (a migrated file stays dirty)
  self.file_migrated = cfg.migrated == true and file ~= nil
  self:apply_config(cfg, file and file.data, self.file_migrated)
  self.log:info("config reloaded: %d desk(s), %d layout(s)", #cfg.desk_names, #cfg.layout_names)
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

-- An action showing workspace N on every screen, for hl.bind in place of
-- o.workspaces.focus(N).
function M.workspace(n)
  return workspaces.action(current, n)
end
M.desk = M.workspace -- deprecated alias

-- Bind SUPER + 1..0 to hyprslots.workspace(1..10) in place of Omarchy's
-- per-screen workspace keys. Call it from the config after setup().
function M.bind_workspace_keys()
  workspaces.bind_keys(current)
end
M.bind_desk_keys = M.bind_workspace_keys -- deprecated alias

-- Point Omarchy's keyboard resize binds at the slots layout on lua:slots
-- workspaces (Omarchy's resize elsewhere). Call after Omarchy's bindings load;
-- setup() leaves the binds alone.
function M.bind_resize_keys()
  resize.bind_keys()
end

-- The editor's keys (install-engine.sh --keys writes them into the loader,
-- each only where it was free): `editor` toggles the editor panel,
-- `capture` opens it on the focused workspace's capture.
local PANEL = "io.github.milanmitrovic.hyprslots"
local EDITOR_KEYS = {
  { name = "editor", description = "Hyprslots: open the editor",
    command = "omarchy-shell shell toggle " .. PANEL },
  { name = "capture", description = "Hyprslots: capture this workspace",
    command = "omarchy-shell shell summon " .. PANEL .. " '{\"capture\":true}'" },
}

function M.bind_editor_keys(keys)
  for _, key in ipairs(EDITOR_KEYS) do
    local combo = type(keys) == "table" and keys[key.name]
    if type(combo) == "string" and combo ~= "" then
      adapter.bind_command(combo, key.description, key.command)
    end
  end
end

-- One rebound resize key's action (what the keybindings menu replays).
function M.resize_key(dx, dy)
  return resize.key_action(dx, dy)
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
