-- The engine's api for the editor and the e2e tests (docs/design.md §9):
--
--   hyprctl repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")'
--   hyprctl repl 'return hyprslots.api.state()'
--
-- Every reply is a JSON string: { "ok": true, ... } or { "ok": false, "error": "..." }.
-- Nothing here raises into Hyprland.

local json = require("hyprslots.dkjson")
local desks = require("hyprslots.desks")

local M = {}

local OBJECT = { __jsontype = "object" }

local function object(t)
  return setmetatable(t or {}, OBJECT)
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
  return {
    ok = true,
    refused = engine.refused,
    config_error = engine.config_error,
    arrangement = engine.active and engine.active.name or nil,
    screens = screens,
    workspaces = workspaces,
    assignments = assignments,
    log_seq = engine.log.seq,
  }
end

local handlers = {}

function handlers.state(engine)
  return M.snapshot(engine)
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
