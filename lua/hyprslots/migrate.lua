-- slots.lua's shape of before, read as today's (docs/design.md §4).
--
-- Before: slots were per workspace, and so were their descriptions:
--
--   slots = { [3] = { main = "kitty/deltaf", right = "firefox" } },
--   descriptions = { [3] = { main = "the editor" } },
--
-- Now slots are global logical names, defined once, and a workspace only
-- says which app fills which of them:
--
--   slots = { main = { description = "the editor" }, right = {} },
--   specs = { [3] = { main = "kitty/deltaf", right = "firefox" } },
--
-- `slots` returns the second shape for either: every slot name some workspace
-- had becomes a global slot, each workspace's specs move under `specs`
-- unchanged, and a slot's descriptions move onto it (every different one, in
-- workspace order, joined with "; "; one for a slot no workspace has is
-- dropped). What it cannot read is carried over as it is, for config.validate
-- to report. `data` reads both this and the arrangements of before (`desks`,
-- below). Pure; the table given is never changed.

local desk = require("hyprslots.desk")
local edit = require("hyprslots.edit")
local serialize = require("hyprslots.serialize")
local tree = require("hyprslots.tree")

local M = {}

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, inner in pairs(value) do
    out[key] = copy(inner)
  end
  return out
end

local function sorted(t)
  local keys = {}
  for key in pairs(t) do
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

-- Whether data is in the per-workspace shape: `slots` keyed by workspace (a
-- number), or per-workspace `descriptions`.
function M.legacy(data)
  if type(data) ~= "table" then
    return false
  end
  if data.descriptions ~= nil then
    return true
  end
  if type(data.slots) ~= "table" then
    return false
  end
  for key in pairs(data.slots) do
    if type(key) == "number" then
      return true
    end
  end
  return false
end

-- The data in today's shape (a copy), and whether it had to change: the
-- shapes of before (M.slots, M.desks), and then what today's shape no longer
-- has or always has (M.unpin, M.normalize). The third value says whether a
-- shape of before was read (the first two alone), which config.validate
-- reports for a table config.lua builds in code.
function M.data(data, monitors)
  local out, changed = M.slots(data)
  local converted, moved = M.desks(out, monitors)
  local unpinned, dropped = M.unpin(converted)
  local normalized, filled = M.normalize(unpinned, monitors)
  return normalized, changed or moved or dropped or filled, changed or moved
end

-- Pinned screens are gone (a desk's `pinned`, and the arrangements' top-level
-- `pinned` roles): the data without them (a copy), and whether it had any.
function M.unpin(data)
  local out = copy(data)
  if type(out) ~= "table" then
    return out, false
  end
  local changed = out.pinned ~= nil
  out.pinned = nil
  if type(out.desks) == "table" then
    for _, entry in pairs(out.desks) do
      if type(entry) == "table" and entry.pinned ~= nil then
        entry.pinned = nil
        changed = true
      end
    end
  end
  return out, changed
end

-- config.lua's `scroll = { width = w }` of before gave every scroll branch's
-- columns one width; each tree says its own now (`scroll:0.5[...]`), full
-- width when it says none. The width of before goes into every scroll tree
-- of `layouts` (a layouts table: name -> { default, workspaces }) that
-- says none, in place, since config.lua may hand the very table on; a
-- full width (FULL_WIDTH or more, the default) changes nothing. Returns
-- whether anything changed.
M.FULL_WIDTH = 0.99

function M.scroll_width(layouts, width)
  if type(layouts) ~= "table" or type(width) ~= "number" or width < 0.1 or width >= M.FULL_WIDTH then
    return false
  end
  local changed = false
  local function widen(trees)
    if type(trees) ~= "table" then
      return
    end
    for screen, text in pairs(trees) do
      local node = type(text) == "string" and tree.parse(text)
      if node and node.scroll and not node.width then
        node.width = width
        trees[screen] = serialize.tree(node)
        changed = true
      end
    end
  end
  for _, layout in pairs(layouts) do
    if type(layout) == "table" then
      widen(layout.default)
      for _, trees in pairs(type(layout.workspaces) == "table" and layout.workspaces or {}) do
        widen(trees)
      end
    end
  end
  return changed
end

local function set_of(list)
  local out = {}
  for _, value in ipairs(list) do
    out[value] = true
  end
  return out
end

