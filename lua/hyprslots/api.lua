-- The engine's api for the editor and the e2e tests (docs/design.md §9):
--
--   hyprctl repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")'
--   hyprctl repl 'return hyprslots.api.state()'
--
-- Every reply is a JSON string: { "ok": true, ... } or { "ok": false, "error": "..." }.
-- Nothing here raises into Hyprland. Calls: state, desk, set_tree, set_ratio,
-- record, assign, unassign, save, reload; for the Slots view set_spec,
-- add_slot, remove_slot, rename_slot, describe_slot, take_spec; for the
-- Arrangements view add_arrangement, rename_arrangement, delete_arrangement,
-- set_screens, set_pinned, copy_trees (the contract is in docs/design.md
-- §9). Every change bumps `seq` and emits hl.dsp.event("hyprslots changed
-- <seq>").

local json = require("hyprslots.dkjson")
local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local desks = require("hyprslots.desks")
local edit = require("hyprslots.edit")
local groups = require("hyprslots.groups")
local ratio = require("hyprslots.ratio")
local record = require("hyprslots.record")
local resize = require("hyprslots.resize")
local router = require("hyprslots.router")
local serialize = require("hyprslots.serialize")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local DATA_FILE = "slots.lua"

local M = {}

local OBJECT = { __jsontype = "object" }
local ARRAY = { __jsontype = "array" }

local function object(t)
  return setmetatable(t or {}, OBJECT)
end

local function array(t)
  return setmetatable(t or {}, ARRAY)
end

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)
  return keys
end

-- The tree in force for an arrangement's desk on a screen role: a keyboard
-- resize's in-memory override (resize.lua), else the config's. The layout
-- places the same tree. state reports it, set_ratio starts from it, record
-- compares against it and save writes it.
function M.effective_branch(engine, arrangement, desk, role)
  return resize.effective_branch(engine, arrangement, desk, role)
end

local function read_only_paths(cfg)
  if not cfg or not cfg.raw then
    return {}
  end
  local file = cfg.data_files and cfg.data_files[DATA_FILE]
  return edit.read_only(cfg.raw, file and file.given)
end

-- { tree, ratio, slots, resized? } for one parsed branch.
local function branch_info(node, resized)
  return object({ tree = serialize.tree(node), ratio = ratio.format(node), slots = array(tree.slots(node)),
    resized = resized or nil })
end

-- "<arrangement>/<desk>/<role>" -> { arrangement, desk, role, tree, ratio }
-- for every unsaved keyboard-resized tree.
local function resized_info(engine)
  local out = object()
  for _, override in ipairs(resize.overrides(engine)) do
    out[override.key] = object({ arrangement = override.arrangement, desk = override.desk, role = override.role,
      tree = serialize.tree(override.tree), ratio = ratio.format(override.tree) })
  end
  return out
end

local function arrangements_info(engine, read_only)
  local out = object()
  local cfg = engine.cfg
  if not cfg then
    return out
  end
  for _, name in ipairs(cfg.arrangement_names) do
    local arrangement = cfg.arrangements[name]
    local deskmap = object()
    for _, desk in ipairs(sorted_keys(arrangement.desks)) do
      local branches = object()
      for _, role in ipairs(sorted_keys(arrangement.desks[desk])) do
        local configured = arrangement.desks[desk][role]
        local effective = M.effective_branch(engine, name, desk, role) or configured
        branches[role] = branch_info(effective, not rawequal(effective, configured))
      end
      deskmap[tostring(desk)] = branches
    end
    local screens = object()
    for role, selector in pairs(arrangement.screens) do
      screens[role] = selector
    end
    out[name] = object({
      screens = screens,
      roles = array(arrangement.roles),
      desks = deskmap,
      active = engine.active ~= nil and engine.active.name == name,
      read_only = not edit.editable(read_only, "arrangements", name),
    })
  end
  return out
end

