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
--
-- Slots are global logical names (`slots = { main = { description = ... } }`),
-- defined once; a workspace says which app fills which of them (`specs = {
-- [3] = { main = "kitty/deltaf" } }`), and a tree may only place a slot
-- defined under `slots`. The per-workspace shape of before (slots =
-- workspace -> slot -> spec) is still read, through migrate.lua, in a data
-- file and in what config.lua returns.

local migrate = require("hyprslots.migrate")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local M = {}

local WORKSPACES = 10
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
    held = migrate.data(held)
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

local function is_workspace(key)
  return math.type(key) == "integer" and key >= 1 and key <= WORKSPACES
end

local function key_path(prefix, key)
  if type(key) == "string" and key:match("^[%a_][%w_]*$") then
    return prefix .. "." .. key
  end
  return prefix .. "[" .. tostring(key) .. "]"
end

-- The global slots: name -> { description? }. Returns name -> { description }
-- and the names, sorted.
local function validate_slots(raw, fail)
  local slots, names = {}, {}
  if raw == nil then
    return slots, names
  end
  if type(raw) ~= "table" then
    fail("slots", "must be a table of slot name -> { description = \"...\" }")
    return slots, names
  end
  for _, name in ipairs(sorted_keys(raw)) do
    local path = key_path("slots", name)
    local entry = raw[name]
    if type(name) ~= "string" or not name:match(SLOT_NAME) then
      fail(path, "a slot name must be letters, digits, '_' or '-', got '" .. tostring(name) .. "'")
    elseif type(entry) ~= "table" then
      fail(path, "must be a table { description = \"...\" } (or {}), got " .. type(entry))
    else
      for key in pairs(entry) do
        if key ~= "description" then
          fail(path, "unknown key '" .. tostring(key) .. "'")
        end
      end
      if entry.description ~= nil and type(entry.description) ~= "string" then
        fail(path .. ".description", "must be text")
      end
      slots[name] = { name = name, description = type(entry.description) == "string" and entry.description or nil }
      names[#names + 1] = name
    end
  end
  return slots, names
end

-- Each workspace's specs: workspace -> slot -> spec text, every slot a global
-- one. Returns workspace -> slot -> parsed spec.
local function validate_specs(raw, slots, fail, title_matching)
  local specs = {}
  if raw == nil then
    return specs
  end
  if type(raw) ~= "table" then
    fail("specs", "must be a table of workspace -> { slot = spec }")
    return specs
  end
  for _, workspace in ipairs(sorted_keys(raw)) do
    local path = key_path("specs", workspace)
    local entries = raw[workspace]
    if not is_workspace(workspace) then
      fail(path, "a workspace must be an integer from 1 to " .. WORKSPACES)
    elseif type(entries) ~= "table" then
      fail(path, "must be a table of slot = spec")
    else
      specs[workspace] = {}
      for _, name in ipairs(sorted_keys(entries)) do
        local slot_path = key_path(path, name)
        if type(name) ~= "string" or not slots[name] then
          fail(slot_path, "no slot '" .. tostring(name) .. "' (define it under slots)")
        else
          local parsed, err = spec.parse(entries[name], title_matching)
          if parsed then
            specs[workspace][name] = parsed
          else
            fail(slot_path, err)
          end
        end
      end
    end
  end
  return specs
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

  local arrangement = { name = name, screens = {}, roles = {}, workspaces = {} }

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

  -- The data key is still `desks` (slots.lua's on-disk shape).
  local desks_path = path .. ".desks"
  if raw.desks ~= nil and type(raw.desks) ~= "table" then
    fail(desks_path, "must be a table of workspace -> { role = tree }")
    return arrangement
  end
  for _, workspace in ipairs(sorted_keys(raw.desks or {})) do
    local workspace_path = key_path(desks_path, workspace)
    local branches = raw.desks[workspace]
    if not is_workspace(workspace) then
      fail(workspace_path, "a workspace must be an integer from 1 to " .. WORKSPACES)
    elseif type(branches) ~= "table" then
      fail(workspace_path, "must be a table of role = tree")
    else
      arrangement.workspaces[workspace] = {}
      local placed = {}
      for _, role in ipairs(sorted_keys(branches)) do
        local branch_path = key_path(workspace_path, role)
        if not arrangement.screens[role] then
          fail(branch_path, "no screen role '" .. tostring(role) .. "' in this arrangement's screens")
        else
          local node, err = tree.parse(branches[role])
          if not node then
            fail(branch_path, err)
          else
            arrangement.workspaces[workspace][role] = node
            for _, slot in ipairs(tree.slots(node)) do
              if not slots[slot] then
                fail(branch_path, string.format("no slot '%s' (define it under slots)", slot))
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

-- title_matching (docs/design.md §7a): extractors and strip_patterns map a
-- class to a string (a plain separator; a Lua pattern), browser_apps lists
-- classes. Errors are reported; spec.title_matching fills in the defaults.
local function validate_title_matching(raw, fail)
  if raw == nil then
    return spec.title_matching(nil)
  end
  local path = "title_matching"
  if type(raw) ~= "table" then
    fail(path, "must be a table { extractors, strip_patterns, browser_apps }")
    return spec.title_matching(nil)
  end
  for _, key in ipairs(sorted_keys(raw)) do
    if key ~= "extractors" and key ~= "strip_patterns" and key ~= "browser_apps" then
      fail(path, "unknown key '" .. tostring(key) .. "'")
    end
  end
  for _, key in ipairs({ "extractors", "strip_patterns" }) do
    local map = raw[key]
    if map ~= nil and type(map) ~= "table" then
      fail(path .. "." .. key, "must be a table of class -> string")
    elseif map then
      for _, class in ipairs(sorted_keys(map)) do
        local value = map[class]
        local entry = key_path(path .. "." .. key, class)
        if type(class) ~= "string" or type(value) ~= "string" or value == "" then
          fail(entry, "must map a class name to a non-empty string")
        elseif key == "strip_patterns" then
          local ok, err = pcall(string.find, "", value)
          if not ok then
            fail(entry, "not a valid Lua pattern (" .. tostring(err) .. "); Lua patterns are not regexes: escape magic characters with %")
          end
        end
      end
    end
  end
  local browsers = raw.browser_apps
  if browsers ~= nil then
    local ok = type(browsers) == "table"
    if ok then
      for key, class in pairs(browsers) do
        if math.type(key) ~= "integer" or type(class) ~= "string" or class == "" then
          ok = false
        end
      end
    end
    if not ok then
      fail(path .. ".browser_apps", "must be a list of class names")
    end
  end
  return spec.title_matching(raw)
end

-- scroll = { width = <fraction of the screen> }: how wide scroll branches'
-- columns are (scroll.lua; default 0.99, Omarchy's full-width scrolling).
local function validate_scroll(raw, fail)
  if raw == nil then
    return nil
  end
  if type(raw) ~= "table" then
    fail("scroll", "must be a table: { width = 0.99 }")
    return nil
  end
  for key in pairs(raw) do
    if key ~= "width" then
      fail("scroll", "unknown key '" .. tostring(key) .. "'")
    end
  end
  local width = raw.width
  if width == nil then
    return {}
  end
  if type(width) ~= "number" or width ~= width or width < 0.1 or width > 1 then
    fail("scroll.width", "must be a fraction of the screen from 0.1 to 1, got " .. tostring(width))
    return {}
  end
  return { width = width }
end

local KNOWN = { slots = true, specs = true, arrangements = true, pinned = true, title_matching = true,
  scroll = true }

-- Normalize a raw config table. Returns the config, or nil and every error
-- found (one per line).
function M.validate(raw)
  if type(raw) ~= "table" then
    return nil, "the config must be a table, got " .. type(raw)
  end
  raw = migrate.data(raw) -- the per-workspace shape of before, read as today's

  local errors, fail = collector()

  for _, key in ipairs(sorted_keys(raw)) do
    if not KNOWN[key] then
      fail("config", "unknown key '" .. tostring(key) .. "'")
    end
  end

  local title_matching = validate_title_matching(raw.title_matching, fail)
  local slots, slot_names = validate_slots(raw.slots, fail)
  local cfg = {
    slots = slots,
    slot_names = slot_names,
    specs = validate_specs(raw.specs, slots, fail, title_matching),
    title_matching = title_matching,
    arrangements = {},
    arrangement_names = {},
    pinned = validate_pinned(raw.pinned, fail),
    scroll = validate_scroll(raw.scroll, fail),
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

  -- A config.lua written for the per-workspace shape passes slots.lua's slots on
  -- and nothing else; the specs that now sit beside them would be lost.
  for name, file in pairs(loaded) do
    if raw.specs == nil and type(file.data) == "table" and type(file.data.specs) == "table"
      and next(file.data.specs) ~= nil then
      return nil, path .. ": " .. name .. " holds specs (workspace -> slot -> app) that config.lua does not return: "
        .. "add `specs = data.specs` beside `slots = data.slots`"
    end
  end

  local cfg, invalid = M.validate(raw)
  if not cfg then
    return nil, path .. ":\n" .. invalid
  end
  cfg.dir, cfg.raw, cfg.data_files = dir, raw, loaded
  return cfg
end

return M
