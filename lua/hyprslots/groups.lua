-- Accordions as Hyprland groups (docs/design.md §3, §6).
--
-- An accordion `a[x, y, z]` is realized as ONE Hyprland group holding the
-- windows of its slots; the slots layout then sees the group as a single
-- target and gives it the accordion's box. Group membership is changed only
-- from a deferred timer, never inside recalculate: anything that may have
-- changed membership (a window opening, closing or changing workspace, a
-- layout pass that sees an accordion split over several targets, a new
-- arrangement) calls schedule(), and the reconcile pass then plans and runs
-- the moves for every desk workspace.
--
-- plan() is pure: given the accordions of a workspace's tree and its windows,
-- it returns the moves that leave each accordion with two or more windows in
-- exactly one group of its own:
--
--   { op = "out",    window = address }                 -- leave its group
--   { op = "create", window = address }                 -- a new group of one
--   { op = "add",    window = address, into = address } -- join into's group
--
-- A group holding a member of an accordion is that accordion's (the first such
-- group wins; the rest give their members up); other windows in it are taken
-- out. A lone member is left as it is, and so is a group of windows with no
-- accordion slot.

local M = {}

local function group_key(group)
  return table.concat(group, ",")
end

-- accordions: list of member-slot lists, as tree.accordions returns.
-- windows: list of { address, slot = <slot in this tree, or nil>,
-- group = <member addresses in group order, or nil> }, in a stable order.
function M.plan(accordions, windows)
  local accordion_of_slot, rank = {}, {}
  for i, members in ipairs(accordions) do
    for j, slot in ipairs(members) do
      accordion_of_slot[slot] = i
      rank[slot] = j
    end
  end

  local accordion_of, wanted = {}, {}
  for i = 1, #accordions do
    wanted[i] = {}
  end
  for _, window in ipairs(windows) do
    local i = window.slot and accordion_of_slot[window.slot]
    if i then
      accordion_of[window.address] = i
      table.insert(wanted[i], window)
    end
  end
  for i = 1, #accordions do
    table.sort(wanted[i], function(a, b) return rank[a.slot] < rank[b.slot] end)
  end

  local ops = {}
  local owner_group = {} -- accordion -> group key
  local group_of = {} -- address -> group key, after the outs
  local seen = {}

  for _, window in ipairs(windows) do
    local group = window.group
    local key = group and group_key(group)
    if key and not seen[key] then
      seen[key] = true
      local owner
      for _, address in ipairs(group) do
        local i = accordion_of[address]
        if i and not owner_group[i] then
          owner = i
          break
        end
      end
      if owner then
        owner_group[owner] = key
      end
      for _, address in ipairs(group) do
        local i = accordion_of[address]
        if (owner and i ~= owner) or (not owner and i) then
          ops[#ops + 1] = { op = "out", window = address }
        else
          group_of[address] = key
        end
      end
    end
  end

  for i = 1, #accordions do
    local members = wanted[i]
    if #members >= 2 then
      local anchor
      for _, window in ipairs(members) do
        if owner_group[i] and group_of[window.address] == owner_group[i] then
          anchor = window.address
          break
        end
      end
      if not anchor then
        anchor = members[1].address
        ops[#ops + 1] = { op = "create", window = anchor }
      end
      for _, window in ipairs(members) do
        local address = window.address
        if address ~= anchor and not (owner_group[i] and group_of[address] == owner_group[i]) then
          ops[#ops + 1] = { op = "add", window = address, into = anchor }
        end
      end
    end
  end

  return ops
end

return M