-- desk -> slot -> spec text, as config.lua returned them.
local function slots_info(engine)
  local out = object()
  local raw = engine.cfg and engine.cfg.raw and engine.cfg.raw.slots
  if type(raw) ~= "table" then
    return out
  end
  for _, desk in ipairs(sorted_keys(raw)) do
    local entries = object()
    for name, spec_text in pairs(raw[desk]) do
      entries[name] = type(spec_text) == "string" and spec_text or tostring(spec_text)
    end
    out[tostring(desk)] = entries
  end
  return out
end

-- desk -> slot -> description, from the slots.lua data (the editor's notes;
-- config.lua need not pass them through).
local function descriptions_info(engine)
  local out = object()
  local raw = engine.data and engine.data.descriptions
  if type(raw) ~= "table" then
    return out
  end
  for _, desk in ipairs(sorted_keys(raw)) do
    if type(raw[desk]) == "table" then
      local entries = object()
      for name, text in pairs(raw[desk]) do
        entries[name] = tostring(text)
      end
      out[tostring(desk)] = entries
    end
  end
  return out
end

-- The connected monitors, by connector: what an arrangement's screens can
-- select them by.
local function monitors_info()
  local out = array()
  local ok, monitors = pcall(adapter.monitors)
  if not ok then
    return out
  end
  table.sort(monitors, function(a, b) return tostring(a.name) < tostring(b.name) end)
  for _, monitor in ipairs(monitors) do
    out[#out + 1] = object({ name = monitor.name, description = monitor.description or "",
      serial = monitor.serial or "", focused = monitor.focused == true })
  end
  return out
end

local function desks_list(engine)
  local seen = {}
  local cfg = engine.cfg
  if cfg then
    for desk in pairs(cfg.slots) do
      seen[desk] = true
    end
    for _, name in ipairs(cfg.arrangement_names) do
      for desk in pairs(cfg.arrangements[name].desks) do
        seen[desk] = true
      end
    end
  end
  return array(sorted_keys(seen))
end

-- The accordions of the desk workspaces and their live groups (groups.lua).
local function groups_info(engine)
  local out = array()
  local ok, described = pcall(groups.describe, engine)
  if not ok then
    engine.log:error("state: groups: %s", tostring(described))
    return out
  end
  for _, g in ipairs(described) do
    out[#out + 1] = object({ workspace = g.workspace, desk = g.desk, role = g.role, slots = array(g.slots),
      members = object(g.members), group = array(g.group), formed = g.formed })
  end
  return out
end

local function windows_info(engine)
  local out = array()
  local ok, windows = pcall(adapter.windows)
  if not ok then
    return out
  end
  table.sort(windows, function(a, b) return tostring(a.address) < tostring(b.address) end)
  for _, window in ipairs(windows) do
    local assignment = engine.assignments[window.address]
    local overflow = engine.overflow and engine.overflow[window.address]
    out[#out + 1] = object({
      address = window.address,
      class = window.class,
      title = window.title,
      workspace = window.workspace_id,
      floating = window.floating,
      box = window.box and object(window.box) or nil,
      desk = assignment and assignment.desk or nil,
      slot = assignment and assignment.slot or nil,
      overflow = overflow and object({ desk = overflow.desk, slot = overflow.slot }) or nil,
      unassigned = engine.unassigned[window.address] or nil,
    })
  end
  return out
end

local function reply(t)
  t.ok = t.ok ~= false
  return json.encode(object(t))
end

local function failure(message)
  return json.encode(object({ ok = false, error = message }))
end

