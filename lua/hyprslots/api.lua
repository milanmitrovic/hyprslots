-- The engine's api for the editor and the e2e tests (docs/design.md §9):
--
--   hyprctl repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")'
--   hyprctl repl 'return hyprslots.api.state()'
--
-- Every reply is a JSON string: { "ok": true, ... } or { "ok": false, "error": "..." }.
-- Nothing here raises into Hyprland. Calls: state, desk, set_tree, set_ratio,
-- record, save, reload (the contract is in docs/design.md §9). Every change
-- bumps `seq` and emits hl.dsp.event("hyprslots changed <seq>").

local json = require("hyprslots.dkjson")
local adapter = require("hyprslots.hl_adapter")
local config = require("hyprslots.config")
local desks = require("hyprslots.desks")
local edit = require("hyprslots.edit")
local groups = require("hyprslots.groups")
local ratio = require("hyprslots.ratio")
local record = require("hyprslots.record")
local resize = require("hyprslots.resize")
local serialize = require("hyprslots.serialize")
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
    out[#out + 1] = object({
      address = window.address,
      class = window.class,
      title = window.title,
      workspace = window.workspace_id,
      floating = window.floating,
      box = window.box and object(window.box) or nil,
      desk = assignment and assignment.desk or nil,
      slot = assignment and assignment.slot or nil,
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
  local screens, workspaces, assignments = object(), object(), object()
  if engine.active then
    for role, monitor in pairs(engine.active.monitors) do
      screens[role] = monitor
    end
  end
  for id, desk in pairs(engine.workspaces) do
    workspaces[tostring(id)] = object({ desk = desk.desk, role = desk.role, monitor = desk.monitor })
  end
  for address, assignment in pairs(engine.assignments) do
    assignments[address] = object({ desk = assignment.desk, slot = assignment.slot })
  end
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
    log_seq = engine.log.seq,
    arrangements = arrangements_info(engine, read_only),
    slots = slots_info(engine),
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
