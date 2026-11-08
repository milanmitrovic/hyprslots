-- The engine's api for the editor and the e2e tests (docs/design.md §9):
--
--   hyprctl repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")'
--   hyprctl repl 'return hyprslots.api.state()'
--
-- Every reply is a JSON string: { "ok": true, ... } or { "ok": false, "error": "..." }.
-- Nothing here raises into Hyprland. Calls: state, workspace, set_tree, set_ratio,
-- record, assign, unassign, save, reload, arrange; for the slot list (the
-- Layout tab's global slots) add_slot, remove_slot, rename_slot, describe_slot; for the
-- Assignment view (each workspace's specs) take_spec, set_spec, clear_spec; for
-- the Layout view's shared trees fold_trees, drop_override; for
-- the Desk view add_desk, rename_desk, delete_desk, apply_layout,
-- set_pinned, add_layout, fork_layout, rename_layout, delete_layout (the
-- contract is in docs/design.md §9). Every change bumps `seq` and emits hl.dsp.event("hyprslots changed
-- <seq>").

local json = require("hyprslots.dkjson")
local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local desk = require("hyprslots.desk")
local workspaces = require("hyprslots.workspaces")
local workspace_count = workspaces.count -- snapshot shadows `workspaces`
local edit = require("hyprslots.edit")
local migrate = require("hyprslots.migrate")
local ratio = require("hyprslots.ratio")
local record = require("hyprslots.record")
local resize = require("hyprslots.resize")
local router = require("hyprslots.router")
local scroll = require("hyprslots.scroll")
local serialize = require("hyprslots.serialize")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local DATA_FILE = "slots.lua"
local WORKSPACES = 10

local M = {}

local OBJECT = { __jsontype = "object" }
local ARRAY = { __jsontype = "array" }

local function object(t)
  return setmetatable(t or {}, OBJECT)
end

local function array(t)
  return setmetatable(t or {}, ARRAY)
end

local function shallow(t)
  local out = {}
  for key, value in pairs(t or {}) do
    out[key] = value
  end
  return out
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

-- The tree in force for a layout's workspace on a screen: a keyboard
-- resize's in-memory override (resize.lua), else the config's. The layout
-- places the same tree. state reports it, set_ratio starts from it, record
-- compares against it and save writes it.
function M.effective_branch(engine, layout, workspace, screen)
  return resize.effective_branch(engine, layout, workspace, screen)
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

-- "<layout>/<workspace>/<screen>" -> { layout, workspace, screen, tree,
-- ratio } for every unsaved keyboard-resized tree.
local function resized_info(engine)
  local out = object()
  for _, override in ipairs(resize.overrides(engine)) do
    out[override.key] = object({ layout = override.layout, workspace = override.workspace,
      screen = override.screen, tree = serialize.tree(override.tree), ratio = ratio.format(override.tree) })
  end
  return out
end

-- { tree, ratio, slots, resized? } per screen ("1", "2"...) of one
-- workspace's trees (or the default ones) of a layout.
local function trees_info(engine, name, n, trees)
  local out = object()
  for _, screen in ipairs(sorted_keys(trees or {})) do
    local configured = trees[screen]
    local effective = n ~= "default" and M.effective_branch(engine, name, n, screen) or configured
    out[tostring(screen)] = branch_info(effective, not rawequal(effective, configured))
  end
  return out
end

-- name -> { screens, default ("1" -> branch), workspaces ("3" -> "1" ->
-- branch: the trees each workspace shows, its own or the default ones),
-- own[] (the workspaces with trees of their own), used_by[] (desks),
-- active, read_only }.
local function layouts_info(engine, read_only)
  local out = object()
  local cfg = engine.cfg
  if not cfg then
    return out
  end
  local users = {}
  for _, desk_name in ipairs(cfg.desk_names) do
    local layout = cfg.desks[desk_name].layout
    users[layout] = users[layout] or array()
    users[layout][#users[layout] + 1] = desk_name
  end
  for _, name in ipairs(cfg.layout_names) do
    local layout = cfg.layouts[name]
    local workspaces = object()
    for n = 1, cfg.workspaces or WORKSPACES do
      local trees = config.trees_for(layout, n)
      if trees then
        workspaces[tostring(n)] = trees_info(engine, name, n, trees)
      end
    end
    out[name] = object({
      screens = layout.screens,
      default = trees_info(engine, name, "default", layout.default),
      workspaces = workspaces,
      own = array(sorted_keys(layout.workspaces)),
      used_by = users[name] or array(),
      active = engine.active ~= nil and engine.active.layout == name,
      read_only = not edit.editable(read_only, "layouts", name),
    })
  end
  return out
end

-- name -> { monitors[] (selectors), connected[] (whether each is),
-- layout, pinned[], active, screens[] (the active desk's connectors, left
-- to right), auto (made for these monitors, not saved yet), read_only }.
local function desks_info(engine, read_only, monitors)
  local out = object()
  local cfg = engine.cfg
  if not cfg then
    return out
  end
  for _, name in ipairs(cfg.desk_names) do
    local entry = cfg.desks[name]
    local connected = array()
    for i, selector in ipairs(entry.monitors) do
      connected[i] = desk.find(selector, monitors) ~= nil
    end
    local active = engine.active ~= nil and engine.active.desk == name
    out[name] = object({
      monitors = array(shallow(entry.monitors)),
      connected = connected,
      layout = entry.layout,
      pinned = array(shallow(entry.pinned_list)),
      active = active,
      screens = active and array(shallow(engine.active.monitors)) or nil,
      auto = engine.auto_desks[name] or nil,
      read_only = not edit.editable(read_only, "desks", name),
    })
  end
  return out
end

-- The global slots, by name: [{ name, description? }].
local function slots_info(engine)
  local out = array()
  local cfg = engine.cfg
  for _, name in ipairs(cfg and cfg.slot_names or {}) do
    out[#out + 1] = object({ name = name, description = cfg.slots[name].description })
  end
  return out
end

-- workspace -> slot -> spec text: which app fills which slot on each workspace.
local function specs_info(engine)
  local out = object()
  local specs = engine.cfg and engine.cfg.specs or {}
  for _, workspace in ipairs(sorted_keys(specs)) do
    local entries = object()
    for name, parsed in pairs(specs[workspace]) do
      entries[name] = parsed.text
    end
    out[tostring(workspace)] = entries
  end
  return out
end

-- The connected monitors, by connector: what a desk's monitors can be
-- selected by, and where they are.
local function monitors_info(monitors)
  local out = array()
  local sorted = {}
  for i, monitor in ipairs(monitors) do
    sorted[i] = monitor
  end
  table.sort(sorted, function(a, b) return tostring(a.name) < tostring(b.name) end)
  for _, monitor in ipairs(sorted) do
    out[#out + 1] = object({ name = monitor.name, description = monitor.description or "",
      serial = monitor.serial or "", focused = monitor.focused == true, x = monitor.x, y = monitor.y,
      width = monitor.width, height = monitor.height, internal = desk.internal(monitor),
      selector = desk.selector(monitor) })
  end
  return out
end

-- The workspaces with specs or trees (in any layout, the default ones
-- counting for every workspace).
local function used_workspaces(engine)
  local seen = {}
  local cfg = engine.cfg
  if cfg then
    for workspace in pairs(cfg.specs) do
      seen[workspace] = true
    end
    for _, name in ipairs(cfg.layout_names) do
      for n = 1, cfg.workspaces or WORKSPACES do
        if next(config.trees_for(cfg.layouts[name], n) or {}) ~= nil then
          seen[n] = true
        end
      end
    end
  end
  return array(sorted_keys(seen))
end

-- The scroll branches of the active desk's workspaces and their
-- columns (scroll.lua).
local function scroll_info(engine)
  local out = array()
  local ok, described = pcall(scroll.describe, engine)
  if not ok then
    engine.log:error("state: scroll: %s", tostring(described))
    return out
  end
  for _, s in ipairs(described) do
    out[#out + 1] = object({ workspace_id = s.workspace_id, workspace = s.workspace, screen = s.screen,
      slots = array(s.slots),
      layout = s.layout, managed = s.managed, columns = array(s.columns), members = object(s.members),
      in_order = s.in_order })
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
      workspace_id = window.workspace_id,
      floating = window.floating,
      box = window.box and object(window.box) or nil,
      workspace = assignment and assignment.workspace or nil,
      slot = assignment and assignment.slot or nil,
      overflow = overflow and object({ workspace = overflow.workspace, slot = overflow.slot }) or nil,
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
  local screens, workspaces, assignments, overflow = array(), object(), object(), object()
  if engine.active then
    for i, monitor in ipairs(engine.active.monitors) do
      screens[i] = monitor
    end
  end
  for id, entry in pairs(engine.workspaces) do
    workspaces[tostring(id)] = object({ workspace = entry.workspace, screen = entry.screen, monitor = entry.monitor,
      layout = scroll.layout_for(engine, id) })
  end
  for address, assignment in pairs(engine.assignments) do
    assignments[address] = object({ workspace = assignment.workspace, slot = assignment.slot,
      manual = assignment.manual or nil })
  end
  for address, match in pairs(engine.overflow or {}) do
    overflow[address] = object({ workspace = match.workspace, slot = match.slot })
  end
  local unassigned = array(sorted_keys(engine.unassigned))
  local read_only = read_only_paths(engine.cfg)
  local dir = engine.config_dir or config.dir()
  local pinned = array()
  for screen in pairs(engine.active and engine.active.pinned or {}) do
    pinned[#pinned + 1] = screen
  end
  table.sort(pinned)
  local ok, monitors = pcall(adapter.monitors)
  monitors = ok and desk.usable(monitors) or {}
  return {
    ok = true,
    seq = engine.seq,
    workspace_count = workspace_count(engine),
    refused = engine.refused,
    config_error = engine.config_error,
    desk = engine.active and engine.active.desk or nil,
    layout = engine.active and engine.active.layout or nil,
    screens = screens,
    workspaces = workspaces,
    assignments = assignments,
    overflow = overflow,
    unassigned = unassigned,
    log_seq = engine.log.seq,
    desks = desks_info(engine, read_only, monitors),
    layouts = layouts_info(engine, read_only),
    slots = slots_info(engine),
    specs = specs_info(engine),
    monitors = monitors_info(monitors),
    used_workspaces = used_workspaces(engine),
    pinned = pinned,
    windows = windows_info(engine),
    dirty = engine.dirty == true or next(engine.resized or {}) ~= nil,
    resized = resized_info(engine),
    scroll = scroll_info(engine),
    config = object({
      dir = dir,
      data_file = dir .. "/" .. DATA_FILE,
      editable = engine.data ~= nil,
      read_only = array(read_only),
      migrated = engine.file_migrated or nil, -- slots.lua is in a shape of before until saved
    }),
  }
end

local handlers = {}
local record_scroll -- defined below handlers.record
function handlers.state(engine)
  return M.snapshot(engine)
end

local function fail(message)
  return { ok = false, error = message }
end

-- The layout a call means: args.layout, else the active desk's; it must be
-- the editor's to change.
local function target_layout(engine, args)
  local name = args.layout
  if name == nil then
    if not engine.active then
      return nil, "no desk is active; name a layout with \"layout\""
    end
    name = engine.active.layout
  end
  if type(name) ~= "string" or not (engine.cfg and engine.cfg.layouts[name]) then
    return nil, "no layout '" .. tostring(name) .. "'"
  end
  if not edit.editable(read_only_paths(engine.cfg), "layouts", name) then
    return nil, "layout '" .. name .. "' is set by code in config.lua; edit it there"
  end
  return name
end

local function as_integer(value)
  if type(value) == "number" and math.type(value) == "float" and value == math.floor(value) then
    return math.tointeger(value)
  end
  return value
end

-- A workspace number, or "default" (a layout's default trees).
local function as_workspace(value)
  if value == "default" then
    return value
  end
  return as_integer(value)
end

-- A screen number (JSON object keys arrive as text).
local function as_screen(value)
  if type(value) == "string" and value:match("^%d+$") then
    return math.tointeger(tonumber(value))
  end
  return as_integer(value)
end

-- The configured tree of a layout's workspace (or "default") on a screen.
local function configured_tree(cfg, name, n, screen)
  local layout = cfg.layouts[name]
  if n == "default" then
    return layout and layout.default[screen]
  end
  local trees = config.trees_for(layout, n)
  return trees and trees[screen]
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

local function set_tree(engine, name, n, screen, text)
  if not engine.data then
    return nil, "config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change"
  end
  local data, err = edit.set_tree(engine.data, name, n, screen, text)
  if not data then
    return nil, err
  end
  -- The new tree replaces a keyboard-resized one; it is kept if the edit fails.
  local key = resize.key(name, n, screen)
  local nudged = engine.resized and engine.resized[key]
  resize.clear(engine, name, n, screen)
  local cfg, apply_err = apply_data(engine, data)
  if not cfg then
    if nudged then
      engine.resized[key] = nudged
    end
    return nil, apply_err
  end
  return configured_tree(cfg, name, n, screen)
end

-- set_tree { layout?, workspace (or "default"), screen, tree }
function handlers.set_tree(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  local n, screen = as_workspace(args.workspace), as_screen(args.screen)
  local node, set_err = set_tree(engine, name, n, screen, args.tree)
  if not node then
    return fail(set_err)
  end
  return { layout = name, workspace = n, screen = screen, tree = serialize.tree(node),
    ratio = ratio.format(node), seq = engine.seq }
end

-- set_ratio { layout?, workspace (or "default"), screen, ratio }
function handlers.set_ratio(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  local n, screen = as_workspace(args.workspace), as_screen(args.screen)
  local current
  if n == "default" then
    current = configured_tree(engine.cfg, name, n, screen)
  else
    current = M.effective_branch(engine, name, n, screen)
  end
  if not current then
    return fail(string.format("layout '%s' has no tree for workspace %s on screen %s", name, tostring(n),
      tostring(screen)))
  end
  local applied, ratio_err = ratio.apply(current, args.ratio)
  if not applied then
    return fail(ratio_err)
  end
  local node, set_err = set_tree(engine, name, n, screen, serialize.tree(applied))
  if not node then
    return fail(set_err)
  end
  return { layout = name, workspace = n, screen = screen, tree = serialize.tree(node),
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

-- Apply a recorded tree when asked, or when it places every slot of the
-- current tree; fills in reply.applied. Returns the reply, or a failure.
local function apply_record(engine, args, reply)
  local apply = args.apply
  if apply == nil then
    apply = #reply.missing == 0
  end
  if apply then
    local editable, edit_err = target_layout(engine, { layout = reply.layout })
    if not editable then
      return fail(edit_err)
    end
    local set, set_err = set_tree(engine, reply.layout, reply.workspace, reply.screen, reply.tree)
    if not set then
      return fail(set_err)
    end
    reply.applied = true
  end
  reply.seq = engine.seq
  return reply
end

-- A scroll branch records as its slots in the column order they show; one
-- that places the overflow leaf records it where the first window with no
-- slot in the branch shows.
record_scroll = function(engine, args, id, entry, name, branch)
  local in_branch = {}
  for _, slot in ipairs(tree.scroll(branch)) do
    in_branch[slot] = true
  end
  local wants_overflow = tree.has_overflow(branch)
  local present, seen, slotted = {}, {}, 0
  for _, window in ipairs(scroll.order(adapter.scroll_windows(id))) do
    local assignment = engine.assignments[window.address]
    if assignment and assignment.workspace == entry.workspace and in_branch[assignment.slot] then
      if not seen[assignment.slot] then
        seen[assignment.slot] = true
        present[#present + 1] = assignment.slot
        slotted = slotted + 1
      end
    elseif wants_overflow and not seen[tree.OVERFLOW] then
      seen[tree.OVERFLOW] = true
      present[#present + 1] = tree.OVERFLOW
    end
  end
  if slotted == 0 then
    return fail("cannot record workspace " .. tostring(id) .. ": no windows to record")
  end
  local missing = array()
  for _, slot in ipairs(tree.columns(branch)) do
    if not seen[slot] then
      missing[#missing + 1] = slot
    end
  end
  local node = { scroll = true, weight = 1, children = {} }
  for i, slot in ipairs(present) do
    node.children[i] = slot == tree.OVERFLOW and { overflow = true, weight = 1 } or { slot = slot, weight = 1 }
  end
  return apply_record(engine, args, { layout = name, workspace = entry.workspace, screen = entry.screen,
    workspace_id = id, tree = serialize.tree(node), ratio = ratio.format(node), missing = missing, applied = false })
end

-- record { workspace_id?, apply? }: the tree the windows on a Hyprland
-- workspace (default: the focused one) show, for that workspace number and
-- screen of the active desk's layout. It is applied when it places every slot
-- of the current tree, or when apply = true; apply = false only previews.
function handlers.record(engine, args)
  local id = as_integer(args.workspace_id) or adapter.active_workspace_id()
  local entry = engine:entry_of_workspace(id)
  if not entry then
    return fail("workspace " .. tostring(id) .. " has no tree in the active desk's layout")
  end
  local name = engine.active.layout
  local branch = M.effective_branch(engine, name, entry.workspace, entry.screen) or entry.branch
  if tree.scroll(branch) then
    return record_scroll(engine, args, id, entry, name, branch)
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
      and assignment.workspace == entry.workspace and in_branch[assignment.slot] then
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
  return apply_record(engine, args, { layout = name, workspace = entry.workspace, screen = entry.screen,
    workspace_id = id, tree = serialize.tree(node), ratio = ratio.format(node), missing = missing, applied = false })
end

-- save {}: write the running data to slots.lua (atomically).
function handlers.save(engine)
  if not engine.data then
    return fail("config.lua loads no " .. DATA_FILE .. ", so there is nothing to save")
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

-- reload {}: re-read config.lua and slots.lua, dropping unsaved edits.
function handlers.reload(engine)
  local ok, err = engine:reload()
  if not ok then
    return fail(err)
  end
  return { desk = engine.active and engine.active.desk or nil, layout = engine.active and engine.active.layout or nil,
    seq = engine.seq }
end

local function live_window(address)
  for _, window in ipairs(adapter.windows()) do
    if window.address == address then
      return window
    end
  end
  return nil
end

-- assign { address, workspace, slot }: put a window into a slot by hand.
function handlers.assign(engine, args)
  if engine.refused then
    return fail("hyprslots is off: " .. engine.refused)
  end
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  local workspace = as_integer(args.workspace)
  local count = workspaces.count(engine)
  if not workspaces.valid(workspace, count) then
    return fail("a workspace must be an integer from 1 to " .. count .. ", got " .. tostring(args.workspace))
  end
  if not (engine.cfg and type(args.slot) == "string" and engine.cfg.slots[args.slot]) then
    return fail(string.format("no slot '%s' (add it in the editor's Layout tab, s then a)", tostring(args.slot)))
  end
  local assignment, displaced = router.assign(engine, window, workspace, args.slot)
  return { address = window.address, workspace = assignment.workspace, slot = assignment.slot, displaced = displaced,
    seq = engine.seq }
end

-- unassign { address, clear_spec? }: the window out of its slot (it takes
-- none until assigned again or closed); with clear_spec, the workspace's spec for
-- that slot too (reply `spec`, the one cleared).
function handlers.unassign(engine, args)
  if engine.refused then
    return fail("hyprslots is off: " .. engine.refused)
  end
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  -- clear_spec (the Assignment view's u): the workspace's spec for the slot the
  -- window holds goes too, first, so the slot is left empty rather than
  -- given to another window that spec matches. A refused clear changes
  -- nothing.
  local held = engine.assignments[window.address]
  local cleared
  if args.clear_spec == true and held then
    local specs = engine.cfg and engine.cfg.specs[held.workspace]
    if specs and specs[held.slot] then
      local reply = handlers.clear_spec(engine, { workspace = held.workspace, slot = held.slot })
      if reply.ok == false then
        return reply
      end
      cleared = reply.spec
    end
  end
  local previous = router.unassign(engine, window.address) or held
  return { address = window.address, workspace = previous and previous.workspace or nil,
    slot = previous and previous.slot or nil, spec = cleared, seq = engine.seq }
end

-- The slot list's, Assignment and Arrangements views' edits. Each builds new slots.lua data
-- (edit.lua), re-runs config.lua over it, checks the edit took effect (a
-- field config.lua builds in code, or does not take from slots.lua, would
-- not), and only then runs it like any edit: re-assign, re-route, window
-- rules, relayout, change event. Nothing is written until save.

local NO_DATA = "config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change"


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

-- Remember an edit that renames or removes what slots.lua names (a slot, an
-- layout) until data is the file's again: reset reads
-- the saved trees through them. `op` is edit.lua's function and its
-- arguments after the data.
local function remember(engine, op, ...)
  engine.since_save = engine.since_save or {}
  engine.since_save[#engine.since_save + 1] = { op = op, args = table.pack(...) }
end

-- Whether the global slots are the editor's to change.
local function editable_slots(engine)
  if not engine.data then
    return nil, NO_DATA
  end
  if not edit.editable(read_only_paths(engine.cfg), "slots") then
    return nil, "the slots are set by code in config.lua; edit them there"
  end
  return true
end

-- The workspace of a spec edit, if its specs are the editor's.
local function editable_specs(engine, args)
  if not engine.data then
    return nil, NO_DATA
  end
  local workspace = as_integer(args.workspace)
  if not edit.editable(read_only_paths(engine.cfg), "specs", workspace) then
    return nil, "workspace " .. tostring(workspace) .. "'s specs are set by code in config.lua; edit them there"
  end
  return workspace
end

-- Rewrite every keyboard-resized tree with keep(override) -> key, node (nil
-- drops it).
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

-- Carry every keyboard-resized tree through fn(node) -> node or nil.
local function on_every_tree(fn)
  return function(engine)
    carry_overrides(engine, function(o)
      local node = fn(o.tree)
      return node and o.key, node
    end)
  end
end

local function rename_assignments(engine, old, new)
  for _, map in ipairs({ "assignments", "overflow" }) do
    local renamed = {}
    for address, a in pairs(engine[map] or {}) do
      if a.slot == old then
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

local function workspace_spec(cfg, workspace, slot)
  local entry = cfg.specs[workspace] and cfg.specs[workspace][slot]
  return entry and entry.text
end

local function list(items, last)
  if #items <= 1 then
    return table.concat(items)
  end
  return table.concat(items, ", ", 1, #items - 1) .. (last or " and ") .. items[#items]
end

-- add_slot { slot, description? }: a global slot every workspace's trees may place.
function handlers.add_slot(engine, args)
  local ok, err = editable_slots(engine)
  if not ok then
    return fail(err)
  end
  local data, edit_err = edit.add_slot(engine.data, args.slot, args.description)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.slots[args.slot] then
      return not_taken("the slots")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { slot = args.slot, description = cfg.slots[args.slot].description, seq = engine.seq }
end

-- remove_slot { slot, force? }: refused while trees place the slot or workspaces
-- have specs for it, saying where, unless force; then it goes from all of
-- them too.
function handlers.remove_slot(engine, args)
  local ok, err = editable_slots(engine)
  if not ok then
    return fail(err)
  end
  local slot = args.slot
  local data, edit_err = edit.remove_slot(engine.data, slot)
  if not data then
    return fail(edit_err)
  end
  local uses = edit.slot_uses(engine.data, slot)
  if (#uses.trees > 0 or #uses.specs > 0) and args.force ~= true then
    local where = {}
    if #uses.trees > 0 then
      where[#where + 1] = "placed by " .. table.concat(uses.trees, ", ")
    end
    if #uses.specs > 0 then
      local workspaces = {}
      for i, workspace in ipairs(uses.specs) do
        workspaces[i] = tostring(workspace)
      end
      where[#where + 1] = "filled on workspace" .. (#workspaces > 1 and "s " or " ") .. list(workspaces)
    end
    return fail(string.format("slot '%s' is %s; remove it with force: true to take it out of all of them",
      slot, table.concat(where, " and ")))
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if c.slots[slot] then
      return not_taken("the slots")
    end
  end, on_every_tree(function(node) return edit.remove_leaf(node, slot) end))
  if not cfg then
    return fail(apply_err)
  end
  remember(engine, "remove_slot", slot)
  return { slot = slot, trees = array(uses.trees), specs = array(uses.specs), seq = engine.seq }
end

local function count_changed_trees(before, after)
  local was = {}
  local function each(data, fn)
    for name, entry in pairs(type(data.layouts) == "table" and data.layouts or {}) do
      if type(entry) == "table" then
        for n, trees in pairs(type(entry.workspaces) == "table" and entry.workspaces or {}) do
          for screen, text in pairs(type(trees) == "table" and trees or {}) do
            fn(name .. "/" .. tostring(n) .. "/" .. tostring(screen), text)
          end
        end
        for screen, text in pairs(type(entry.default) == "table" and entry.default or {}) do
          fn(name .. "/default/" .. tostring(screen), text)
        end
      end
    end
  end
  each(before, function(key, text) was[key] = text end)
  local n = 0
  each(after, function(key, text)
    if was[key] ~= nil and was[key] ~= text then
      n = n + 1
    end
  end)
  return n
end

-- rename_slot { slot, to }: everywhere: every tree of every layout, every
-- workspace's spec, the keyboard-resized trees and the
-- assignments (a hand-made one stays hand-made).
function handlers.rename_slot(engine, args)
  local ok, err = editable_slots(engine)
  if not ok then
    return fail(err)
  end
  local old, new = args.slot, args.to
  local data, edit_err = edit.rename_slot(engine.data, old, new)
  if not data then
    return fail(edit_err)
  end
  local uses = edit.slot_uses(engine.data, old)
  local trees = count_changed_trees(engine.data, data)
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.slots[new] or (new ~= old and c.slots[old]) then
      return not_taken("the slots")
    end
  end, function(e)
    on_every_tree(function(node) return edit.rename_leaf(node, old, new) end)(e)
    rename_assignments(e, old, new)
  end)
  if not cfg then
    return fail(apply_err)
  end
  remember(engine, "rename_slot", old, new)
  return { slot = old, to = new, trees = trees, specs = array(uses.specs), seq = engine.seq }
end

-- describe_slot { slot, description }: "" removes it.
function handlers.describe_slot(engine, args)
  local ok, err = editable_slots(engine)
  if not ok then
    return fail(err)
  end
  local data, edit_err = edit.describe_slot(engine.data, args.slot, args.description)
  if not data then
    return fail(edit_err)
  end
  local want = (args.description ~= nil and args.description ~= "") and args.description or nil
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.slots[args.slot] or c.slots[args.slot].description ~= want then
      return not_taken("the slots")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { slot = args.slot, description = args.description or "", seq = engine.seq }
end

-- set_spec { workspace, slot, spec }: the app that fills a global slot on a workspace.
function handlers.set_spec(engine, args)
  local workspace, err = editable_specs(engine, args)
  if not workspace then
    return fail(err)
  end
  local data, edit_err = edit.set_spec(engine.data, workspace, args.slot, args.spec)
  if not data then
    return fail(edit_err)
  end
  local text = data.specs[workspace][args.slot]
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if workspace_spec(c, workspace, args.slot) ~= text then
      return not_taken("workspace " .. workspace .. "'s specs")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { workspace = workspace, slot = args.slot, spec = text, seq = engine.seq }
end

-- clear_spec { workspace, slot }: the workspace no longer says which app fills the
-- slot (the slot and the trees stay; its window leaves it unless put there
-- by hand).
function handlers.clear_spec(engine, args)
  local workspace, err = editable_specs(engine, args)
  if not workspace then
    return fail(err)
  end
  local data, edit_err = edit.clear_spec(engine.data, workspace, args.slot)
  if not data then
    return fail(edit_err)
  end
  local was = engine.data.specs[workspace][args.slot]
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if workspace_spec(c, workspace, args.slot) ~= nil then
      return not_taken("workspace " .. workspace .. "'s specs")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  return { workspace = workspace, slot = args.slot, spec = was, seq = engine.seq }
end

-- The screen (on the active desk) of the workspace a window is on, or nil.
local function window_screen(engine, window)
  local entry = engine.workspaces[window.workspace_id]
  if entry then
    return entry.screen
  end
  local ok, monitor = pcall(adapter.workspace_monitor, window.workspace_id)
  for screen, name in ipairs(ok and engine.active and engine.active.monitors or {}) do
    if name == monitor then
      return screen
    end
  end
  return nil
end

-- take_spec { workspace, slot, address, place?, layout?, screen? }: the
-- Assignment view's a (aerolayout's):
-- the window's spec (spec.from_window) becomes the workspace's spec for the slot,
-- replacing the one it had, and the window takes the slot (over any other
-- window the spec matches; the one that held it is routed again). The edit
-- is checked before anything moves. With place, a slot the workspace's trees
-- in the layout (default the active one) do not place is put into them first
-- (edit.place_slot), on `screen`, else the screen of the window's workspace,
-- else 1; reply `placed` { layout, screen, tree, used_by[] }.
function handlers.take_spec(engine, args)
  local window = live_window(args.address)
  if not window then
    return fail("no open window " .. tostring(args.address))
  end
  local workspace, err = editable_specs(engine, args)
  if not workspace then
    return fail(err)
  end
  local text = spec.from_window(window, engine.cfg and engine.cfg.title_matching)
  if not text then
    return fail("window " .. tostring(args.address) .. " has no class to make a spec of")
  end
  local data, edit_err = engine.data, nil
  local placed
  if args.place == true then
    local name, layout_err = target_layout(engine, args)
    if not name then
      return fail(layout_err)
    end
    local screen = as_screen(args.screen) or window_screen(engine, window) or 1
    if math.type(screen) ~= "integer" or screen < 1 or screen > engine.cfg.layouts[name].screens then
      screen = 1
    end
    local on
    data, on = edit.place_slot(data, name, workspace, args.slot, screen)
    if not data then
      return fail(on)
    end
    placed = on and { layout = name, screen = on }
  end
  data, edit_err = edit.set_spec(data, workspace, args.slot, text)
  if not data then
    return fail(edit_err)
  end
  text = data.specs[workspace][args.slot]
  local cfg, load_err = config.load(engine.config_dir, { data = { [DATA_FILE] = data } })
  if cfg and workspace_spec(cfg, workspace, args.slot) ~= text then
    cfg, load_err = nil, not_taken("workspace " .. workspace .. "'s specs")
  end
  if not cfg then
    return fail(load_err)
  end
  if placed then
    -- the placed tree replaces a keyboard-resized one of that branch
    resize.clear(engine, placed.layout, workspace, placed.screen)
    local users = array()
    for _, desk_name in ipairs(cfg.desk_names) do
      if cfg.desks[desk_name].layout == placed.layout then
        users[#users + 1] = desk_name
      end
    end
    placed = object({ layout = placed.layout, screen = placed.screen,
      tree = serialize.tree(configured_tree(cfg, placed.layout, workspace, placed.screen)), used_by = users })
  end
  local before = engine.data.specs and engine.data.specs[workspace]
  local replaced = type(before) == "table" and before[args.slot] or nil
  -- Into the slot first, so the re-solve under the new spec keeps it there;
  -- the spec names the window, so it is an ordinary assignment, not by hand.
  local _, displaced = router.assign(engine, window, workspace, args.slot)
  if spec.admits(cfg.specs[workspace][args.slot], window) then
    engine.assignments[window.address] = { workspace = workspace, slot = args.slot }
  end
  engine:apply_config(cfg, data, true)
  return { workspace = workspace, slot = args.slot, spec = text, replaced = replaced, address = window.address,
    displaced = displaced, placed = placed, seq = engine.seq }
end

-- Desks and layouts (the Desk view) --------------------------------

local function section_editable(engine, section, name, what)
  if not engine.data then
    return nil, NO_DATA
  end
  if not edit.editable(read_only_paths(engine.cfg), section, name) then
    return nil, what .. " is set by code in config.lua; edit it there"
  end
  return true
end

-- The desk a call means: args.desk, else the active one; it must be the
-- editor's to change.
local function target_desk(engine, args)
  local name = args.desk
  if name == nil then
    if not engine.active then
      return nil, "no desk is active; name one with \"desk\""
    end
    name = engine.active.desk
  end
  if type(name) ~= "string" or not (engine.cfg and engine.cfg.desks[name]) then
    return nil, "no desk '" .. tostring(name) .. "'"
  end
  local ok, err = section_editable(engine, "desks", name, "desk '" .. name .. "'")
  if not ok then
    return nil, err
  end
  return name
end

local function active_desk(engine)
  return engine.active and engine.active.desk or nil
end

local function active_layout(engine)
  return engine.active and engine.active.layout or nil
end

local function took_desk(name, want)
  return function(c)
    local entry = c.desks[name]
    if not entry then
      return not_taken("desk '" .. name .. "'")
    end
    if want and not want(entry) then
      return not_taken("desk '" .. name .. "'")
    end
  end
end

-- add_desk { name, monitors[], layout }: a desk for these monitor selectors.
function handlers.add_desk(engine, args)
  local ok, err = section_editable(engine, "desks", args.name, "the desks")
  if not ok then
    return fail(err)
  end
  local data, edit_err = edit.add_desk(engine.data, args.name, args.monitors, args.layout)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, took_desk(args.name))
  if not cfg then
    return fail(apply_err)
  end
  return { desk = args.name, monitors = array(shallow(cfg.desks[args.name].monitors)), layout = args.layout,
    active = active_desk(engine), seq = engine.seq }
end

-- rename_desk { desk, to }
function handlers.rename_desk(engine, args)
  if args.desk == nil then
    return fail("name the desk with \"desk\"")
  end
  local old, err = target_desk(engine, args)
  if not old then
    return fail(err)
  end
  local new = args.to
  local data, edit_err = edit.rename_desk(engine.data, old, new)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.desks[new] or (new ~= old and c.desks[old]) then
      return not_taken("desk '" .. old .. "'")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  if engine.auto_desks[old] then
    engine.auto_desks[old], engine.auto_desks[new] = nil, true
  end
  return { desk = old, to = new, active = active_desk(engine), seq = engine.seq }
end

-- delete_desk { desk }: the active one too; its monitors are then a setup
-- no desk knows, which gets a new desk of its own (§8).
function handlers.delete_desk(engine, args)
  if args.desk == nil then
    return fail("name the desk with \"desk\"")
  end
  local name, err = target_desk(engine, args)
  if not name then
    return fail(err)
  end
  local data, edit_err = edit.delete_desk(engine.data, name)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if c.desks[name] then
      return not_taken("desk '" .. name .. "'")
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  engine.auto_desks[name] = nil
  return { desk = name, active = active_desk(engine), seq = engine.seq }
end

-- apply_layout { desk?, layout }: the desk (default: the active one) uses
-- this layout, one for as many screens as it has monitors.
function handlers.apply_layout(engine, args)
  local name, err = target_desk(engine, args)
  if not name then
    return fail(err)
  end
  local data, edit_err = edit.set_desk_layout(engine.data, name, args.layout)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, took_desk(name, function(entry)
    return entry.layout == args.layout
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { desk = name, layout = args.layout, active = active_desk(engine), seq = engine.seq }
end

-- set_pinned { desk?, pinned[] }: the desk's screens (1 the left-most)
-- excluded from workspace switching.
function handlers.set_pinned(engine, args)
  local name, err = target_desk(engine, args)
  if not name then
    return fail(err)
  end
  local data, edit_err = edit.set_pinned(engine.data, name, args.pinned)
  if not data then
    return fail(edit_err)
  end
  local want = data.desks[name].pinned or {}
  local cfg, apply_err = apply_edit(engine, data, took_desk(name, function(entry)
    if #entry.pinned_list ~= #want then
      return false
    end
    for i, index in ipairs(want) do
      if entry.pinned_list[i] ~= index then
        return false
      end
    end
    return true
  end))
  if not cfg then
    return fail(apply_err)
  end
  return { desk = name, pinned = array(shallow(want)), seq = engine.seq }
end

local function took_layout(name)
  return function(c)
    if not c.layouts[name] then
      return not_taken("layout '" .. name .. "'")
    end
  end
end

-- The default trees of a new layout for `screens` screens: the active
-- desk's monitors when it has that many (a laptop panel first scrolls),
-- else plain monitors.
local function default_trees(engine, screens)
  local monitors = {}
  if engine.active and #engine.active.monitors == screens then
    local by_name = {}
    for _, monitor in ipairs(adapter.monitors()) do
      by_name[monitor.name] = monitor
    end
    for i, name in ipairs(engine.active.monitors) do
      monitors[i] = by_name[name] or { name = name, x = i }
    end
  else
    for i = 1, screens do
      monitors[i] = { name = "screen-" .. i, x = i }
    end
  end
  return desk.default_trees(monitors, engine.cfg and engine.cfg.slot_names or {})
end

-- add_layout { name, screens, default? }: a new layout for `screens`
-- screens, empty, or with the default trees (default: true).
function handlers.add_layout(engine, args)
  local ok, err = section_editable(engine, "layouts", args.name, "the layouts")
  if not ok then
    return fail(err)
  end
  local screens = as_integer(args.screens)
  local trees = args.default == true and math.type(screens) == "integer" and default_trees(engine, screens) or nil
  local data, edit_err = edit.add_layout(engine.data, args.name, screens, trees)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, took_layout(args.name))
  if not cfg then
    return fail(apply_err)
  end
  return { layout = args.name, screens = cfg.layouts[args.name].screens, seq = engine.seq }
end

-- fork_layout { layout?, to, desk? }: a copy of the layout (default: the
-- active desk's), keyboard-resized trees included, which the desk (default:
-- the active one) then uses when it has as many monitors as the layout has
-- screens. Reply `desk`: the desk now using the copy, if any.
function handlers.fork_layout(engine, args)
  local source, err = target_layout(engine, args)
  if not source then
    return fail(err)
  end
  local new = args.to
  local ok, sec_err = section_editable(engine, "layouts", new, "the layouts")
  if not ok then
    return fail(sec_err)
  end
  local data, edit_err = edit.copy_layout(engine.data, source, new)
  if not data then
    return fail(edit_err)
  end
  local repoint = args.desk
  if repoint == nil then
    repoint = active_desk(engine)
  end
  if repoint then
    local desk_ok, desk_err = target_desk(engine, { desk = repoint })
    if not desk_ok then
      return fail(desk_err)
    end
    local entry = engine.cfg.desks[repoint]
    if #entry.monitors == engine.cfg.layouts[source].screens then
      data, edit_err = edit.set_desk_layout(data, repoint, new)
      if not data then
        return fail(edit_err)
      end
    elseif args.desk ~= nil then
      return fail(string.format("desk '%s' has %d monitor%s, and layout '%s' is for %d screen%s", repoint,
        #entry.monitors, #entry.monitors == 1 and "" or "s", source, engine.cfg.layouts[source].screens,
        engine.cfg.layouts[source].screens == 1 and "" or "s"))
    else
      repoint = nil -- the active desk has another monitor count: a copy only
    end
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.layouts[new] or (repoint and c.desks[repoint] and c.desks[repoint].layout ~= new) then
      return not_taken("the layouts")
    end
  end, function(e)
    local copies = {}
    for _, o in ipairs(resize.overrides(e)) do
      if o.layout == source then
        copies[resize.key(new, o.workspace, o.screen)] = o.tree
      end
    end
    for key, node in pairs(copies) do
      e.resized[key] = node
    end
  end)
  if not cfg then
    return fail(apply_err)
  end
  -- reset in the copy goes back to the saved trees of the layout it copies
  remember(engine, "copy_layout", source, new)
  return { layout = source, to = new, desk = repoint, active = active_layout(engine), seq = engine.seq }
end

-- rename_layout { layout, to }: the desks using it follow.
function handlers.rename_layout(engine, args)
  if args.layout == nil then
    return fail("name the layout with \"layout\"")
  end
  local old, err = target_layout(engine, args)
  if not old then
    return fail(err)
  end
  local new = args.to
  local data, edit_err = edit.rename_layout(engine.data, old, new)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if not c.layouts[new] or (new ~= old and c.layouts[old]) then
      return not_taken("layout '" .. old .. "'")
    end
  end, function(e)
    carry_overrides(e, function(o)
      if o.layout == old then
        return resize.key(new, o.workspace, o.screen), o.tree
      end
      return o.key, o.tree
    end)
  end)
  if not cfg then
    return fail(apply_err)
  end
  remember(engine, "rename_layout", old, new)
  return { layout = old, to = new, active = active_layout(engine), seq = engine.seq }
end

-- delete_layout { layout, remap? }: refused while desks use it, unless
-- `remap` names a layout for as many screens for them to use instead.
function handlers.delete_layout(engine, args)
  if args.layout == nil then
    return fail("name the layout with \"layout\"")
  end
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  local users = edit.layout_users(engine.data, name)
  local data, edit_err = edit.delete_layout(engine.data, name, args.remap)
  if not data then
    return fail(edit_err)
  end
  local cfg, apply_err = apply_edit(engine, data, function(c)
    if c.layouts[name] then
      return not_taken("layout '" .. name .. "'")
    end
  end, function(e)
    carry_overrides(e, function(o)
      if o.layout == name then
        return nil
      end
      return o.key, o.tree
    end)
  end)
  if not cfg then
    return fail(apply_err)
  end
  remember(engine, "delete_layout", name, args.remap)
  return { layout = name, remap = args.remap, desks = array(users), active = active_layout(engine), seq = engine.seq }
end

-- A desk the engine makes for monitors no desk knows (init.lua's
-- Engine:new_desk): `name` for these selectors using `layout`, made too (for
-- `screens` screens, with these default trees) when `trees` is given. An
-- edit like any other, in memory until saved. Returns true, or nil and why
-- not (config.lua does not take desks or layouts from slots.lua).
function M.new_desk(engine, name, selectors, layout, screens, trees)
  if not engine.data then
    return nil, NO_DATA
  end
  local read_only = read_only_paths(engine.cfg)
  if not edit.editable(read_only, "desks", name) or (trees and not edit.editable(read_only, "layouts", layout)) then
    return nil, "config.lua sets the desks or layouts by code"
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
  local cfg, apply_err = apply_edit(engine, data, took_desk(name))
  if not cfg then
    return nil, apply_err
  end
  return true
end

-- arrange {}: run the scroll pass now (order every scroll workspace
-- hyprslots keeps, and widen every column of the focused one), as Super+L
-- does on bringing slots back.
function handlers.arrange(engine)
  local result = scroll.arrange(engine, { widen_all = true })
  return { swaps = result.swaps, widened = array(result.widened) }
end

function handlers.workspace(engine, args)
  local ok, err = workspaces.activate(engine, args.workspace)
  if not ok then
    return { ok = false, error = err }
  end
  return { workspace = args.workspace }
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

-- Layout editing (the editor's Layout view) ---------------------------------

-- set_trees { layout?, workspace (or "default"), trees = { ["1"] = tree, ... } }:
-- several of a workspace's trees in one edit, so a slot can move from one
-- screen to another (a slot sits on one screen of a workspace, so two
-- set_tree calls could not do it). All or nothing; each tree set replaces
-- that branch's keyboard-resized override, which is kept when the edit
-- fails.
function handlers.set_trees(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail("config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change")
  end
  local n = as_workspace(args.workspace)
  if type(args.trees) ~= "table" then
    return fail("no trees to set: give \"trees\" as an object of screen -> tree")
  end
  local trees_in = {}
  for screen, text in pairs(args.trees) do
    trees_in[as_screen(screen)] = text
  end
  local data, set_err = edit.set_trees(engine.data, name, n, trees_in)
  if not data then
    return fail(set_err)
  end
  local nudged = {}
  for screen in pairs(trees_in) do
    local key = resize.key(name, n, screen)
    nudged[key] = engine.resized and engine.resized[key]
    resize.clear(engine, name, n, screen)
  end
  local cfg, apply_err = apply_data(engine, data)
  if not cfg then
    for key, override in pairs(nudged) do
      engine.resized[key] = override
    end
    return fail(apply_err)
  end
  local trees = object()
  for screen in pairs(trees_in) do
    local node = configured_tree(cfg, name, n, screen)
    trees[tostring(screen)] = object({ tree = serialize.tree(node), ratio = ratio.format(node) })
  end
  return { layout = name, workspace = n, trees = trees, seq = engine.seq }
end

-- fold_trees { layout? }: drop every workspace's own trees in the layout
-- that its shared (default) trees lay out the same (edit.fold_trees: the
-- shared tree with slots missing, which close up anyway); reply `folded[]`
-- (workspaces) and `kept[]` ({ workspace, reason }). Keyboard-resized trees
-- stay (they are per workspace). Nothing to fold changes nothing.
function handlers.fold_trees(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail(NO_DATA)
  end
  local data, report = edit.fold_trees(engine.data, name)
  if not data then
    return fail(report)
  end
  local kept = array()
  for i, k in ipairs(report.kept) do
    kept[i] = object({ workspace = k.workspace, reason = k.reason })
  end
  if #report.folded > 0 then
    local cfg, apply_err = apply_data(engine, data)
    if not cfg then
      return fail(apply_err)
    end
  end
  return { layout = name, folded = array(report.folded), kept = kept, seq = engine.seq }
end

-- drop_override { layout?, workspace, screen? }: the workspace back to the
-- layout's shared (default) trees (edit.drop_override; with `screen`, that
-- screen's tree only), dropping its keyboard-resized trees there too; reply
-- `own` (whether it still has trees of its own).
function handlers.drop_override(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail(NO_DATA)
  end
  local n, screen = as_integer(args.workspace), as_screen(args.screen)
  local data, drop_err = edit.drop_override(engine.data, name, n, screen)
  if not data then
    return fail(drop_err)
  end
  local saved = shallow(engine.resized)
  for s = 1, engine.cfg.layouts[name].screens do
    if screen == nil or s == screen then
      resize.clear(engine, name, n, s)
    end
  end
  local cfg, apply_err = apply_data(engine, data)
  if not cfg then
    engine.resized = saved
    return fail(apply_err)
  end
  return { layout = name, workspace = n, screen = screen, own = cfg.layouts[name].workspaces[n] ~= nil,
    seq = engine.seq }
end

-- slots.lua as it is on disk (data only, read in an empty environment, in
-- today's shape) and whether it is in a shape of before, or nil and why not.
local function saved_data(engine)
  local path = (engine.config_dir or config.dir()) .. "/" .. DATA_FILE
  local chunk, err = loadfile(path, "t", {})
  if not chunk then
    return nil, "cannot read " .. DATA_FILE .. ": " .. tostring(err)
  end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    return nil, "cannot read " .. DATA_FILE .. ": " .. (ok and "it returns no table" or tostring(data))
  end
  local ok_monitors, monitors = pcall(adapter.monitors)
  return migrate.data(data, ok_monitors and monitors or nil) -- read as load_data reads it
end

-- The saved data through the renames and removals made since (slots,
-- layouts), so its trees name what the running data
-- names. An edit that does not apply to the file (it renames a slot added
-- since) is skipped.
local function as_edited(engine, saved)
  local out = saved
  for _, e in ipairs(engine.since_save or {}) do
    out = edit[e.op](out, table.unpack(e.args, 1, e.args.n)) or out
  end
  return out
end

-- reset { layout?, workspace (or "default"), screen }: a branch back to the
-- tree slots.lua holds on disk (its own there, else the default one; no
-- tree when it has neither), read through the slot and layout renames and
-- removals made since, dropping both an unsaved edit and a keyboard-resized
-- override of it. Other branches keep their edits; the engine is clean again
-- when nothing differs from the file.
function handlers.reset(engine, args)
  local name, err = target_layout(engine, args)
  if not name then
    return fail(err)
  end
  if not engine.data then
    return fail("config.lua loads no " .. DATA_FILE .. ", so there is nothing the editor may change")
  end
  local n, screen = as_workspace(args.workspace), as_screen(args.screen)
  local saved, migrated_or_err = saved_data(engine)
  if not saved then
    return fail(migrated_or_err)
  end
  local migrated = migrated_or_err == true
  local data, reset_err = edit.reset_tree(engine.data, as_edited(engine, saved), name, n, screen)
  if not data then
    return fail(reset_err)
  end
  local cfg, load_err = config.load(engine.config_dir, { data = { [DATA_FILE] = data } })
  if not cfg then
    return fail(load_err)
  end
  resize.clear(engine, name, n, screen)
  -- a file in a shape of before differs from what runs until it is saved
  engine:apply_config(cfg, data, migrated or serialize.dump(data) ~= serialize.dump(saved))
  local node = configured_tree(cfg, name, n, screen)
  return { layout = name, workspace = n, screen = screen, tree = node and serialize.tree(node) or nil,
    ratio = node and ratio.format(node) or nil, seq = engine.seq }
end

return M
