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
local MAX_SCREENS = 10
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
-- { data = what the file holds, given = the copy config.lua was handed,
-- migrated = whether it was in a shape of before }. `monitors` (the
-- connected ones) order the screens of arrangements of before (migrate.lua).
function M.sandbox(dir, data, loaded, monitors)
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
    local migrated
    held, migrated = migrate.data(held, monitors)
    local given = deep_copy(held)
    if loaded then
      loaded[name] = { data = deep_copy(held), given = given, migrated = migrated }
    end
    return given
  end

  env._G = env
  return env
end

-- Errors collected with their path, e.g. "layouts.dual.workspaces[3][1]: ...".
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

local function is_workspace(key, count)
  return math.type(key) == "integer" and key >= 1 and key <= count
end

-- Why a workspace key is out of range, for `count` managed workspaces.
local function workspace_range(count)
  return "a workspace must be an integer from 1 to " .. count
    .. (count ~= WORKSPACES and " (workspaces = " .. count .. ")" or "")
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
local function validate_specs(raw, slots, fail, title_matching, count)
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
    if not is_workspace(workspace, count) then
      fail(path, workspace_range(count))
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

-- The layouts: name -> { screens = N, default = { [i] = tree }, workspaces =
-- { [n] = { [i] = tree } } }. A workspace's own trees replace the default
-- ones whole; screen i is the i-th monitor from the left.
local function validate_trees(path, raw, screens, slots, fail)
  local out = {}
  if type(raw) ~= "table" then
    fail(path, "must be a table of screen -> tree ({ [1] = \"h[left, main]\" })")
    return out
  end
  local placed = {}
  for _, index in ipairs(sorted_keys(raw)) do
    local branch_path = path .. "[" .. tostring(index) .. "]"
    if math.type(index) ~= "integer" or index < 1 or (screens and index > screens) then
      fail(branch_path, string.format("a screen must be an integer from 1 to %s", tostring(screens or "the layout's screens")))
    else
      local node, err = tree.parse(raw[index])
      if not node then
        fail(branch_path, err)
      else
        out[index] = node
        for _, slot in ipairs(tree.slots(node)) do
          if not slots[slot] then
            fail(branch_path, string.format("no slot '%s' (define it under slots)", slot))
          elseif placed[slot] then
            fail(branch_path, string.format("slot '%s' is placed on both screen %d and screen %d", slot, placed[slot], index))
          else
            placed[slot] = index
          end
        end
      end
    end
  end
  return out
end

local function check_entry_name(path, name, what, fail)
  if type(name) ~= "string" or name == "" or name:find("/", 1, true) or name ~= name:match("^%s*(.-)%s*$") then
    fail(path, string.format("a %s name is text with no '/' and no spaces around it, got '%s'", what, tostring(name)))
    return false
  end
  return true
end

local function validate_layout(name, raw, slots, fail, count)
  local path = key_path("layouts", name)
  if type(raw) ~= "table" then
    fail(path, "must be a table { screens = N, default = ..., workspaces = ... }")
    return nil
  end
  for key in pairs(raw) do
    if key ~= "screens" and key ~= "default" and key ~= "workspaces" then
      fail(path, "unknown key '" .. tostring(key) .. "'")
    end
  end
  local layout = { name = name, screens = nil, default = {}, workspaces = {} }
  local screens = raw.screens
  if math.type(screens) ~= "integer" or screens < 1 or screens > MAX_SCREENS then
    fail(path .. ".screens", "must be how many screens the layout is for, an integer from 1 to " .. MAX_SCREENS)
    screens = nil
  end
  layout.screens = screens
  if raw.default ~= nil then
    layout.default = validate_trees(path .. ".default", raw.default, screens, slots, fail)
  end
  if raw.workspaces ~= nil and type(raw.workspaces) ~= "table" then
    fail(path .. ".workspaces", "must be a table of workspace -> { [screen] = tree }")
  else
    for _, n in ipairs(sorted_keys(raw.workspaces or {})) do
      local ws_path = key_path(path .. ".workspaces", n)
      if not is_workspace(n, count) then
        fail(ws_path, workspace_range(count))
      else
        layout.workspaces[n] = validate_trees(ws_path, raw.workspaces[n], screens, slots, fail)
      end
    end
  end
  return layout
end