-- One tree set (screen -> text) holding every global slot (`names`,
-- sorted, `global` the same as a set): the slots that are not global
-- dropped (a tree left with none goes), the missing ones appended
-- (tree.append) to the left-most screen that has a tree. Changes `trees`
-- in place; a tree whose slots stay is kept as written. Returns whether
-- anything changed. A set with a tree that does not parse is left alone,
-- for config.validate to report.
local function fill(trees, names, global)
  local screens, nodes = {}, {}
  for screen, text in pairs(trees) do
    if type(text) ~= "string" then
      return false
    end
    local node = tree.parse(text)
    if not node then
      return false
    end
    screens[#screens + 1] = screen
    nodes[screen] = node
  end
  table.sort(screens, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)

  local placed, touched = {}, {}
  for _, screen in ipairs(screens) do
    local node = nodes[screen]
    for _, slot in ipairs(tree.slots(node)) do
      if global[slot] then
        placed[slot] = true
      else
        node = node and edit.remove_leaf(node, slot)
        touched[screen] = true
      end
    end
    nodes[screen] = node
  end
  local missing = {}
  for _, name in ipairs(names) do
    if not placed[name] then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    for _, screen in ipairs(screens) do
      if nodes[screen] then
        nodes[screen] = tree.append(nodes[screen], missing)
        touched[screen] = true
        break
      end
    end
  end
  local changed = false
  for _, screen in ipairs(screens) do
    if touched[screen] then
      trees[screen] = nodes[screen] and serialize.tree(nodes[screen]) or nil
      changed = true
    end
  end
  return changed
end

-- The monitor a layout's screen 1 is, as far as the data and `monitors`
-- (the connected ones, or nil) tell: for the first desk using the layout
-- (by name) whose monitors are all connected, the left-most of them; else
-- the first monitor the first desk using it lists, connected or not (a
-- laptop panel is selected by its connector, so it is known by name);
-- else, when no desk uses it and as many monitors as it has screens are
-- connected, the left-most of those. nil when nothing tells.
local function first_screen(data, name, screens, monitors)
  local usable = desk.usable(monitors)
  local users = {}
  if type(data.desks) == "table" then
    for _, desk_name in ipairs(sorted(data.desks)) do
      local entry = data.desks[desk_name]
      if type(entry) == "table" and entry.layout == name and type(entry.monitors) == "table"
        and type(entry.monitors[1]) == "string" then
        users[#users + 1] = entry.monitors
      end
    end
  end
  for _, selectors in ipairs(users) do
    local found = desk.match(selectors, usable)
    if found then
      local list = {}
      for _, selector in ipairs(selectors) do
        list[#list + 1] = found[selector]
      end
      return desk.order(list)[1]
    end
  end
  if users[1] then
    return desk.find(users[1][1], usable) or { name = users[1][1] }
  end
  if #usable > 0 and #usable == screens then
    return desk.order(usable)[1]
  end
  return nil
end

-- Whether a tree set has no tree.
local function treeless(trees)
  return trees == nil or (type(trees) == "table" and next(trees) == nil)
end

-- Every tree holds every global slot: each tree set of each layout (its
-- default trees, each workspace's own) gets the global slots it leaves out,
-- by name, and loses the slots that are not global (fill above). Empty
-- slots close up, so a slot nothing fills on a workspace takes no room.
-- A layout is never treeless: one with no default tree (none given, or
-- every one dropped above) gets the default trees of a new desk's layout
-- (desk.default_trees), every global slot on screen 1, as a scroll branch
-- (full width) when screen 1 is a laptop panel (first_screen above), else
-- side by side. A workspace with no trees of its own stays without any (it
-- uses the layout's). `monitors` (the connected ones, or nil) tell which
-- monitor screen 1 is. Returns the data (a copy) and whether it changed.
function M.normalize(data, monitors)
  local out = copy(data)
  if type(out) ~= "table" or type(out.slots) ~= "table" or type(out.layouts) ~= "table" then
    return out, false
  end
  local names = {}
  for name in pairs(out.slots) do
    if type(name) == "string" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local global = set_of(names)
  local changed = false
  for _, name in ipairs(sorted(out.layouts)) do
    local layout = out.layouts[name]
    if type(layout) == "table" then
      if type(layout.default) == "table" and fill(layout.default, names, global) then
        changed = true
      end
      local screens = layout.screens
      if treeless(layout.default) and #names > 0 and math.type(screens) == "integer" and screens >= 1 then
        local first = first_screen(out, name, screens, monitors) or { name = "screen-1" }
        layout.default = desk.default_trees({ first }, names)
        fill(layout.default, names, global)
        changed = true
      end
      if type(layout.workspaces) == "table" then
        for _, n in ipairs(sorted(layout.workspaces)) do
          if type(layout.workspaces[n]) == "table" and fill(layout.workspaces[n], names, global) then
            changed = true
          end
        end
      end
    end
  end
  return out, changed
end

-- The per-workspace slots of before read as global slots (a copy), and
-- whether it had to change.
function M.slots(data)
  local out = copy(data)
  if not M.legacy(data) then
    return out, false
  end

  local slots, specs = {}, type(out.specs) == "table" and out.specs or {}
  local per_workspace = type(data.slots) == "table" and data.slots or {}
  for _, key in ipairs(sorted(per_workspace)) do
    local entries = per_workspace[key]
    if type(key) ~= "number" then
      slots[key] = copy(entries) -- a global slot given beside workspaces
    elseif type(entries) ~= "table" then
      if specs[key] == nil then
        specs[key] = copy(entries)
      end
    else
      local own = type(specs[key]) == "table" and specs[key] or {}
      specs[key] = own
      for _, name in ipairs(sorted(entries)) do
        if own[name] == nil then
          own[name] = entries[name]
        end
        if slots[name] == nil then
          slots[name] = {}
        end
      end
    end
  end

  local texts, seen = {}, {}
  local descriptions = type(data.descriptions) == "table" and data.descriptions or {}
  for _, workspace in ipairs(sorted(descriptions)) do
    local entries = descriptions[workspace]
    if type(entries) == "table" then
      for _, name in ipairs(sorted(entries)) do
        local text = entries[name]
        if type(text) == "string" and text ~= "" and type(slots[name]) == "table" then
          seen[name] = seen[name] or {}
          if not seen[name][text] then
            seen[name][text] = true
            texts[name] = texts[name] or {}
            texts[name][#texts[name] + 1] = text
          end
        end
      end
    end
  end
  for name, list in pairs(texts) do
    if slots[name].description == nil then
      slots[name].description = table.concat(list, "; ")
    end
  end

  out.slots = next(slots) ~= nil and slots or out.slots
  if type(out.slots) == "table" then
    for key in pairs(out.slots) do
      if type(key) == "number" then
        out.slots[key] = nil
      end
    end
  end
  out.specs = next(specs) ~= nil and specs or nil
  out.descriptions = nil
  return out, true
end

-- Arrangements of before, read as desks and layouts.
--
-- Before, an arrangement was a monitor setup and its trees in one, with a
-- name per screen (a role), and `pinned` listed roles for every arrangement
-- (pinned screens are gone: M.unpin drops them):
--
--   arrangements = { docked = { screens = { laptop = "eDP-1", wide = "DP-1" },
--                               desks = { [3] = { wide = "h[left, main]" } } } },
--   pinned = { "laptop" },
--
-- Now a desk is the monitor setup and a layout the trees, by screen number
-- (1 the left-most):
--
--   desks = { docked = { monitors = { "eDP-1", "DP-1" }, layout = "docked" } },
--   layouts = { docked = { screens = 2, workspaces = { [3] = { [2] = "h[left, main]" } } } },
--
-- Each arrangement becomes a desk of the same name (its selectors, in screen
-- order) and a layout of its trees. Screen order is the monitors' left to
-- right when `monitors` (the connected ones, { name, description, serial,
-- x, y }) has every one of its screens; otherwise the roles' sort order,
-- the order slots.lua writes them in. Arrangements whose layouts come out
-- the same share one, named after the first of them.
local function before(a, b)
  return desk.order({ a, b })[1] == a and a ~= b
end

local function canonical(layout)
  return serialize.dump(layout)
end

-- The roles of an arrangement -> the connected monitor each finds, when
-- they are exactly the connected monitors; else nil.
local function desk_match(roles, screens, monitors)
  local selectors = {}
  for i, role in ipairs(roles) do
    selectors[i] = screens[role]
  end
  for _, selector in ipairs(selectors) do
    if type(selector) ~= "string" then
      return nil
    end
  end
  local found = desk.match(selectors, desk.usable(monitors))
  if not found then
    return nil
  end
  local out = {}
  for _, role in ipairs(roles) do
    out[role] = found[screens[role]]
  end
  return out
end

-- The data with its arrangements read as desks and layouts (a copy), and
-- whether it had to change. Data that already has desks or layouts is
-- left as it is (an `arrangements` beside them is config.validate's to
-- report).
function M.desks(data, monitors)
  local out = copy(data)
  if type(out) ~= "table" or out.arrangements == nil or out.desks ~= nil or out.layouts ~= nil then
    return out, false
  end
  if type(out.arrangements) ~= "table" then
    return out, false
  end
  local arrangements = out.arrangements
  local desks, layouts, by_text = {}, {}, {}
  for _, name in ipairs(sorted(arrangements)) do
    local entry = arrangements[name]
    if type(entry) ~= "table" then
      desks[name] = entry -- config.validate says what is wrong with it
    else
      local screens = type(entry.screens) == "table" and entry.screens or {}
      local roles = {}
      for _, role in ipairs(sorted(screens)) do
        roles[#roles + 1] = role
      end
      local found = monitors and desk_match(roles, screens, monitors)
      if found then
        table.sort(roles, function(a, b)
          return before(found[a], found[b])
        end)
      end
      local index, selectors = {}, {}
      for i, role in ipairs(roles) do
        index[role] = i
        selectors[i] = screens[role]
      end
      local workspaces = {}
      for n, branches in pairs(type(entry.desks) == "table" and entry.desks or {}) do
        if type(branches) == "table" then
          local trees = {}
          for role, text in pairs(branches) do
            trees[index[role] or role] = text -- an unknown role stays, for validate to report
          end
          workspaces[n] = trees
        else
          workspaces[n] = branches
        end
      end
      local layout = { screens = #roles, workspaces = next(workspaces) ~= nil and workspaces or nil }
      local text = canonical(layout)
      local shared = by_text[text]
      if not shared then
        shared = name
        by_text[text] = name
        layouts[name] = layout
      end
      desks[name] = { monitors = selectors, layout = shared }
    end
  end
  out.desks = desks
  out.layouts = layouts
  out.arrangements = nil
  out.pinned = nil
  return out, true
end

return M
