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
-- `data` returns the second shape for either: every slot name some workspace
-- had becomes a global slot, each workspace's specs move under `specs`
-- unchanged, and a slot's descriptions move onto it (every different one, in
-- workspace order, joined with "; "; one for a slot no workspace has is
-- dropped). What it cannot read is carried over as it is, for config.validate
-- to report. Pure; the table given is never changed.

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

-- The data in the global shape (a copy), and whether it had to change.
function M.data(data)
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

return M