-- The desks: name -> { monitors = { selector, ... }, layout = name }. A desk is a monitor setup; it uses a layout for as
-- many screens as it has monitors.
local function validate_desk(name, raw, layouts, fail)
  local path = key_path("desks", name)
  if type(raw) ~= "table" then
    fail(path, "must be a table { monitors = { ... }, layout = \"name\" }")
    return nil
  end
  for key in pairs(raw) do
    if key ~= "monitors" and key ~= "layout" then
      fail(path, "unknown key '" .. tostring(key) .. "'")
    end
  end
  local desk = { name = name, monitors = {}, layout = nil }
  local monitors_path = path .. ".monitors"
  if type(raw.monitors) ~= "table" or raw.monitors[1] == nil then
    fail(monitors_path, "must list at least one monitor: { \"description|serial|connector\", ... }")
  else
    local seen = {}
    for key, selector in pairs(raw.monitors) do
      if math.type(key) ~= "integer" or key < 1 or key > #raw.monitors then
        fail(monitors_path, "must be a list of monitor selectors")
        break
      end
    end
    for i, selector in ipairs(raw.monitors) do
      if type(selector) ~= "string" or selector == "" then
        fail(monitors_path .. "[" .. i .. "]", "must be a monitor description, serial or connector name")
      elseif seen[selector] then
        fail(monitors_path .. "[" .. i .. "]", "'" .. selector .. "' is listed twice")
      else
        seen[selector] = true
        desk.monitors[#desk.monitors + 1] = selector
      end
    end
  end
  local layout_path = path .. ".layout"
  if type(raw.layout) ~= "string" then
    fail(layout_path, "must name the layout the desk uses")
  elseif not layouts[raw.layout] then
    fail(layout_path, "no layout '" .. raw.layout .. "' (define it under layouts)")
  else
    local layout = layouts[raw.layout]
    if layout.screens and #desk.monitors > 0 and layout.screens ~= #desk.monitors then
      fail(layout_path, string.format("layout '%s' is for %d screen%s, and the desk has %d monitor%s", raw.layout,
        layout.screens, layout.screens == 1 and "" or "s", #desk.monitors, #desk.monitors == 1 and "" or "s"))
    end
    desk.layout = raw.layout
  end
  return desk
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

local KNOWN = { slots = true, specs = true, desks = true, layouts = true, title_matching = true,
  scroll = true, workspaces = true }

-- How many workspaces hyprslots manages (1 to N: Super+N, the editor's
-- workspace keys, the workspace rules), default all ten of Omarchy's.
local function validate_count(raw, fail)
  if raw == nil then
    return WORKSPACES
  end
  if math.type(raw) ~= "integer" or raw < 1 or raw > WORKSPACES then
    fail("workspaces", "must be how many workspaces hyprslots manages, an integer from 1 to " .. WORKSPACES
      .. ", got " .. tostring(raw))
    return WORKSPACES
  end
  return raw
end

-- Normalize a raw config table. Returns the config, or nil and every error
-- found (one per line).
function M.validate(raw, monitors)
  if type(raw) ~= "table" then
    return nil, "the config must be a table, got " .. type(raw)
  end
  local migrated, _
  -- The shapes of before read as today's; every tree holding every slot.
  -- Only a shape of before counts as migrated here: a table config.lua builds
  -- in code is normalized each time it is loaded (saving cannot change it).
  raw, _, migrated = migrate.data(raw, monitors)

  local errors, fail = collector()

  for _, key in ipairs(sorted_keys(raw)) do
    if key == "arrangements" then
      fail("arrangements", "arrangements are desks and layouts now; give either, not both")
    elseif not KNOWN[key] then
      fail("config", "unknown key '" .. tostring(key) .. "'")
    end
  end

  local title_matching = validate_title_matching(raw.title_matching, fail)
  local slots, slot_names = validate_slots(raw.slots, fail)
  local count = validate_count(raw.workspaces, fail)
  local cfg = {
    workspaces = count,
    slots = slots,
    slot_names = slot_names,
    specs = validate_specs(raw.specs, slots, fail, title_matching, count),
    title_matching = title_matching,
    desks = {},
    desk_names = {},
    layouts = {},
    layout_names = {},
    scroll = validate_scroll(raw.scroll, fail),
  }

  for _, section in ipairs({ "layouts", "desks" }) do
    local entries = raw[section]
    if entries ~= nil and type(entries) ~= "table" then
      fail(section, "must be a table of name -> { ... }")
    else
      for _, name in ipairs(sorted_keys(entries or {})) do
        if check_entry_name(key_path(section, name), name, section == "desks" and "desk" or "layout", fail) then
          local entry
          if section == "layouts" then
            entry = validate_layout(name, entries[name], cfg.slots, fail, count)
          else
            entry = validate_desk(name, entries[name], cfg.layouts, fail)
          end
          if entry then
            cfg[section][name] = entry
            local names = section == "desks" and cfg.desk_names or cfg.layout_names
            names[#names + 1] = name
          end
        end
      end
    end
  end

  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end
  cfg.migrated = migrated
  return cfg
end

-- The trees a layout gives workspace n: screen -> parsed tree, its own or
-- else the default ones (nil when it has neither).
function M.trees_for(layout, n)
  if not layout then
    return nil
  end
  local own = layout.workspaces[n]
  if own then
    return own
  end
  return next(layout.default) ~= nil and layout.default or nil
end

-- Load config.lua from `dir` (default M.dir()). Returns the validated config,
-- or nil, an error message, and `true` when the file simply does not exist.
-- opts.data (name -> table) stands in for data files (see M.sandbox),
-- opts.monitors are the connected monitors (for the arrangements of
-- before). The config also keeps `dir`, `raw` (the table config.lua
-- returned), `data_files` (name -> { data, given, migrated }) for the editor
-- api, and `migrated` (a file or the config was in a shape of before).
function M.load(dir, opts)
  dir = dir or M.dir()
  local path = dir .. "/config.lua"

  local probe = io.open(path, "r")
  if not probe then
    return nil, "no config at " .. path, true
  end
  probe:close()

  local loaded = {}
  local monitors = opts and opts.monitors
  local raw, err = load_chunk(path, M.sandbox(dir, opts and opts.data, loaded, monitors))
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
    -- ... and one written for arrangements passes `arrangements`, which
    -- slots.lua now holds as desks and layouts.
    if type(file.data) == "table" and (file.data.desks ~= nil or file.data.layouts ~= nil)
      and raw.desks == nil and raw.layouts == nil then
      return nil, path .. ": " .. name .. " holds desks and layouts (the arrangements of before) that config.lua "
        .. "does not return: add `desks = data.desks, layouts = data.layouts` (in place of `arrangements`)"
    end
  end

  local cfg, invalid = M.validate(raw, monitors)
  if not cfg then
    return nil, path .. ":\n" .. invalid
  end
  cfg.dir, cfg.raw, cfg.data_files = dir, raw, loaded
  for _, file in pairs(loaded) do
    cfg.migrated = cfg.migrated or file.migrated
  end
  return cfg
end

return M
