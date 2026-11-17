-- The edit pipeline (docs/design.md §9): how an edit of the editor's data
-- runs. Each edit builds new slots.lua data (edit.lua), re-runs config.lua
-- over it, checks the edit took effect (a field config.lua builds in code,
-- or does not take from slots.lua, would not), and only then runs it like
-- any edit: re-assign, re-route, window rules, relayout, change event.
-- Nothing is written until save (persist.lua). api.lua's calls and the
-- engine's own edits (a desk for new monitors) both run through here.

local config = require("hyprslots.config")
local edit = require("hyprslots.edit")
local resize = require("hyprslots.resize")
local util = require("hyprslots.util")

local M = {}

M.DATA_FILE = "slots.lua"
-- Messages reach the editor, so they name no files.
M.NO_DATA = "your config loads no editor data, so there is nothing the editor may change"

-- The data paths config.lua sets by code (edit.read_only), never nil.
function M.read_only_paths(cfg)
  if not cfg or not cfg.raw then
    return {}
  end
  local file = cfg.data_files and cfg.data_files[M.DATA_FILE]
  return edit.read_only(cfg.raw, file and file.given)
end

-- The configured tree of a layout's workspace (or "default") on a screen.
function M.configured_tree(cfg, name, n, screen)
  local layout = cfg.layouts[name]
  if n == "default" then
    return layout and layout.default[screen]
  end
  local trees = config.trees_for(layout, n)
  return trees and trees[screen]
end

-- Run config.lua over edited data; on success the engine runs it. Returns the
-- new config, or nil and why (the running config stays).
function M.apply_data(engine, data)
  local cfg, err = config.load(engine.config_dir, { data = { [M.DATA_FILE] = data } })
  if not cfg then
    return nil, err
  end
  engine:apply_config(cfg, data, true)
  return cfg
end

-- Re-run config.lua over edited data, applying nothing. `check(cfg)`
-- returns why the edit did not take, or nil. Returns cfg, or nil and why.
function M.load_checked(engine, data, check)
  local cfg, err = config.load(engine.config_dir, { data = { [M.DATA_FILE] = data } })
  if cfg and check then
    err = check(cfg)
    if err then
      return nil, err
    end
  end
  return cfg, err
end

-- Run edited data. `check(cfg)` returns why the edit did not take, or nil;
-- `carry(engine)` moves in-memory state along (keyboard-resized trees,
-- assignments) and is undone when the edit fails. Returns cfg, or nil and
-- why.
function M.apply(engine, data, check, carry)
  local saved = { resized = util.shallow(engine.resized), assignments = util.shallow(engine.assignments),
    overflow = util.shallow(engine.overflow) }
  if carry then
    carry(engine)
  end
  local cfg, err = M.load_checked(engine, data, check)
  if not cfg then
    engine.resized, engine.assignments, engine.overflow = saved.resized, saved.assignments, saved.overflow
    return nil, err
  end
  engine:apply_config(cfg, data, true)
  return cfg
end

-- Why an edit config.lua did not take is refused.
function M.not_taken(what)
  return "your config does not take " .. what .. " from the editor's data, so the edit would change nothing; "
    .. "change it in your config"
end

-- Remember an edit that renames or removes what slots.lua names (a slot, an
-- layout) until data is the file's again: reset reads
-- the saved trees through them. `op` is edit.lua's function and its
-- arguments after the data.
function M.remember(engine, op, ...)
  engine.since_save = engine.since_save or {}
  engine.since_save[#engine.since_save + 1] = { op = op, args = table.pack(...) }
end

-- Whether the global slots are the editor's to change.
function M.editable_slots(engine)
  if not engine.data then
    return nil, M.NO_DATA
  end
  if not edit.editable(M.read_only_paths(engine.cfg), "slots") then
    return nil, "the slots are set by code in your config; edit them there"
  end
  return true
end

-- The workspace of a spec edit, if its specs are the editor's.
function M.editable_specs(engine, workspace)
  if not engine.data then
    return nil, M.NO_DATA
  end
  if not edit.editable(M.read_only_paths(engine.cfg), "specs", workspace) then
    return nil, "workspace " .. tostring(workspace) .. "'s specs are set by code in your config; edit them there"
  end
  return workspace
end

-- Whether a section's entry (`what`, for the message) is the editor's to
-- change.
function M.section_editable(engine, section, name, what)
  if not engine.data then
    return nil, M.NO_DATA
  end
  if not edit.editable(M.read_only_paths(engine.cfg), section, name) then
    return nil, what .. " is set by code in your config; edit it there"
  end
  return true
end

-- Rewrite every keyboard-resized tree with keep(override) -> key, node (nil
-- drops it).
function M.carry_overrides(engine, keep)
  local out = {}
  for _, override in ipairs(resize.overrides(engine)) do
    local key, node = keep(override)
    if key then
      out[key] = node
    end
  end
  engine.resized = out
end

-- Carry every keyboard-resized tree through fn(node) -> node or nil.
function M.on_every_tree(fn)
  return function(engine)
    M.carry_overrides(engine, function(o)
      local node = fn(o.tree)
      return node and o.key, node
    end)
  end
end

-- Every assignment (and overflow match) of slot `old` now of slot `new`.
function M.rename_assignments(engine, old, new)
  for _, map in ipairs({ "assignments", "overflow" }) do
    local renamed = {}
    for address, a in pairs(engine[map] or {}) do
      if a.slot == old then
        local copy = util.shallow(a)
        copy.slot = new
        renamed[address] = copy
      else
        renamed[address] = a
      end
    end
    engine[map] = renamed
  end
end

-- The spec text a config gives a slot on a workspace, or nil.
function M.workspace_spec(cfg, workspace, slot)
  local entry = cfg.specs[workspace] and cfg.specs[workspace][slot]
  return entry and entry.text
end

-- A check that the config took desk `name` (and, with `want`, as wanted).
function M.took_desk(name, want)
  return function(c)
    local entry = c.desks[name]
    if not entry then
      return M.not_taken("desk '" .. name .. "'")
    end
    if want and not want(entry) then
      return M.not_taken("desk '" .. name .. "'")
    end
  end
end

-- A check that the config took layout `name`.
function M.took_layout(name)
  return function(c)
    if not c.layouts[name] then
      return M.not_taken("layout '" .. name .. "'")
    end
  end
end

-- A desk the engine makes for monitors no desk knows (init.lua's
-- Engine:new_desk): `name` for these selectors using `layout`, made too (for
-- `screens` screens, with these default trees) when `trees` is given. An
-- edit like any other, in memory until saved. Returns true, or nil and why
-- not (config.lua does not take desks or layouts from slots.lua).
function M.new_desk(engine, name, selectors, layout, screens, trees)
  if not engine.data then
    return nil, M.NO_DATA
  end
  local read_only = M.read_only_paths(engine.cfg)
  if not edit.editable(read_only, "desks", name) or (trees and not edit.editable(read_only, "layouts", layout)) then
    return nil, "your config sets the desks or layouts by code"
  end
  local data, err = engine.data, nil
  if trees then
    data, err = edit.add_layout(data, layout, screens, trees)
    if not data then
      return nil, err
    end
  end
  data, err = edit.add_desk(data, name, selectors, layout)
  if not data then
    return nil, err
  end
  local cfg, apply_err = M.apply(engine, data, M.took_desk(name))
  if not cfg then
    return nil, apply_err
  end
  return true
end

return M
