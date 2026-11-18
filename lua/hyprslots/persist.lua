-- Saving the editor's data (docs/design.md §9, save; §8, desk geometry):
-- slots.lua written from the running data, read back as it is on disk
-- (reset compares against it), and the active desk's geometry recorded in
-- it. The api's save and reset calls and the engine (a first run's new
-- desk, a monitor change) save through here.

local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local desk = require("hyprslots.desk")
local edit = require("hyprslots.edit")
local edits = require("hyprslots.edits")
local migrate = require("hyprslots.migrate")
local resize = require("hyprslots.resize")
local serialize = require("hyprslots.serialize")

local DATA_FILE = edits.DATA_FILE
local read_only_paths = edits.read_only_paths
local configured_tree = edits.configured_tree

local M = {}

local function fail(message)
  return { ok = false, error = message }
end

-- Write the running data to slots.lua (atomically), keyboard-resized trees
-- included where the layout is the editor's: { path, seq }, or
-- { ok = false, error } (the api's save call's reply).
function M.save(engine)
  if not engine.data then
    return fail("your config loads no editor data, so there is nothing to save")
  end
  local data = edit.copy(engine.data)
  local read_only = read_only_paths(engine.cfg)
  local written = {} -- override keys save makes part of the config
  for _, o in ipairs(resize.overrides(engine)) do
    local configured = engine.cfg.layouts[o.layout] and configured_tree(engine.cfg, o.layout, o.workspace, o.screen)
    if configured and not rawequal(configured, o.tree) and edit.editable(read_only, "layouts", o.layout) then
      local next_data = edit.set_tree(data, o.layout, o.workspace, o.screen, serialize.tree(o.tree))
      if next_data then
        data = next_data
        written[#written + 1] = { o.layout, o.workspace, o.screen }
      end
    end
  end
  local path = (engine.config_dir or config.dir()) .. "/" .. DATA_FILE
  local ok, err = serialize.write(path, data)
  if not ok then
    return fail(err)
  end
  engine.log:info("saved %s", path)
  engine.auto_desks = {} -- the desks made for new monitors are slots.lua's now
  engine.file_migrated = false
  -- The written overrides are config now: run the saved data, then drop them.
  local cfg = #written > 0 and config.load(engine.config_dir, { data = { [DATA_FILE] = data } })
  if cfg then
    for _, w in ipairs(written) do
      resize.clear(engine, w[1], w[2], w[3])
    end
    engine:apply_config(cfg, data, false)
  else
    engine.data = data
    engine.dirty = false
    engine.since_save = {}
    engine:changed()
  end
  return { path = path, seq = engine.seq }
end

-- slots.lua as it is on disk (data only, read in an empty environment, in
-- today's shape) and whether it is in a shape of before, or nil and why not.
function M.saved_data(engine)
  local path = (engine.config_dir or config.dir()) .. "/" .. DATA_FILE
  local chunk, err = loadfile(path, "t", {})
  if not chunk then
    return nil, "cannot read the editor's saved data: " .. tostring(err)
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    return nil, "cannot read the editor's saved data: " .. (ok and "it returns no table" or tostring(data))
  end
  local ok_monitors, monitors = pcall(adapter.monitors)
  return migrate.data(data, ok_monitors and monitors or nil) -- read as load_data reads it
end

-- The saved data through the renames and removals made since (slots,
-- layouts), so its trees name what the running data
-- names. An edit that does not apply to the file (it renames a slot added
-- since) is skipped.
function M.as_edited(engine, saved)
  local out = saved
  for _, e in ipairs(engine.since_save or {}) do
    out = edit[e.op](out, table.unpack(e.args, 1, e.args.n)) or out
  end
  return out
end

-- The data without the desks' recorded geometry (a copy): what an edit
-- compares, the geometry being no edit.
function M.without_geometry(data)
  local out = edit.copy(data)
  for _, entry in pairs(type(out.desks) == "table" and out.desks or {}) do
    if type(entry) == "table" then
      entry.geometry = nil
    end
  end
  return out
end

-- The active desk's geometry into slots.lua (docs/design.md §8): its
-- monitors' logical boxes (desk.geometry), when they differ from what the
-- data holds and the desk is the editor's. Not an edit: it never makes the
-- engine dirty. Saved at once while nothing else is unsaved (as a first
-- run's new desk is) and slots.lua on disk is still what runs, else it
-- waits in the data for the next save (never written over a file changed
-- since it was read: a hand edit, a reload that failed).
function M.record_geometry(engine)
  local active = engine.active
  if not (engine.cfg and engine.data and active) or engine.refused then
    return
  end
  local entry = type(engine.data.desks) == "table" and engine.data.desks[active.desk]
  if type(entry) ~= "table" or type(entry.monitors) ~= "table"
      or not edit.editable(read_only_paths(engine.cfg), "desks", active.desk) then
    return
  end
  local geometry = desk.geometry(entry.monitors, adapter.monitors())
  if not geometry or desk.same_geometry(geometry, entry.geometry) then
    return
  end
  local pending = engine.dirty or next(engine.resized or {}) ~= nil
  if not pending then
    local on_disk = M.saved_data(engine)
    pending = not on_disk
      or serialize.dump(M.without_geometry(on_disk)) ~= serialize.dump(M.without_geometry(engine.data))
  end
  entry.geometry = geometry -- the running data, which save writes
  local running = engine.cfg.desks[active.desk]
  if running then
    running.geometry = geometry
  end
  engine.log:info("desk %s: geometry recorded%s", active.desk, pending and " (saved with the next save)" or "")
  if pending then
    engine:changed()
    return
  end
  local saved = M.save(engine)
  if saved.ok == false then
    engine.log:error("desk %s: geometry not saved: %s", active.desk, tostring(saved.error))
  end
end

return M
