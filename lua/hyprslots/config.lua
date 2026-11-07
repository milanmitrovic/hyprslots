-- Load and validate the user's configuration (docs/design.md §4).
--
--   $XDG_CONFIG_HOME/hyprslots/config.lua  hand-written, real Lua, sandboxed
--   $XDG_CONFIG_HOME/hyprslots/slots.lua   data only, loaded by config.lua
--                                          through load_data("slots.lua")
--
-- config.lua runs with a small environment: the pure standard library,
-- os.getenv/date/time, hostname() and load_data(); no os.execute, io,
-- require, dofile or hl. A data file runs in an empty environment, so it can
-- only be a table literal.
--
-- `validate` turns the returned table into the normalized form the engine
-- uses: specs and trees parsed, every error reported with its path.

local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local M = {}

local DESKS = 10
local SLOT_NAME = "^[%a_][%w_%-]*$"

-- The directory hyprslots reads its config from.
function M.dir()
  local base = os.getenv("XDG_CONFIG_HOME")
  if not base or base:sub(1, 1) ~= "/" then
    base = (os.getenv("HOME") or "") .. "/.config"
  end
  return base .. "/hyprslots"
end

local function copy(source, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = source[key]
  end
  return out
end

local function shallow(source)
  local out = {}
  for key, value in pairs(source) do
    out[key] = value
  end
  return out
end

local function hostname()
  local file = io.open("/etc/hostname", "r")
  if file then
    local name = file:read("l")
    file:close()
    if name and name ~= "" then
      return name
    end
  end
  return os.getenv("HOSTNAME") or ""
end

local function load_chunk(path, env)
  local chunk, err = loadfile(path, "t", env)
  if not chunk then
    return nil, err
  end
  local ok, result = pcall(chunk)
  if not ok then
    return nil, path .. ": " .. tostring(result)
  end
  return result
end

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, inner in pairs(value) do
    out[key] = deep_copy(inner)
  end
  return out
end

-- The environment config.lua runs in. `data` (name -> table) stands in for
-- data files, so the engine can re-run config.lua over edited slots.lua data
-- without writing it first. `loaded` (when given) records, per data file,
-- { data = what the file holds, given = the copy config.lua was handed }.
function M.sandbox(dir, data, loaded)
  local env = copy(_G, {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawlen", "rawset",
    "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "xpcall", "_VERSION",
  })
  env.string = shallow(string)
  env.table = shallow(table)
  env.math = shallow(math)
  env.utf8 = shallow(utf8)
  env.os = copy(os, { "getenv", "date", "time", "clock" })
  env.hostname = hostname

  function env.load_data(name)
    if type(name) ~= "string" or not name:match("^[%w_%-][%w_%-%.]*$") or name:find("..", 1, true) then
      error("load_data: '" .. tostring(name) .. "' must be a plain file name in " .. dir, 2)
    end
    local held
    if data and data[name] ~= nil then
      held = data[name]
    else
      local err
      held, err = load_chunk(dir .. "/" .. name, {})
      if err then
        error("load_data: " .. err, 2)
      end
    end
    local given = deep_copy(held)
    if loaded then
      loaded[name] = { data = deep_copy(held), given = given }
    end
    return given
  end

  env._G = env
  return env
end

-- Errors collected with their path, e.g. "arrangements.dual.desks[3].big: ...".
local function collector()
  local errors = {}
  return errors, function(path, message)
    errors[#errors + 1] = path .. ": " .. message
  end
end

local function sorted_keys(t)
  local keys = {}
  for key in pairs(t) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) < type(b)
  end)
  return keys
end

local function is_desk(key)
  return math.type(key) == "integer" and key >= 1 and key <= DESKS
end

