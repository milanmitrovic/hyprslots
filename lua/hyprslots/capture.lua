-- Capture: turn what is on screen into a layout (docs/design.md §9,
-- Capture). The api's `capture` reads the windows of a workspace on every
-- screen of the active desk and, in one edit, makes a global slot for each
-- window no slot holds (named after its app), records each screen's
-- arrangement as its tree and gives each window's slot the window's spec on
-- that workspace. This is its pure half: the names, the trees and the
-- plan; capture_apply.lua gathers the windows and applies it. No `hl`, no I/O.

local edit = require("hyprslots.edit")
local record = require("hyprslots.record")
local spec = require("hyprslots.spec")
local tree = require("hyprslots.tree")
local util = require("hyprslots.util")

local M = {}

-- A slot name is at most this long: names are short, as the picture and the
-- prompts show them.
M.MAX_NAME = 16

-- A tiled split snaps to an arrangement of whole weights 1 to 5 (the Layout
-- picture's divider drags, Layout.arrangements) when one puts every child
-- within this share of the split of where it was measured; else record.lua's
-- own snapping, which keeps any ratio.
M.SNAP = 0.03
local MAX_WEIGHT = 5
local MAX_CHILDREN = 6 -- 5^6 arrangements at most; more children snap as record does

-- What an app's class says before its name ("google-chrome": chrome) and
-- after it ("brave-browser": brave).
local VENDORS = { "google-", "microsoft-", "jetbrains-" }
local SUFFIXES = { "-browser", "-desktop" }

local function trimmed(text)
  return (text:gsub("^[-_]+", ""):gsub("[-_]+$", ""))
end

-- The slot name for a window of `class`: the class's last dot-separated
-- part (a reverse-domain id's app: com.mitchellh.ghostty is ghostty), lower
-- case, without a vendor before it or "-browser" after it, made a valid slot
-- name (letters, digits, '_' and '-', a letter or '_' first) and short.
function M.slot_name(class)
  local name = type(class) == "string" and class or ""
  local last = name:match("([^%.]+)$")
  if name:find(".", 1, true) and last then
    name = last
  end
  name = name:lower()
  for _, vendor in ipairs(VENDORS) do
    if name:sub(1, #vendor) == vendor and #name > #vendor then
      name = name:sub(#vendor + 1)
    end
  end
  for _, suffix in ipairs(SUFFIXES) do
    if name:sub(-#suffix) == suffix and #name > #suffix then
      name = name:sub(1, -#suffix - 1)
    end
  end
  name = trimmed(name:gsub("[^%w_-]+", "_"):gsub("_+", "_"))
  if name == "" then
    return "app"
  end
  if not name:match("^[%a_]") then
    name = "app-" .. name
  end
  return trimmed(name:sub(1, M.MAX_NAME))
end

-- Every arrangement of `n` children, weights 1 to 5 divided by their gcd,
-- each once (computed once per count).
local arrangements = {}
local function arrangements_of(n)
  if arrangements[n] then
    return arrangements[n]
  end
  local out, seen, current = {}, {}, {}
  local function walk(i)
    if i > n then
      local common = 0
      for _, w in ipairs(current) do
        common = util.gcd(common, w)
      end
      local reduced = {}
      for j, w in ipairs(current) do
        reduced[j] = w // common
      end
      local key = table.concat(reduced, ":")
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = reduced
      end
      return
    end
    for w = 1, MAX_WEIGHT do
      current[i] = w
      walk(i + 1)
    end
  end
  walk(1)
  arrangements[n] = out
  return out
end

-- Integer weights for a split's measured extents: the 1 to 5 arrangement
-- nearest them (the largest share off by at most M.SNAP; ties to the
-- smaller weights), else record.weights.
function M.weights(extents)
  local n = #extents
  if n >= 2 and n <= MAX_CHILDREN then
    local total = 0
    for _, extent in ipairs(extents) do
      total = total + extent
    end
    if total > 0 then
      local best, best_err, best_sum
      for _, candidate in ipairs(arrangements_of(n)) do
        local sum = 0
        for _, w in ipairs(candidate) do
          sum = sum + w
        end
        local err = 0
        for i, w in ipairs(candidate) do
          err = math.max(err, math.abs(w / sum - extents[i] / total))
        end
        if best == nil or err < best_err - 1e-9 or (math.abs(err - best_err) <= 1e-9 and sum < best_sum) then
          best, best_err, best_sum = candidate, err, sum
        end
      end
      if best_err <= M.SNAP then
        local out = {}
        for i, w in ipairs(best) do
          out[i] = w
        end
        return out
      end
    end
  end
  return record.weights(extents)
end

-- A scroll branch's columns are half the screen when they were measured
-- at most this wide, else full (the editor's t: scroll half, scroll full).
M.HALF_WIDTH = 0.75

-- The windows of a screen in the order their slots are named and, on a
-- scroll branch, their columns go: a scrolling screen's by column (then by
-- place in it), a tiled one's left to right, then top to bottom.
local function ordered(screen)
  local out = {}
  for i, window in ipairs(screen.windows or {}) do
    out[i] = window
  end
  table.sort(out, function(a, b)
    if screen.scroll then
      if (a.column or 0) ~= (b.column or 0) then
        return (a.column or 0) < (b.column or 0)
      end
      if (a.row or 0) ~= (b.row or 0) then
        return (a.row or 0) < (b.row or 0)
      end
    else
      local ab, bb = a.box or {}, b.box or {}
      if (ab.x or 0) ~= (bb.x or 0) then
        return (ab.x or 0) < (bb.x or 0)
      end
      if (ab.y or 0) ~= (bb.y or 0) then
        return (ab.y or 0) < (bb.y or 0)
      end
    end
    return tostring(a.address) < tostring(b.address)
  end)
  return out
end

-- The plan for capturing workspace `input.workspace` (pure):
--
--   input.slots         the global slots (name -> entry)
--   input.specs         the workspace's specs, parsed (slot -> spec.parse)
--   input.title_matching  spec.title_matching's, for the windows' specs
--   input.assignments   address -> { workspace, slot }: who holds what
--   input.screens[i]    { windows = { { address, class, title, box,
--                       column?, row?, column_width? } }, scroll (the screen
--                       scrolls), current (its tree in force, parsed, or nil) }
--
-- Each window takes, in order: the slot it holds on the workspace; else a
-- free slot whose spec there matches it; else a slot named after its app
-- (slot_name, then -2, -3...): one the workspace neither fills nor gives a
-- spec, or a new one. A slot is free when no window outside the capture
-- (a floating one, say) holds it on the workspace. Each screen with windows
-- gets their tree (a tiled screen record.lua's guillotine cuts, its ratios
-- snapped by M.weights; a scrolling one a scroll branch in column order, the
-- width its tree had or else as wide as its columns), followed by the slots
-- its tree had that no window fills; one without windows keeps its tree,
-- less the slots captured. Returns
--
--   { trees = { [screen] = node or false (no tree) }, new_slots = { names },
--     specs = { slot -> spec text to set }, assign = { address -> slot },
--     windows = { { address, class, slot, spec, new } in order } }
--
-- or nil and why not (no windows, windows that overlap).
function M.plan(input)
  local n = input.workspace
  local slots = input.slots or {}
  local specs = input.specs or {}
  local assignments = input.assignments or {}
  local tm = input.title_matching

  local captured = {}
  local any = false
  for _, screen in ipairs(input.screens) do
    for _, window in ipairs(screen.windows or {}) do
      captured[window.address] = true
      any = true
    end
  end
  if not any then
    return nil, "no windows on workspace " .. tostring(n) .. " to capture"
  end

  -- Slots someone outside the capture holds on the workspace.
  local held = {}
  for address, a in pairs(assignments) do
    if a.workspace == n and not captured[address] then
      held[a.slot] = true
    end
  end
  local used, created = {}, {}
  local out = { trees = {}, new_slots = {}, specs = {}, assign = {}, windows = {} }

  local function free_existing(name)
    return slots[name] ~= nil and not held[name] and not used[name] and specs[name] == nil
  end

  local function take(window, slot, is_new)
    used[slot] = true
    out.assign[window.address] = slot
    local text = spec.from_window(window, tm)
    local current = specs[slot]
    if current and spec.match(current, window) then
      text = nil -- the workspace's spec already names it
    end
    if text then
      out.specs[slot] = text
    end
    out.windows[#out.windows + 1] = { address = window.address, class = window.class, title = window.title,
      slot = slot, spec = text or (current and current.text), new = is_new or false }
  end

  local order = {}
  for i, screen in ipairs(input.screens) do
    order[i] = ordered(screen)
  end

  -- First the windows that hold a slot or match one, so a name never takes
  -- a slot a later window holds.
  for _, windows in ipairs(order) do
    for _, window in ipairs(windows) do
      local a = assignments[window.address]
      if a and a.workspace == n and slots[a.slot] ~= nil and not used[a.slot] then
        take(window, a.slot)
      end
    end
  end
  for _, windows in ipairs(order) do
    for _, window in ipairs(windows) do
      if not out.assign[window.address] then
        local names = {}
        for name in pairs(specs) do
          names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
          if slots[name] ~= nil and not held[name] and not used[name] and spec.match(specs[name], window) then
            take(window, name)
            break
          end
        end
      end
    end
  end
  for _, windows in ipairs(order) do
    for _, window in ipairs(windows) do
      if not out.assign[window.address] then
        local base = M.slot_name(window.class)
        local name, k = base, 1
        while not (free_existing(name) or (slots[name] == nil and not created[name])) do
          k = k + 1
          name = base .. "-" .. k
        end
        local is_new = slots[name] == nil
        if is_new then
          created[name] = true
          out.new_slots[#out.new_slots + 1] = name
        end
        take(window, name, is_new)
      end
    end
  end

  for i, screen in ipairs(input.screens) do
    local windows = order[i]
    local current = screen.current
    local node
    if #windows > 0 then
      if screen.scroll then
        local width = current and current.scroll and current.width or nil
        if not (current and current.scroll) then
          local measured = windows[1].column_width
          width = (type(measured) == "number" and measured <= M.HALF_WIDTH) and 0.5 or nil
        end
        node = { scroll = true, width = width, weight = 1, children = {} }
        for j, window in ipairs(windows) do
          node.children[j] = { slot = out.assign[window.address], weight = 1 }
        end
      else
        local boxes = {}
        for _, window in ipairs(windows) do
          boxes[out.assign[window.address]] = window.box
        end
        local err
        node, err = record.tree(boxes, M.weights)
        if not node then
          return nil, "cannot capture workspace " .. tostring(n) .. ": " .. err
        end
      end
      local kept = {}
      for _, slot in ipairs(current and tree.slots(current) or {}) do
        if not used[slot] and slots[slot] ~= nil then
          kept[#kept + 1] = slot
        end
      end
      node = tree.append(node, kept)
    elseif current then
      node = current
      for slot in pairs(used) do
        node = node and edit.remove_leaf(node, slot)
      end
    end
    out.trees[i] = node or false
  end
  return out
end

return M
