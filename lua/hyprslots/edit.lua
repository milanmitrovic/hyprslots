-- Edits to the editor-owned data file (slots.lua), and which parts of the
-- config the editor may change at all (docs/design.md §4, §9).
--
-- config.lua is real code: it receives the slots.lua table from load_data and
-- returns a config built from it. A config field is editable when config.lua
-- passed the data's own table straight through (the same table, by identity);
-- a field it built in code is read-only, because changing slots.lua would not
-- change it. Granularity: top-level keys, and one level below them
-- (`desks.<name>`, `layouts.<name>`, `specs.<workspace>`); the global
-- `slots` are one field, all or nothing.
--
-- Every edit returns a new data table; the one given is never mutated. Pure:
-- no `hl`, no I/O.

local serialize = require("hyprslots.serialize")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")

local M = {}

local WORKSPACES = 10
local SLOT_NAME = "^[%a_][%w_%-]*$" -- config.lua's rule for slot names

local function sorted_keys(t)
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

-- A deep copy of plain data.
function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, inner in pairs(value) do
    out[key] = M.copy(inner)
  end
  return out
end

-- Fields that are one whole: a slot list partly built in code is code's.
local WHOLE = { slots = true }

-- The config paths config.lua sets by code, sorted: "desks.work",
-- "layouts.office", "specs.4", "slots", "title_matching". `raw` is what
-- config.lua returned, `given` the table load_data("slots.lua") handed it
-- (nil when it loaded none).
function M.read_only(raw, given)
  local out = {}
  for _, key in ipairs(sorted_keys(raw)) do
    local value, source = raw[key], given and given[key]
    if source ~= nil and rawequal(value, source) then
      -- passed straight through: all of it is the data's
    elseif type(value) == "table" and type(source) == "table" and not WHOLE[key] then
      for _, sub in ipairs(sorted_keys(value)) do
        if not rawequal(value[sub], source[sub]) then
          out[#out + 1] = key .. "." .. tostring(sub)
        end
      end
    else
      out[#out + 1] = tostring(key)
    end
  end
  return out
end

-- Whether `section.name` (e.g. layouts.solo) is the data's to change.
function M.editable(read_only, section, name)
  local whole, one = section, section .. "." .. tostring(name)
  for _, path in ipairs(read_only) do
    if path == whole or path == one then
      return false
    end
  end
  return true
end

local function check_workspace(workspace)
  if math.type(workspace) ~= "integer" or workspace < 1 or workspace > WORKSPACES then
    return nil, "a workspace must be an integer from 1 to " .. WORKSPACES .. ", got " .. tostring(workspace)
  end
  return true
end

local function check_name(name, what)
  if type(name) ~= "string" or not name:match(SLOT_NAME) then
    return nil, string.format("a %s name must start with a letter or '_' and hold only letters, digits, '_' or '-', got '%s'",
      what, tostring(name))
  end
  return true
end

-- The data's global slots (name -> { description? }), never nil.
local function global_slots(data)
  return data and type(data.slots) == "table" and data.slots or {}
end

local function existing_slot(data, slot)
  if type(slot) ~= "string" or global_slots(data)[slot] == nil then
    return nil, string.format("no slot '%s' (add it in the editor's Layout tab, s then a)", tostring(slot))
  end
  return true
end

-- Spec text, normalized (trimmed), or nil and the grammar's complaint.
local function spec_text(text)
  local parsed, err = spec.parse(text)
  if not parsed then
    return nil, err
  end
  return parsed.text
end

-- A copy of a parsed tree with slot `old` called `new`.
function M.rename_leaf(node, old, new)
  local out = {}
  for key, value in pairs(node) do
    out[key] = value
  end
  if node.slot == old then
    out.slot = new
  end
  if node.children then
    out.children = {}
    for i, child in ipairs(node.children) do
      out.children[i] = M.rename_leaf(child, old, new)
    end
  end
  return out
end

-- A copy of a parsed tree without slot `name`: a split left with one child
-- is replaced by that child (taking the split's weight; a scroll branch
-- stays one), a container left with none goes too. Nil when nothing is left.
function M.remove_leaf(node, name)
  if node.slot ~= nil or node.children == nil then
    if node.slot == name then
      return nil
    end
    return M.copy(node)
  end
  local children = {}
  for _, child in ipairs(node.children) do
    local kept = M.remove_leaf(child, name)
    if kept then
      children[#children + 1] = kept
    end
  end
  if #children == 0 then
    return nil
  end
  if #children == 1 and not node.scroll then
    children[1].weight = node.weight
    return children[1]
  end
  local out = M.copy(node)
  out.children = children
  return out
end

local function gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

-- A parsed tree as text that is the same for every tree laid out the same:
-- each container's weights divided by their greatest common divisor (2:2 is
-- 1:1), the root's own weight left out.
local function shape(node, weighted)
  local text
  if node.children then
    local divisor = 0
    for _, child in ipairs(node.children) do
      divisor = gcd(child.weight or 1, divisor)
    end
    local parts = {}
    for i, child in ipairs(node.children) do
      parts[i] = shape(child, not node.scroll and math.tointeger((child.weight or 1) // math.max(divisor, 1)))
    end
    local kind = node.scroll and "scroll" .. (node.width and ":" .. serialize.width(node.width) or "") or node.split
    text = kind .. "[" .. table.concat(parts, ", ") .. "]"
  else
    text = node.overflow and tree.OVERFLOW or node.slot
  end
  return weighted and text .. ":" .. weighted or text
end

-- Whether a workspace's own tree on a screen (`text`, nil for none) is the
-- layout's default tree there (`default`, nil for none) with some of its
-- slots missing, and nothing else: the same containers nested the same way,
-- the same slots in the same order, the same overflow leaf, and the shares
-- pruning those slots leaves (as edit.remove_leaf: a split left with one
-- child is that child, with the split's share). Empty slots close up, so
-- such a tree lays its windows out as the default one does, and the
-- workspace may as well show the default. A tree that does not parse is no
-- match.
function M.redundant_with_default(text, default)
  local own = text ~= nil and tree.parse(text) or nil
  local base = default ~= nil and tree.parse(default) or nil
  if (text ~= nil and not own) or (default ~= nil and not base) then
    return false
  end
  if not base then
    return own == nil
  end
  local mine = {}
  for _, slot in ipairs(own and tree.slots(own) or {}) do
    mine[slot] = true
  end
  local theirs = {}
  local pruned = base
  for _, slot in ipairs(tree.slots(base)) do
    theirs[slot] = true
    if not mine[slot] then
      pruned = pruned and M.remove_leaf(pruned, slot)
    end
  end
  for slot in pairs(mine) do
    if not theirs[slot] then
      return false
    end
  end
  if not own or not pruned then
    return own == nil and pruned == nil
  end
  return shape(own) == shape(pruned)
end

-- Every tree table of every layout: its default trees and each workspace's
-- own, as (layout name, workspace or "default", screen -> text table).
local function each_trees(data, fn)
  for _, name in ipairs(sorted_keys(type(data.layouts) == "table" and data.layouts or {})) do
    local entry = data.layouts[name]
    if type(entry) == "table" then
      if type(entry.default) == "table" then
        fn(name, "default", entry.default, entry)
      end
      local workspaces = type(entry.workspaces) == "table" and entry.workspaces or {}
      for _, n in ipairs(sorted_keys(workspaces)) do
        if type(workspaces[n]) == "table" then
          fn(name, n, workspaces[n], entry)
        end
      end
    end
  end
end

-- Rewrite every tree of every layout (default and per workspace) with
-- fn(node) -> node or nil (nil drops the branch). Trees that do not parse
-- are left as they are (config.lua's validation reports them). A
-- workspace's trees are kept even when none is left (they still replace the
-- default ones); empty default trees go.
local function rewrite_trees(out, fn)
  each_trees(out, function(_, n, trees, entry)
    for screen, text in pairs(trees) do
      local node = tree.parse(text)
      if node then
        local changed = fn(node)
        trees[screen] = changed and serialize.tree(changed) or nil
      end
    end
    if n == "default" and next(trees) == nil then
      entry.default = nil
    end
  end)
end

-- Rewrite every workspace's spec for slot `old`: moved to `new`, or dropped when
-- `new` is nil. A workspace left with no specs goes.
local function rewrite_specs(out, old, new)
  local specs = type(out.specs) == "table" and out.specs or {}
  for workspace, entries in pairs(specs) do
    if type(entries) == "table" and entries[old] ~= nil then
      if new ~= nil then
        entries[new] = entries[old]
      end
      entries[old] = nil
      if next(entries) == nil then
        specs[workspace] = nil
      end
    end
  end
  if out.specs ~= nil and next(specs) == nil then
    out.specs = nil
  end
end

-- Where slot `name` is used: { trees = { "<layout>/<workspace>/<screen>",
-- ... } (workspace "default" for the default trees), specs = { workspace,
-- ... } }, both sorted.
function M.slot_uses(data, name)
  local trees, specs = {}, {}
  each_trees(data, function(layout, n, branches)
    for _, screen in ipairs(sorted_keys(branches)) do
      local node = tree.parse(branches[screen])
      if node then
        for _, slot in ipairs(tree.slots(node)) do
          if slot == name then
            trees[#trees + 1] = layout .. "/" .. tostring(n) .. "/" .. tostring(screen)
          end
        end
      end
    end
  end)
  local all = type(data.specs) == "table" and data.specs or {}
  for _, workspace in ipairs(sorted_keys(all)) do
    if type(all[workspace]) == "table" and all[workspace][name] ~= nil then
      specs[#specs + 1] = workspace
    end
  end
  return { trees = trees, specs = specs }
end

-- The data with a new global slot (description optional).
function M.add_slot(data, name, description)
  local ok, name_err = check_name(name, "slot")
  if not ok then
    return nil, name_err
  end
  if global_slots(data)[name] ~= nil then
    return nil, string.format("there is a slot '%s' already", name)
  end
  if description ~= nil and type(description) ~= "string" then
    return nil, "a description must be text"
  end
  local out = M.copy(data or {})
  out.slots = type(out.slots) == "table" and out.slots or {}
  out.slots[name] = (description ~= nil and description ~= "") and { description = description } or {}
  return out
end

-- The data without a global slot: gone from every tree of every workspace that
-- placed it (a branch it was all of goes too) and from every workspace's specs.
function M.remove_slot(data, name)
  local ok, err = existing_slot(data, name)
  if not ok then
    return nil, err
  end
  local out = M.copy(data)
  out.slots[name] = nil
  rewrite_trees(out, function(node) return M.remove_leaf(node, name) end)
  rewrite_specs(out, name, nil)
  return out
end

-- The data with a global slot renamed: in every tree of every layout
-- (aerolayout's rename_slot_everywhere) and in every workspace's specs; its
-- description follows.
function M.rename_slot(data, old, new)
  local ok, err = existing_slot(data, old)
  if not ok then
    return nil, err
  end
  local named, name_err = check_name(new, "slot")
  if not named then
    return nil, name_err
  end
  if new == old then
    return M.copy(data)
  end
  if data.slots[new] ~= nil then
    return nil, string.format("there is a slot '%s' already", new)
  end
  local out = M.copy(data)
  out.slots[new], out.slots[old] = out.slots[old], nil
  rewrite_trees(out, function(node) return M.rename_leaf(node, old, new) end)
  rewrite_specs(out, old, new)
  return out
end

-- The data with a global slot's description set; "" (or nil) removes it.
function M.describe_slot(data, name, text)
  local ok, err = existing_slot(data, name)
  if not ok then
    return nil, err
  end
  if text ~= nil and type(text) ~= "string" then
    return nil, "a description must be text"
  end
  local out = M.copy(data)
  local entry = type(out.slots[name]) == "table" and out.slots[name] or {}
  entry.description = (text ~= nil and text ~= "") and text or nil
  out.slots[name] = entry
  return out
end

-- The data with the app that fills slot `slot` on workspace `workspace` set (spec
-- text, normalized), replacing the workspace's spec for it if it had one.
function M.set_spec(data, workspace, slot, text)
  local ok, err = check_workspace(workspace)
  if not ok then
    return nil, err
  end
  local defined, slot_err = existing_slot(data, slot)
  if not defined then
    return nil, slot_err
  end
  local normalized, spec_err = spec_text(text)
  if not normalized then
    return nil, spec_err
  end
  local out = M.copy(data)
  out.specs = type(out.specs) == "table" and out.specs or {}
  out.specs[workspace] = type(out.specs[workspace]) == "table" and out.specs[workspace] or {}
  out.specs[workspace][slot] = normalized
  return out
end

-- The data without workspace `workspace`'s spec for slot `slot` (the global slot and
-- the trees stay; a window can still be put there by hand).
function M.clear_spec(data, workspace, slot)
  local ok, err = check_workspace(workspace)
  if not ok then
    return nil, err
  end
  local entries = data and type(data.specs) == "table" and data.specs[workspace]
  if type(entries) ~= "table" or type(slot) ~= "string" or entries[slot] == nil then
    return nil, string.format("workspace %s has no spec for '%s'", tostring(workspace), tostring(slot))
  end
  local out = M.copy(data)
  out.specs[workspace][slot] = nil
  if next(out.specs[workspace]) == nil then
    out.specs[workspace] = nil
  end
  return out
end

-- Desks and layouts -----------------------------------------------------------

local MAX_SCREENS = 10

local function entry_name(name, what)
  if type(name) ~= "string" or name:match("^%s*$") then
    return nil, "a " .. what .. " needs a name"
  end
  if name:find("/", 1, true) or name ~= name:match("^%s*(.-)%s*$") then
    return nil, "a " .. what .. " name has no '/' and no spaces around it, got '" .. name .. "'"
  end
  return name
end

local function section(data, key)
  return data and type(data[key]) == "table" and data[key] or {}
end

local function desk_entry(data, name)
  local entry = section(data, "desks")[name]
  if type(entry) ~= "table" then
    return nil, "no desk '" .. tostring(name) .. "'"
  end
  return entry
end

local function layout_entry(data, name)
  local entry = section(data, "layouts")[name]
  if type(entry) ~= "table" then
    return nil, "no layout '" .. tostring(name) .. "'"
  end
  return entry
end

local function screen_count(entry)
  return math.type(entry.screens) == "integer" and entry.screens or 0
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

-- The desks that use layout `name`, sorted.
function M.layout_users(data, name)
  local out = {}
  for _, desk in ipairs(sorted_keys(section(data, "desks"))) do
    local entry = data.desks[desk]
    if type(entry) == "table" and entry.layout == name then
      out[#out + 1] = desk
    end
  end
  return out
end

-- A copy of a monitors list, or nil and why it is no good.
local function monitors_copy(monitors)
  if type(monitors) ~= "table" or monitors[1] == nil then
    return nil, "a desk must list at least one monitor (a description, serial or connector)"
  end
  local out, seen = {}, {}
  for i, selector in ipairs(monitors) do
    if type(selector) ~= "string" or selector == "" then
      return nil, "monitor " .. i .. " needs a selector (a monitor description, serial or connector)"
    end
    if seen[selector] then
      return nil, "'" .. selector .. "' is listed twice"
    end
    seen[selector] = true
    out[i] = selector
  end
  return out
end

local function check_fits(data, layout, count)
  local entry, err = layout_entry(data, layout)
  if not entry then
    return nil, err
  end
  if screen_count(entry) ~= count then
    return nil, string.format("layout '%s' is for %s, and the desk has %s", layout, plural(screen_count(entry), "screen"),
      plural(count, "monitor"))
  end
  return entry
end

-- The data with a new desk for `monitors` (selectors) using `layout`.
function M.add_desk(data, name, monitors, layout)
  local ok, err = entry_name(name, "desk")
  if not ok then
    return nil, err
  end
  if section(data, "desks")[name] ~= nil then
    return nil, "a desk called '" .. name .. "' already exists"
  end
  local copied, monitors_err = monitors_copy(monitors)
  if not copied then
    return nil, monitors_err
  end
  local fits, fit_err = check_fits(data, layout, #copied)
  if not fits then
    return nil, fit_err
  end
  local out = M.copy(data or {})
  out.desks = type(out.desks) == "table" and out.desks or {}
  out.desks[name] = { monitors = copied, layout = layout }
  return out
end

function M.rename_desk(data, old, new)
  local entry, err = desk_entry(data, old)
  if not entry then
    return nil, err
  end
  local ok, name_err = entry_name(new, "desk")
  if not ok then
    return nil, name_err
  end
  if new == old then
    return M.copy(data)
  end
  if data.desks[new] ~= nil then
    return nil, "a desk called '" .. new .. "' already exists"
  end
  local out = M.copy(data)
  out.desks[new], out.desks[old] = out.desks[old], nil
  return out
end

function M.delete_desk(data, name)
  local entry, err = desk_entry(data, name)
  if not entry then
    return nil, err
  end
  local out = M.copy(data)
  out.desks[name] = nil
  return out
end

-- The data with desk `name` using layout `layout` (one for as many screens
-- as the desk has monitors).
function M.set_desk_layout(data, name, layout)
  local entry, err = desk_entry(data, name)
  if not entry then
    return nil, err
  end
  local fits, fit_err = check_fits(data, layout, type(entry.monitors) == "table" and #entry.monitors or 0)
  if not fits then
    return nil, fit_err
  end
  local out = M.copy(data)
  out.desks[name].layout = layout
  return out
end

-- The data with a new layout for `screens` screens: empty, or with these
-- default trees (screen -> text).
function M.add_layout(data, name, screens, default)
  local ok, err = entry_name(name, "layout")
  if not ok then
    return nil, err
  end
  if section(data, "layouts")[name] ~= nil then
    return nil, "a layout called '" .. name .. "' already exists"
  end
  if math.type(screens) == "float" and screens == math.floor(screens) then
    screens = math.tointeger(screens)
  end
  if math.type(screens) ~= "integer" or screens < 1 or screens > MAX_SCREENS then
    return nil, "a layout is for 1 to " .. MAX_SCREENS .. " screens, got " .. tostring(screens)
  end
  local out = M.copy(data or {})
  out.layouts = type(out.layouts) == "table" and out.layouts or {}
  out.layouts[name] = { screens = screens, default = default and next(default) ~= nil and M.copy(default) or nil }
  return out
end

-- The data with layout `source` copied as `name`.
function M.copy_layout(data, source, name)
  local entry, err = layout_entry(data, source)
  if not entry then
    return nil, err
  end
  local ok, name_err = entry_name(name, "layout")
  if not ok then
    return nil, name_err
  end
  if data.layouts[name] ~= nil then
    return nil, "a layout called '" .. name .. "' already exists"
  end
  local out = M.copy(data)
  out.layouts[name] = M.copy(entry)
  return out
end

-- The data with layout `old` called `new`; the desks using it follow.
function M.rename_layout(data, old, new)
  local entry, err = layout_entry(data, old)
  if not entry then
    return nil, err
  end
  local ok, name_err = entry_name(new, "layout")
  if not ok then
    return nil, name_err
  end
  if new == old then
    return M.copy(data)
  end
  if data.layouts[new] ~= nil then
    return nil, "a layout called '" .. new .. "' already exists"
  end
  local out = M.copy(data)
  out.layouts[new], out.layouts[old] = out.layouts[old], nil
  for _, desk in pairs(section(out, "desks")) do
    if type(desk) == "table" and desk.layout == old then
      desk.layout = new
    end
  end
  return out
end

-- The data without layout `name`. Refused while desks use it, unless
-- `remap` names a layout for as many screens, which they then use.
function M.delete_layout(data, name, remap)
  local entry, err = layout_entry(data, name)
  if not entry then
    return nil, err
  end
  local users = M.layout_users(data, name)
  if #users > 0 then
    if remap == nil then
      return nil, string.format("layout '%s' is used by %s %s; delete it with remap: <another layout for %s>",
        name, #users == 1 and "desk" or "desks", table.concat(users, ", "), plural(screen_count(entry), "screen"))
    end
    if remap == name then
      return nil, "cannot remap layout '" .. name .. "' to itself"
    end
    local target, target_err = layout_entry(data, remap)
    if not target then
      return nil, target_err
    end
    if screen_count(target) ~= screen_count(entry) then
      return nil, string.format("layout '%s' is for %s, and '%s' for %s", remap, plural(screen_count(target), "screen"),
        name, plural(screen_count(entry), "screen"))
    end
  end
  local out = M.copy(data)
  out.layouts[name] = nil
  for _, desk in ipairs(users) do
    out.desks[desk].layout = remap
  end
  return out
end

-- Layout trees ----------------------------------------------------------------
--
-- A layout holds a tree per screen for each workspace that has its own
-- (`workspaces[n][screen]`), and default trees (`default[screen]`) for the
-- workspaces with none of their own. `n` is a workspace 1 to 10 or
-- "default".

local function check_workspace_or_default(n)
  if n == "default" then
    return true
  end
  return check_workspace(n)
end

local function as_screen(screen)
  if type(screen) == "string" and screen:match("^%d+$") then
    return math.tointeger(tonumber(screen))
  end
  if math.type(screen) == "float" and screen == math.floor(screen) then
    return math.tointeger(screen)
  end
  return screen
end

local function check_screen(name, entry, screen)
  local count = screen_count(entry)
  if math.type(screen) ~= "integer" or screen < 1 or screen > count then
    return nil, string.format("layout '%s' has screens 1 to %d, got %s", name, count, tostring(screen))
  end
  return true
end

-- The table of trees (screen -> text) workspace n's edits go into, made
-- when missing: a workspace with none of its own starts from a copy of the
-- default ones, which it then replaces whole.
local function trees_of(entry, n)
  if n == "default" then
    entry.default = type(entry.default) == "table" and entry.default or {}
    return entry.default
  end
  entry.workspaces = type(entry.workspaces) == "table" and entry.workspaces or {}
  if type(entry.workspaces[n]) ~= "table" then
    entry.workspaces[n] = type(entry.default) == "table" and M.copy(entry.default) or {}
  end
  return entry.workspaces[n]
end

-- The data with a layout's tree for workspace n (or "default") on a screen
-- set to `text` (normalized). Returns the new data, or nil and why not.
function M.set_tree(data, layout, n, screen, text)
  local entry, err = layout_entry(data, layout)
  if not entry then
    return nil, err
  end
  local ok, ws_err = check_workspace_or_default(n)
  if not ok then
    return nil, ws_err
  end
  screen = as_screen(screen)
  local fits, screen_err = check_screen(layout, entry, screen)
  if not fits then
    return nil, screen_err
  end
  local node, parse_err = tree.parse(text)
  if not node then
    return nil, parse_err
  end
  if type(data.slots) == "table" then
    for _, slot in ipairs(tree.slots(node)) do
      if data.slots[slot] == nil then
        return nil, string.format("no slot '%s' (add it in the editor's Layout tab, s then a)", slot)
      end
    end
  end
  local out = M.copy(data)
  trees_of(out.layouts[layout], n)[screen] = serialize.tree(node)
  return out
end

-- The data with several of a workspace's trees set at once (`trees`:
-- screen -> text), so a slot can move from one screen to another in one
-- edit. Returns the new data, or nil and why not (the first refusal).
function M.set_trees(data, layout, n, trees)
  if type(trees) ~= "table" or next(trees) == nil then
    return nil, "no trees to set: give \"trees\" as an object of screen -> tree"
  end
  local out = data
  for _, screen in ipairs(sorted_keys(trees)) do
    local err
    out, err = M.set_tree(out, layout, n, screen, trees[screen])
    if not out then
      return nil, err
    end
  end
  return out
end

-- The slots a set of trees (screen -> text) places, as a set.
local function placed_slots(trees)
  local out = {}
  for _, text in pairs(trees or {}) do
    local node = tree.parse(text)
    for _, slot in ipairs(node and tree.slots(node) or {}) do
      out[slot] = true
    end
  end
  return out
end

-- Why workspace n's own trees in a layout must stay, or nil when the shared
-- (default) ones would lay it out the same: each screen's tree is the shared
-- one with slots missing (M.redundant_with_default), and the workspace has
-- no spec for a slot the shared trees place and its own leave out (that spec
-- would start filling it).
local function override_needed(data, entry, n)
  local own = entry.workspaces[n]
  local default = type(entry.default) == "table" and entry.default or {}
  for screen = 1, screen_count(entry) do
    if not M.redundant_with_default(own[screen], default[screen]) then
      return string.format("screen %d's tree is not the shared one with slots left out", screen)
    end
  end
  local specs = section(data, "specs")[n]
  local mine, shared = placed_slots(own), placed_slots(default)
  local woken = {}
  for _, slot in ipairs(sorted_keys(type(specs) == "table" and specs or {})) do
    if shared[slot] and not mine[slot] then
      woken[#woken + 1] = slot
    end
  end
  if #woken > 0 then
    return string.format("it has a spec for %s, which its own trees leave out and the shared ones place",
      table.concat(woken, ", "))
  end
  return nil
end

-- The data with every workspace's own trees in layout `layout` dropped that
-- the layout's shared (default) trees would lay out the same (see
-- override_needed): the copies the cutover made of one tree, cut down to the
-- slots each workspace had. Returns the new data and { folded = {
-- workspaces }, kept = { { workspace, reason } } } (both by workspace), or
-- nil and why not.
function M.fold_trees(data, layout)
  local entry, err = layout_entry(data, layout)
  if not entry then
    return nil, err
  end
  local out = M.copy(data)
  local target = out.layouts[layout]
  local report = { folded = {}, kept = {} }
  local workspaces = type(target.workspaces) == "table" and target.workspaces or {}
  for _, n in ipairs(sorted_keys(workspaces)) do
    if type(workspaces[n]) == "table" then
      local reason = override_needed(out, target, n)
      if reason then
        report.kept[#report.kept + 1] = { workspace = n, reason = reason }
      else
        workspaces[n] = nil
        report.folded[#report.folded + 1] = n
      end
    end
  end
  if target.workspaces ~= nil and next(workspaces) == nil then
    target.workspaces = nil
  end
  return out, report
end

-- The data with workspace n's own trees in layout `layout` dropped, so it
-- shows the shared (default) ones; with `screen`, only that screen's tree
-- goes back to the shared one, and the rest once they are the shared ones
-- too. Returns the new data, or nil and why not.
function M.drop_override(data, layout, n, screen)
  local entry, err = layout_entry(data, layout)
  if not entry then
    return nil, err
  end
  local ok, ws_err = check_workspace(n)
  if not ok then
    return nil, ws_err
  end
  if screen ~= nil then
    screen = as_screen(screen)
    local fits, screen_err = check_screen(layout, entry, screen)
    if not fits then
      return nil, screen_err
    end
  end
  if type(entry.workspaces) ~= "table" or type(entry.workspaces[n]) ~= "table" then
    return nil, string.format("workspace %d uses the shared trees already in layout '%s'", n, layout)
  end
  local out = M.copy(data)
  local target = out.layouts[layout]
  local default = type(target.default) == "table" and target.default or {}
  if screen ~= nil then
    target.workspaces[n][screen] = default[screen]
  end
  if screen == nil or serialize.dump(target.workspaces[n]) == serialize.dump(default) then
    target.workspaces[n] = nil
  end
  if next(target.workspaces) == nil then
    target.workspaces = nil
  end
  return out
end

-- The data with a layout's tree for workspace n (or "default") on a screen
-- put back to the one `saved` (the data as slots.lua holds it) gives it:
-- the workspace's own tree there, else (it has none of its own there) the
-- saved default one, or no tree at all. A workspace whose trees are then the
-- saved default ones, and has none of its own in `saved`, goes back to
-- using the default ones. Returns the new data, or nil and why not.
function M.reset_tree(data, saved, layout, n, screen)
  local entry, err = layout_entry(data, layout)
  if not entry then
    return nil, err
  end
  local ok, ws_err = check_workspace_or_default(n)
  if not ok then
    return nil, ws_err
  end
  screen = as_screen(screen)
  local fits, screen_err = check_screen(layout, entry, screen)
  if not fits then
    return nil, screen_err
  end
  local saved_entry = section(saved, "layouts")[layout]
  saved_entry = type(saved_entry) == "table" and saved_entry or {}
  local saved_default = type(saved_entry.default) == "table" and saved_entry.default or {}
  local saved_own = n ~= "default" and type(saved_entry.workspaces) == "table" and saved_entry.workspaces[n] or nil
  saved_own = type(saved_own) == "table" and saved_own or nil
  local text
  if n == "default" then
    text = saved_default[screen]
  elseif saved_own then
    text = saved_own[screen]
  else
    text = saved_default[screen]
  end

  local out = M.copy(data)
  local target = out.layouts[layout]
  local has_own = n ~= "default" and type(target.workspaces) == "table" and type(target.workspaces[n]) == "table"
  if n ~= "default" and not has_own and text == (type(target.default) == "table" and target.default[screen] or nil) then
    return out -- it shows the default trees, and the reset changes none of them
  end
  local trees = trees_of(target, n)
  trees[screen] = text
  if n == "default" then
    if next(trees) == nil then
      target.default = nil
    end
  elseif not saved_own and serialize.dump(trees) == serialize.dump(type(target.default) == "table" and target.default or {}) then
    target.workspaces[n] = nil
    if next(target.workspaces) == nil then
      target.workspaces = nil
    end
  end
  return out
end

return M