-- The engine's state as a plain table.
function M.snapshot(engine)
  local screens, workspaces, assignments, overflow = object(), object(), object(), object()
  if engine.active then
    for role, monitor in pairs(engine.active.monitors) do
      screens[role] = monitor
    end
  end
  for id, desk in pairs(engine.workspaces) do
    workspaces[tostring(id)] = object({ desk = desk.desk, role = desk.role, monitor = desk.monitor })
  end
  for address, assignment in pairs(engine.assignments) do
    assignments[address] = object({ desk = assignment.desk, slot = assignment.slot,
      manual = assignment.manual or nil })
  end
  for address, match in pairs(engine.overflow or {}) do
    overflow[address] = object({ desk = match.desk, slot = match.slot })
  end
  local unassigned = array(sorted_keys(engine.unassigned))
  local read_only = read_only_paths(engine.cfg)
  local dir = engine.config_dir or config.dir()
  local pinned = array()
  for role in pairs(engine.cfg and engine.cfg.pinned or {}) do
    pinned[#pinned + 1] = role
  end
  table.sort(pinned)
  return {
    ok = true,
    seq = engine.seq,
    refused = engine.refused,
    config_error = engine.config_error,
    arrangement = engine.active and engine.active.name or nil,
    screens = screens,
    workspaces = workspaces,
    assignments = assignments,
    overflow = overflow,
    unassigned = unassigned,
    log_seq = engine.log.seq,
    arrangements = arrangements_info(engine, read_only),
    slots = slots_info(engine),
    descriptions = descriptions_info(engine),
    monitors = monitors_info(),
    desks = desks_list(engine),
    pinned = pinned,
    windows = windows_info(engine),
    dirty = engine.dirty == true or next(engine.resized or {}) ~= nil,
    resized = resized_info(engine),
    groups = groups_info(engine),
    config = object({
      dir = dir,
      data_file = dir .. "/" .. DATA_FILE,
      editable = engine.data ~= nil,
      read_only = array(read_only),
    }),
  }
end

local handlers = {}

function handlers.state(engine)
  return M.snapshot(engine)
end

local function fail(message)
  return { ok = false, error = message }
end

-- The arrangement a call means: args.arrangement, else the active one.
local function target_arrangement(engine, args)
  local name = args.arrangement
  if name == nil then
    if not engine.active then
      return nil, "no arrangement is active; name one with \"arrangement\""
    end
    name = engine.active.name
  end
  if type(name) ~= "string" or not (engine.cfg and engine.cfg.arrangements[name]) then
    return nil, "no arrangement '" .. tostring(name) .. "'"
  end
  if not edit.editable(read_only_paths(engine.cfg), "arrangements", name) then
    return nil, "arrangement '" .. name .. "' is set by code in config.lua; edit it there"
  end
  return name
end

local function as_desk(value)
  if type(value) == "number" and math.type(value) == "float" and value == math.floor(value) then
    return math.tointeger(value)
  end
  return value
end

-- Run config.lua over edited data; on success the engine runs it. Returns the
-- new config, or nil and why (the running config stays).
local function apply_data(engine, data)
  local cfg, err = config.load(engine.config_dir, { data = { [DATA_FILE] = data } })
  if not cfg then
    return nil, err
  end
  engine:apply_config(cfg, data, true)
  return cfg
end

local function set_tree(engine, name, desk, role, text)
  if not engine.data then
    return nil, "config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change"
  end
  local data, err = edit.set_tree(engine.data, name, desk, role, text)
  if not data then
    return nil, err
  end
  -- The new tree replaces a keyboard-resized one; it is kept if the edit fails.
  local nudged = engine.resized and engine.resized[resize.key(name, desk, role)]
  resize.clear(engine, name, desk, role)
  local cfg, apply_err = apply_data(engine, data)
  if not cfg then
    if nudged then
      engine.resized[resize.key(name, desk, role)] = nudged
    end
    return nil, apply_err
  end
  return cfg.arrangements[name].desks[desk][role]
end

-- set_tree { arrangement?, desk, role, tree }
function handlers.set_tree(engine, args)
  local name, err = target_arrangement(engine, args)
  if not name then
    return fail(err)
  end
  local desk = as_desk(args.desk)
  local node, set_err = set_tree(engine, name, desk, args.role, args.tree)
  if not node then
    return fail(set_err)
  end
  return { arrangement = name, desk = desk, role = args.role, tree = serialize.tree(node),
    ratio = ratio.format(node), seq = engine.seq }
end

-- set_ratio { arrangement?, desk, role, ratio }
function handlers.set_ratio(engine, args)
  local name, err = target_arrangement(engine, args)
  if not name then
    return fail(err)
  end
  local desk = as_desk(args.desk)
  local current = M.effective_branch(engine, name, desk, args.role)
  if not current then
    return fail(string.format("arrangement '%s' has no tree for desk %s on '%s'", name, tostring(desk), tostring(args.role)))
  end
  local applied, ratio_err = ratio.apply(current, args.ratio)
  if not applied then
    return fail(ratio_err)
  end
  local node, set_err = set_tree(engine, name, desk, args.role, serialize.tree(applied))
  if not node then
    return fail(set_err)
  end
  return { arrangement = name, desk = desk, role = args.role, tree = serialize.tree(node),
    ratio = ratio.format(node), seq = engine.seq }
end

local function leaves(node, out)
  out = out or {}
  if node.children == nil then
    out[#out + 1] = node
  else
    for _, child in ipairs(node.children) do
      leaves(child, out)
    end
  end
  return out
end

local function has_accordion(node)
  if node.children == nil then
    return false
  end
  if node.split ~= "h" and node.split ~= "v" then
    return true
  end
  for _, child in ipairs(node.children) do
    if has_accordion(child) then
      return true
    end
  end
  return false
end

-- record { workspace?, apply? }: the tree the windows on a workspace (default:
-- the focused one) show, for that desk and screen of the active arrangement.
-- It is applied when it places every slot of the current tree, or when
-- apply = true; apply = false only previews.
function handlers.record(engine, args)
  local id = as_desk(args.workspace) or adapter.active_workspace_id()
  local desk = engine:desk_of_workspace(id)
  if not desk then
    return fail("workspace " .. tostring(id) .. " is no desk of the active arrangement")
  end
  local name = engine.active.name
  local branch = M.effective_branch(engine, name, desk.desk, desk.role) or desk.branch
  if has_accordion(branch) then
    return fail("cannot record workspace " .. tostring(id) .. ": its tree holds an accordion, whose windows "
      .. "overlap (aerolayout cannot record one either); set its tree or ratio instead")
  end
  local in_branch = {}
  for _, leaf in ipairs(leaves(branch)) do
    if leaf.slot then
      in_branch[leaf.slot] = true
    end
  end
  local boxes = {}
  for _, window in ipairs(adapter.windows()) do
    local assignment = engine.assignments[window.address]
    if window.workspace_id == id and not window.floating and window.box and assignment
      and assignment.desk == desk.desk and in_branch[assignment.slot] then
      boxes[assignment.slot] = window.box
    end
  end
  local node, err = record.tree(boxes)
  if not node then
    return fail("cannot record workspace " .. tostring(id) .. ": " .. err)
  end
  local missing = array()
  for _, leaf in ipairs(leaves(branch)) do
    if leaf.slot == nil then
      missing[#missing + 1] = "*" -- the overflow leaf: a record has no windows for it
    elseif not boxes[leaf.slot] then
      missing[#missing + 1] = leaf.slot
    end
  end
  local apply = args.apply
  if apply == nil then
    apply = #missing == 0
  end
  local reply = { arrangement = name, desk = desk.desk, role = desk.role, workspace = id,
    tree = serialize.tree(node), ratio = ratio.format(node), missing = missing, applied = false }
  if apply then
    local editable, edit_err = target_arrangement(engine, { arrangement = name })
    if not editable then
      return fail(edit_err)
    end
    local set, set_err = set_tree(engine, name, desk.desk, desk.role, reply.tree)
    if not set then
      return fail(set_err)
    end
    reply.applied = true
  end
  reply.seq = engine.seq
  return reply
end

-- save {}: write the running data to slots.lua (atomically).
function handlers.save(engine)
  if not engine.data then
    return fail("config.lua loads no " .. DATA_FILE .. ", so there is nothing to save")
  end
  local data = edit.copy(engine.data)
  local read_only = read_only_paths(engine.cfg)
  local written = {} -- override keys save makes part of the config
  for _, name in ipairs(engine.cfg.arrangement_names) do
    local entry = engine.cfg.arrangements[name]
    local target = type(data.arrangements) == "table" and data.arrangements[name]
    if type(target) == "table" and edit.editable(read_only, "arrangements", name) then
      for desk, branches in pairs(entry.desks) do
        for role, node in pairs(branches) do
          local effective = M.effective_branch(engine, name, desk, role)
          if effective and not rawequal(effective, node) then
            target.desks = target.desks or {}
            target.desks[desk] = target.desks[desk] or {}
            target.desks[desk][role] = serialize.tree(effective)
            written[#written + 1] = { name, desk, role }
          end
        end
      end
    end
  end
  local path = (engine.config_dir or config.dir()) .. "/" .. DATA_FILE
  local ok, err = serialize.write(path, data)
  if not ok then
    return fail(err)
  end
  engine.log:info("saved %s", path)
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
    engine:changed()
  end
  return { path = path, seq = engine.seq }
end

-- reload {}: re-read config.lua and slots.lua, dropping unsaved edits.
function handlers.reload(engine)
  local ok, err = engine:reload()
  if not ok then
    return fail(err)
  end
  return { arrangement = engine.active and engine.active.name or nil, seq = engine.seq }
end

local function live_window(address)
  for _, window in ipairs(adapter.windows()) do
    if window.address == address then
      return window
    end
  end
  return nil
end

-- assign { address, desk, slot }: put a window into a slot by hand.
function handlers.assign(engine, args)
  if engine.refused then
    return fail("hyprslots is off: " .. engine.refused)
  end
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  local desk = as_desk(args.desk)
  local slots = engine.cfg and engine.cfg.slots[desk]
  if not (slots and type(args.slot) == "string" and slots[args.slot]) then
    return fail(string.format("desk %s has no slot '%s'", tostring(desk), tostring(args.slot)))
  end
  local assignment, displaced = router.assign(engine, window, desk, args.slot)
  return { address = window.address, desk = assignment.desk, slot = assignment.slot, displaced = displaced,
    seq = engine.seq }
end

-- unassign { address }: take a window out of its slot by hand.
function handlers.unassign(engine, args)
  if engine.refused then
    return fail("hyprslots is off: " .. engine.refused)
  end
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  local previous = router.unassign(engine, window.address)
  return { address = window.address, desk = previous and previous.desk or nil,
    slot = previous and previous.slot or nil, seq = engine.seq }
end

-- The Slots and Arrangements views' edits. Each builds new slots.lua data
-- (edit.lua), re-runs config.lua over it, checks the edit took effect (a
-- field config.lua builds in code, or does not take from slots.lua, would
-- not), and only then runs it like any edit: re-assign, re-route, window
-- rules, relayout, change event. Nothing is written until save.

local NO_DATA = "config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change"

local function shallow(t)
  local out = {}
  for key, value in pairs(t or {}) do
    out[key] = value
  end
  return out
end

-- Run edited data. `check(cfg)` returns why the edit did not take, or nil;
-- `carry(engine)` moves in-memory state along (keyboard-resized trees,
-- assignments) and is undone when the edit fails. Returns cfg, or nil and
-- why.
local function apply_edit(engine, data, check, carry)
  local saved = { resized = shallow(engine.resized), assignments = shallow(engine.assignments),
    overflow = shallow(engine.overflow) }
  if carry then
    carry(engine)
  end
  local cfg, err = config.load(engine.config_dir, { data = { [DATA_FILE] = data } })
  if cfg and check then
    err = check(cfg)
    if err then
      cfg = nil
    end
  end
  if not cfg then
    engine.resized, engine.assignments, engine.overflow = saved.resized, saved.assignments, saved.overflow
    return nil, err
  end
  engine:apply_config(cfg, data, true)
  return cfg
end

local function not_taken(what)
  return "config.lua does not take " .. what .. " from " .. DATA_FILE .. ", so the edit would change nothing; "
    .. "change it in config.lua"
end

-- The desk of a slot edit, if its slots are the editor's.
local function editable_desk(engine, args)
  if not engine.data then
    return nil, NO_DATA
  end
  local desk = as_desk(args.desk)
  if not edit.editable(read_only_paths(engine.cfg), "slots", desk) then
    return nil, "desk " .. tostring(desk) .. "'s slots are set by code in config.lua; edit them there"
  end
  return desk
end

-- Rewrite every keyboard-resized tree of a desk with fn(node) -> node or nil.
local function carry_overrides(engine, keep)
  local out = {}
  for _, override in ipairs(resize.overrides(engine)) do
    local key, node = keep(override)
    if key then
      out[key] = node
    end
  end
  engine.resized = out
end

local function on_desk_trees(desk, fn)
  return function(engine)
    carry_overrides(engine, function(o)
      if o.desk ~= desk then
        return o.key, o.tree
      end
      local node = fn(o.tree)
      return node and o.key, node
    end)
  end
end

local function rename_assignments(engine, desk, old, new)
  for _, map in ipairs({ "assignments", "overflow" }) do
    local renamed = {}
    for address, a in pairs(engine[map] or {}) do
      if a.desk == desk and a.slot == old then
        local copy = shallow(a)
        copy.slot = new
        renamed[address] = copy
      else
        renamed[address] = a
      end
    end
    engine[map] = renamed
  end
end

local function slot_spec(cfg, desk, slot)
  local entry = cfg.slots[desk] and cfg.slots[desk][slot]
  return entry and entry.text
end

-- set_spec { desk, slot, spec }
function handlers.set_spec(engine, args)
  local desk, err = editable_desk(engine, args)
  if not desk then
    return fail(err)
  end
  local data, edit_err = edit.set_spec(engine.data, desk, args.slot, args.spec)
  if not data then
    return fail(edit_err)
  end
  local text = data.slots[desk][args.slot]
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if slot_spec(c, desk, args.slot) ~= text then
      return not_taken("desk " .. desk .. "'s slots")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { desk = desk, slot = args.slot, spec = text, seq = engine.seq }
end

-- add_slot { desk, slot, spec, description? }
function handlers.add_slot(engine, args)
  local desk, err = editable_desk(engine, args)
  if not desk then
    return fail(err)
  end
  local data, edit_err = edit.add_slot(engine.data, desk, args.slot, args.spec, args.description)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if slot_spec(c, desk, args.slot) == nil then
      return not_taken("desk " .. desk .. "'s slots")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { desk = desk, slot = args.slot, spec = data.slots[desk][args.slot], seq = engine.seq }
end

-- remove_slot { desk, slot }: also out of every tree that places it.
function handlers.remove_slot(engine, args)
  local desk, err = editable_desk(engine, args)
  if not desk then
    return fail(err)
  end
  local data, edit_err = edit.remove_slot(engine.data, desk, args.slot)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if c.slots[desk] and c.slots[desk][args.slot] ~= nil then
      return not_taken("desk " .. desk .. "'s slots")
    end
  end, on_desk_trees(desk, function(node) return edit.remove_leaf(node, args.slot) end))
  if not cfg then
    return fail(apply_err)
  end
  return { desk = desk, slot = args.slot, seq = engine.seq }
end

local function count_changed_trees(before, after)
  local n = 0
  for name, entry in pairs(type(after.arrangements) == "table" and after.arrangements or {}) do
    local old = before.arrangements and before.arrangements[name]
    for desk, branches in pairs(type(entry.desks) == "table" and entry.desks or {}) do
      for role, text in pairs(branches) do
        local was = old and old.desks and old.desks[desk] and old.desks[desk][role]
        if was ~= nil and was ~= text then
          n = n + 1
        end
      end
    end
  end
  return n
end

-- rename_slot { desk, slot, to }: in every tree of every arrangement too.
function handlers.rename_slot(engine, args)
  local desk, err = editable_desk(engine, args)
  if not desk then
    return fail(err)
  end
  local old, new = args.slot, args.to
  local data, edit_err = edit.rename_slot(engine.data, desk, old, new)
  if not data then
    return fail(edit_err)
  end
  local trees = count_changed_trees(engine.data, data)
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if slot_spec(c, desk, new) == nil then
      return not_taken("desk " .. desk .. "'s slots")
    end
  end, function(e)
    on_desk_trees(desk, function(node) return edit.rename_leaf(node, old, new) end)(e)
    rename_assignments(e, desk, old, new)
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { desk = desk, slot = old, to = new, trees = trees, seq = engine.seq }
end

-- describe_slot { desk, slot, description }: "" removes it.
function handlers.describe_slot(engine, args)
  if not engine.data then
    return fail(NO_DATA)
  end
  local desk = as_desk(args.desk)
  local data, edit_err = edit.describe_slot(engine.data, desk, args.slot, args.description)
  if not data then
    return fail(edit_err)
  end
  engine.data = data
  engine.dirty = true
  engine:changed()
  return { desk = desk, slot = args.slot, description = args.description or "", seq = engine.seq }
end

-- take_spec { desk, slot, address }: the window's spec (spec.from_window)
-- written into the slot, as aerolayout's Assignment `a` did.
function handlers.take_spec(engine, args)
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  local text = spec.from_window(window, engine.cfg and engine.cfg.title_matching)
  if not text then
    return fail("window " .. tostring(args.address) .. " has no class to make a spec of")
  end
  local reply = handlers.set_spec(engine, { desk = args.desk, slot = args.slot, spec = text })
  if reply.ok == false then
    return reply
  end
  reply.address = window.address
  return reply
end

local function arrangements_editable(engine)
  if not engine.data then
    return nil, NO_DATA
  end
  local read_only = read_only_paths(engine.cfg)
  for _, path in ipairs(read_only) do
    if path == "arrangements" then
      return nil, "the arrangements are set by code in config.lua; edit them there"
    end
  end
  return true
end

local function active_name(engine)
  return engine.active and engine.active.name or nil
end

-- The arrangement a rename or delete means: it must be named.
local function named_arrangement(engine, args)
  if args.arrangement == nil then
    return nil, "name one with \"arrangement\""
  end
  local name, err = target_arrangement(engine, args)
  if not name then
    return nil, err
  end
  if not engine.data then
    return nil, NO_DATA
  end
  return name
end

local function on_arrangement_overrides(fn)
  return function(engine)
    carry_overrides(engine, function(o)
      return fn(o)
    end)
  end
end

local function copy_source(args)
  if args.from ~= nil then
    return args.from, true
  end
  if args.default == true then
    return nil, true
  end
  return nil, false
end

-- add_arrangement { name, screens, from? | default? , roles? }: a new
-- arrangement for these screens (role -> selector), empty, with another's
-- trees (`from`, roles mapped by `roles` or by name) or the default trees.
function handlers.add_arrangement(engine, args)
  local ok, err = arrangements_editable(engine)
  if not ok then
    return fail(err)
  end
  local name = args.name
  local data, edit_err = edit.add_arrangement(engine.data, name, args.screens)
  if not data then
    return fail(edit_err)
  end
  local from, copying = copy_source(args)
  if copying then
    data, edit_err = edit.copy_trees(data, name, from, args.roles)
    if not data then
      return fail(edit_err)
    end
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.arrangements[name] then
      return not_taken("the arrangements")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { arrangement = name, screens = object(shallow(data.arrangements[name].screens)), active = active_name(engine),
    seq = engine.seq }
end

-- rename_arrangement { arrangement, to }
function handlers.rename_arrangement(engine, args)
  local old, err = named_arrangement(engine, args)
  if not old then
    return fail(err)
  end
  local new = args.to
  local data, edit_err = edit.rename_arrangement(engine.data, old, new)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.arrangements[new] or (new ~= old and c.arrangements[old]) then
      return not_taken("arrangement '" .. old .. "'")
    end
  end, on_arrangement_overrides(function(o)
    if o.arrangement == old then
      return resize.key(new, o.desk, o.role), o.tree
    end
    return o.key, o.tree
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { arrangement = old, to = new, active = active_name(engine), seq = engine.seq }
end

-- delete_arrangement { arrangement }: the active one too (these screens then
-- run nothing).
function handlers.delete_arrangement(engine, args)
  local name, err = named_arrangement(engine, args)
  if not name then
    return fail(err)
  end
  local data, edit_err = edit.delete_arrangement(engine.data, name)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if c.arrangements[name] then
      return not_taken("arrangement '" .. name .. "'")
    end
  end, on_arrangement_overrides(function(o)
    if o.arrangement == name then
      return nil
    end
    return o.key, o.tree
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { arrangement = name, active = active_name(engine), seq = engine.seq }
end

-- set_screens { arrangement?, screens, renames? }: replace an arrangement's
-- screens (role -> selector); renames (old role -> new role) carry trees.
function handlers.set_screens(engine, args)
  local name, err = target_arrangement(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail(NO_DATA)
  end
  local renames = type(args.renames) == "table" and args.renames or {}
  local data, edit_err = edit.set_screens(engine.data, name, args.screens, renames)
  if not data then
    return fail(edit_err)
  end
  local screens = data.arrangements[name].screens
  local cfg, apply_err = apply_edit(engine, data, function(c)
    local entry = c.arrangements[name]
    for role, selector in pairs(screens) do
      if not entry or entry.screens[role] ~= selector then
        return not_taken("arrangement '" .. name .. "'")
      end
    end
  end, on_arrangement_overrides(function(o)
    if o.arrangement ~= name then
      return o.key, o.tree
    end
    local role = renames[o.role]
    if role == nil and screens[o.role] ~= nil then
      role = o.role
    end
    return role and resize.key(name, o.desk, role), o.tree
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { arrangement = name, screens = object(shallow(screens)), active = active_name(engine), seq = engine.seq }
end

-- set_pinned { pinned[] }: the screen roles excluded from desk switching.
function handlers.set_pinned(engine, args)
  if not engine.data then
    return fail(NO_DATA)
  end
  for _, path in ipairs(read_only_paths(engine.cfg)) do
    if path == "pinned" then
      return fail("pinned is set by code in config.lua; edit it there")
    end
  end
  local data, edit_err = edit.set_pinned(engine.data, args.pinned)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    local want = {}
    for _, role in ipairs(data.pinned) do
      want[role] = true
      if not c.pinned[role] then
        return not_taken("pinned")
      end
    end
    for role in pairs(c.pinned) do
      if not want[role] then
        return not_taken("pinned")
      end
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { pinned = array(data.pinned), seq = engine.seq }
end

-- copy_trees { arrangement?, from? | default?, roles? }: replace an
-- arrangement's trees with another's (roles mapped by `roles`, else by
-- name), or with the default trees (each desk's slots side by side on the
-- first screen role).
function handlers.copy_trees(engine, args)
  local name, err = target_arrangement(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail(NO_DATA)
  end
  local from, copying = copy_source(args)
  if not copying then
    return fail("copy_trees needs \"from\" (an arrangement) or \"default\": true")
  end
  local data, edit_err = edit.copy_trees(engine.data, name, from, args.roles)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, nil, on_arrangement_overrides(function(o)
    if o.arrangement == name then
      return nil
    end
    return o.key, o.tree
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { arrangement = name, from = from, seq = engine.seq }
end

function handlers.desk(engine, args)
  local ok, err = desks.activate(engine, args.desk)
  if not ok then
    return { ok = false, error = err }
  end
  return { desk = args.desk }
end

-- call(engine, name, json) -> JSON reply string.
function M.call(engine, name, text)
  if not engine then
    return failure("hyprslots is not set up (hyprslots.setup() has not run)")
  end

  local args = {}
  if text ~= nil and text ~= "" then
    local decoded, _, err = json.decode(text)
    if err or type(decoded) ~= "table" then
      return failure("arguments must be a JSON object: " .. tostring(err or text))
    end
    args = decoded
  end

  local handler = handlers[name]
  if not handler then
    return failure("unknown call '" .. tostring(name) .. "'")
  end

  local ok, result = pcall(handler, engine, args)
  if not ok then
    engine.log:error("api %s failed: %s", tostring(name), tostring(result))
    return failure(tostring(result))
  end
  return reply(result)
end

function M.state(engine)
  return M.call(engine, "state")
end

-- Human-readable state and log, for hyprctl repl 'return hyprslots.dump()'.
function M.dump(engine)
  if not engine then
    return "hyprslots is not set up"
  end
  local lines = { "hyprslots state:", json.encode(object(M.snapshot(engine)), { indent = true }), "log:" }
  for _, line in ipairs(engine.log:lines()) do
    lines[#lines + 1] = "  " .. line
  end
  return table.concat(lines, "\n")
end

return M
