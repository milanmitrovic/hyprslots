-- An app's desktop entry (docs/design.md §9, Launching apps): which one a
-- window class stands for, and the command it launches with. Desktop
-- entries live in the applications folder of each XDG data dir
-- ($XDG_DATA_HOME, then $XDG_DATA_DIRS), the first holding an id winning.
-- An adapter (it reads the disk); the api caches what it finds per class
-- for the Lua state, and stores the id with the specs it makes.

local launch = require("hyprslots.launch")

local M = {}

-- The applications folders, from an environment (name -> value; default
-- os.getenv), in the order they win.
function M.dirs(env)
  local get = env and function(name) return env[name] end or os.getenv
  local function set(name)
    local value = get(name)
    return value ~= nil and value ~= "" and value or nil
  end
  local home = set("HOME") or ""
  local out = { (set("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/applications" }
  for dir in (set("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"):gmatch("[^:]+") do
    out[#out + 1] = dir .. "/applications"
  end
  return out
end

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("a")
  file:close()
  return text
end

-- The text of desktop entry `id` (no ".desktop"), from the first folder
-- holding it.
local function entry(id, dirs)
  for _, dir in ipairs(dirs) do
    local text = read(dir .. "/" .. id .. ".desktop")
    if text then
      return text
    end
  end
  return nil
end

local function quoted(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- What the folders hold, read once per Lua state (two processes, whatever
-- their size): every desktop id, the first folder's first, and each
-- entry's StartupWMClass (lower case -> the id).
local indexes = {}
local function index(dirs)
  local key = table.concat(dirs, ":")
  if indexes[key] then
    return indexes[key]
  end
  local out = { ids = {}, wm = {} }
  local seen = {}
  for _, dir in ipairs(dirs) do
    local list = io.popen("ls -1 " .. quoted(dir) .. " 2>/dev/null")
    if list then
      for name in list:lines() do
        local id = name:match("^(.+)%.desktop$")
        if id and not seen[id] then
          seen[id] = dir
          out.ids[#out.ids + 1] = id
        end
      end
      list:close()
    end
  end
  table.sort(out.ids)
  local paths = {}
  for _, id in ipairs(out.ids) do
    paths[#paths + 1] = quoted(seen[id] .. "/" .. id .. ".desktop")
  end
  if #paths > 0 then
    local grep = io.popen("grep -s -H -i -m1 '^StartupWMClass=' " .. table.concat(paths, " ") .. " 2>/dev/null")
    if grep then
      for line in grep:lines() do
        local id, class = line:match("([^/]+)%.desktop:[^=]*=%s*(.-)%s*$")
        if id and class and out.wm[class:lower()] == nil then
          out.wm[class:lower()] = id
        end
      end
      grep:close()
    end
  end
  indexes[key] = out
  return out
end

-- The command desktop entry `id` launches with (launch.exec_line), or nil.
function M.command(id, dirs)
  return launch.exec_line(entry(id, dirs or M.dirs()))
end

-- The desktop id a window `class` stands for, and its command: the entry
-- named the class, else the class in lower case, else the one whose
-- StartupWMClass is the class, else one whose id ends in ".<class>" (a
-- reverse-domain id: org.gnome.Nautilus for nautilus). Nil when none
-- launches anything.
function M.resolve(class, dirs)
  if type(class) ~= "string" or class == "" then
    return nil
  end
  dirs = dirs or M.dirs()
  for _, id in ipairs({ class, class:lower() }) do
    local command = launch.exec_line(entry(id, dirs))
    if command then
      return id, command
    end
  end
  local found = index(dirs)
  local lower = class:lower()
  local id = found.wm[lower]
  local command = id and launch.exec_line(entry(id, dirs))
  if command then
    return id, command
  end
  for _, other in ipairs(found.ids) do
    if other:lower():sub(-(#lower + 1)) == "." .. lower then
      command = launch.exec_line(entry(other, dirs))
      if command then
        return other, command
      end
    end
  end
  return nil
end

return M
