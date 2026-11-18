-- A ring buffer of what hyprslots decided and why; hyprslots.dump() prints
-- it with the state. An optional sink also receives every entry (the engine
-- forwards them to Hyprland's log with print).

local M = {}

local Log = {}
Log.__index = Log

function M.new(opts)
  opts = opts or {}
  return setmetatable({ capacity = opts.capacity or 200, sink = opts.sink, buffer = {}, seq = 0 }, Log)
end

function Log:add(level, fmt, ...)
  local ok, text = pcall(string.format, fmt, ...)
  if not ok then
    local parts = { tostring(fmt) }
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    text = table.concat(parts, " ")
  end

  self.seq = self.seq + 1
  local entry = { seq = self.seq, level = level, text = text }
  self.buffer[#self.buffer + 1] = entry
  if #self.buffer > self.capacity then
    table.remove(self.buffer, 1)
  end

  if self.sink then
    pcall(self.sink, entry)
  end
  return entry
end

function Log:info(fmt, ...) return self:add("info", fmt, ...) end
function Log:warn(fmt, ...) return self:add("warn", fmt, ...) end
function Log:error(fmt, ...) return self:add("error", fmt, ...) end

-- Entries oldest first.
function Log:entries()
  local out = {}
  for i, entry in ipairs(self.buffer) do
    out[i] = { seq = entry.seq, level = entry.level, text = entry.text }
  end
  return out
end

function Log:lines()
  local out = {}
  for i, entry in ipairs(self.buffer) do
    out[i] = string.format("#%d %s %s", entry.seq, entry.level, entry.text)
  end
  return out
end

return M