local function key_path(prefix, key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") then
    return prefix .. "." .. key
  end
  return prefix .. "[" .. tostring(key) .. "]"
end

local function validate_slots(raw, fail)
  local slots = {}
  if raw == nil then
    return slots
  end
  if type(raw) ~= "table" then
    fail("slots", "must be a table of desk -> { slot = spec }")
    return slots
  end
  for _, desk in ipairs(sorted_keys(raw)) do
    local path = key_path("slots", desk)
    local entries = raw[desk]
    if not is_desk(desk) then
      fail(path, "a desk must be an integer from 1 to " .. DESKS)
    elseif type(entries) ~= "table" then
      fail(path, "must be a table of slot = spec")
    else
      slots[desk] = {}
      for _, name in ipairs(sorted_keys(entries)) do
        local slot_path = key_path(path, name)
        if type(name) ~= "string" or not name:match(SLOT_NAME) then
          fail(slot_path, "a slot name must be letters, digits, '_' or '-', got '" .. tostring(name) .. "'")
        else
          local parsed, err = spec.parse(entries[name])
          if parsed then
            slots[desk][name] = parsed
          else
            fail(slot_path, err)
            slots[desk][name] = false -- the slot exists; its spec is broken
          end
        end
      end
    end
  end
  return slots
end

local function validate_arrangement(name, raw, slots, fail)
  local path = key_path("arrangements", name)
  if type(raw) ~= "table" then
    fail(path, "must be a table { screens = ..., desks = ... }")
    return nil
  end
  for key in pairs(raw) do
    if key ~= "screens" and key ~= "desks" then
      fail(path, "unknown key '" .. tostring(key) .. "'")
    end
  end

  local arrangement = { name = name, screens = {}, roles = {}, desks = {} }

  local screens_path = path .. ".screens"
  if type(raw.screens) ~= "table" or next(raw.screens) == nil then
    fail(screens_path, "must name at least one screen: { role = \"description|serial|connector\" }")
  else
    for _, role in ipairs(sorted_keys(raw.screens)) do
      local selector = raw.screens[role]
      if type(role) ~= "string" or not role:match(SLOT_NAME) then
        fail(screens_path, "a screen role must be a name, got '" .. tostring(role) .. "'")
      elseif type(selector) ~= "string" or selector == "" then
        fail(key_path(screens_path, role), "must be a monitor description, serial or connector name")
      else
        arrangement.screens[role] = selector
        arrangement.roles[#arrangement.roles + 1] = role
      end
    end
  end

  local desks_path = path .. ".desks"
  if raw.desks ~= nil and type(raw.desks) ~= "table" then
    fail(desks_path, "must be a table of desk -> { role = tree }")
    return arrangement
  end
  for _, desk in ipairs(sorted_keys(raw.desks or {})) do
    local desk_path = key_path(desks_path, desk)
    local branches = raw.desks[desk]
    if not is_desk(desk) then
      fail(desk_path, "a desk must be an integer from 1 to " .. DESKS)
    elseif type(branches) ~= "table" then
      fail(desk_path, "must be a table of role = tree")
    else
      arrangement.desks[desk] = {}
      local placed = {}
      for _, role in ipairs(sorted_keys(branches)) do
        local branch_path = key_path(desk_path, role)
        if not arrangement.screens[role] then
          fail(branch_path, "no screen role '" .. tostring(role) .. "' in this arrangement's screens")
        else
          local node, err = tree.parse(branches[role])
          if not node then
            fail(branch_path, err)
          else
            arrangement.desks[desk][role] = node
            for _, slot in ipairs(tree.slots(node)) do
              if not (slots[desk] and slots[desk][slot] ~= nil) then
                fail(branch_path, string.format("desk %d has no slot '%s' (define it under slots[%d])", desk, slot, desk))
              elseif placed[slot] then
                fail(branch_path, string.format("slot '%s' is placed on both '%s' and '%s'", slot, placed[slot], role))
              else
                placed[slot] = role
              end
            end
          end
        end
      end
    end
  end

  return arrangement
end

local function validate_pinned(raw, fail)
  local pinned = {}
  if raw == nil then
    return pinned
  end
  if type(raw) ~= "table" then
    fail("pinned", "must be a list of screen roles")
    return pinned
  end
  for i, role in ipairs(raw) do
    if type(role) ~= "string" then
      fail("pinned[" .. i .. "]", "must be a screen role name")
    else
      pinned[role] = true
    end
  end
  return pinned
end

local KNOWN = { slots = true, arrangements = true, pinned = true, title_rules = true }

-- Normalize a raw config table. Returns the config, or nil and every error
-- found (one per line).
function M.validate(raw)
  if type(raw) ~= "table" then
    return nil, "the config must be a table, got " .. type(raw)
  end

  local errors, fail = collector()

  for _, key in ipairs(sorted_keys(raw)) do
    if not KNOWN[key] then
      fail("config", "unknown key '" .. tostring(key) .. "'")
    end
  end

  local cfg = {
    slots = validate_slots(raw.slots, fail),
    arrangements = {},
    arrangement_names = {},
    pinned = validate_pinned(raw.pinned, fail),
    title_rules = raw.title_rules,
  }

  if raw.arrangements ~= nil and type(raw.arrangements) ~= "table" then
    fail("arrangements", "must be a table of name -> { screens, desks }")
  else
    for _, name in ipairs(sorted_keys(raw.arrangements or {})) do
      if type(name) ~= "string" then
        fail("arrangements", "an arrangement name must be a string, got " .. tostring(name))
      else
        local arrangement = validate_arrangement(name, raw.arrangements[name], cfg.slots, fail)
        if arrangement then
          cfg.arrangements[name] = arrangement
          cfg.arrangement_names[#cfg.arrangement_names + 1] = name
        end
      end
    end
  end

  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  return cfg
end

-- Load config.lua from `dir` (default M.dir()). Returns the validated config,
-- or nil, an error message, and `true` when the file simply does not exist.
-- opts.data (name -> table) stands in for data files (see M.sandbox). The
-- config also keeps `dir`, `raw` (the table config.lua returned) and
-- `data_files` (name -> { data, given }) for the editor api.
function M.load(dir, opts)
  dir = dir or M.dir()
  local path = dir .. "/config.lua"

  local probe = io.open(path, "r")
  if not probe then
    return nil, "no config at " .. path, true
  end
  probe:close()

  local loaded = {}
  local raw, err = load_chunk(path, M.sandbox(dir, opts and opts.data, loaded))
  if err then
    return nil, err
  end
  if type(raw) ~= "table" then
    return nil, path .. " must return a table, got " .. type(raw)
  end

  local cfg, invalid = M.validate(raw)
  if not cfg then
    return nil, path .. ":\n" .. invalid
  end
  cfg.dir, cfg.raw, cfg.data_files = dir, raw, loaded
  return cfg
end

return M
