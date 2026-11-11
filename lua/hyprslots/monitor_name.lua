-- A monitor's display name (docs/design.md §8): the short name the editor
-- shows for a monitor ("Built-in", "Odyssey G95NC") where Hyprland's
-- description is a long sausage of make, model and serial. Display only:
-- desks keep matching their monitors by description, serial or connector
-- (desk.lua).
--
-- The automatic name is "Built-in" for a laptop's own panel (connector eDP,
-- LVDS or DSI), else the model, else the make, else the connector.
-- Hyprland's HL.Monitor has no make or model, only the description
-- "<make> <model> <serial>", so the model is the description less its
-- serial and the longest make that starts it. The makes are the PNP vendor
-- names (hwdata's pnp.ids, the table libdisplay-info names makes from); the
-- user's label (config `monitor_names`, keyed by any selector a desk could
-- use for the monitor) comes before all of it.
--
-- Pure but for read_makes / system_makes, which read the vendor table.

local M = {}

M.BUILT_IN = "Built-in"

-- Where hwdata keeps the PNP vendor ids ("SAM\tSamsung Electric Company").
M.PNP_IDS = "/usr/share/hwdata/pnp.ids"

-- Makes of common monitors, for where pnp.ids cannot be read.
local COMMON = {
  "Acer Technologies", "Apple Computer Inc", "ASUSTek COMPUTER INC", "AU Optronics", "BenQ Corporation",
  "BOE", "Chimei Innolux Corporation", "Dell Inc.", "Eizo Nanao Corporation", "GIGA-BYTE TECHNOLOGY CO., LTD.",
  "Hewlett Packard", "HP Inc.", "Iiyama North America", "LG Display", "LG Electronics", "Lenovo Group Limited",
  "Microstep", "NEC Corporation", "Philips Consumer Electronics Company", "Samsung Display Corp",
  "Samsung Electric Company", "Sharp Corporation", "Sony", "ViewSonic Corporation",
}

local function set_of(list)
  local out = {}
  for _, name in ipairs(list) do
    out[name] = true
  end
  return out
end

-- The makes in a PNP id table (make -> true): each line three letters, a
-- tab, the vendor's name. The common ones when the file cannot be read.
function M.read_makes(path)
  local file = io.open(path or M.PNP_IDS, "r")
  if not file then
    return set_of(COMMON)
  end
  local out = {}
  for line in file:lines() do
    local name = line:match("^%w%w%w\t(.-)%s*$")
    if name and name ~= "" then
      out[name] = true
    end
  end
  file:close()
  return next(out) ~= nil and out or set_of(COMMON)
end

local system
-- The system's makes, read once.
function M.system_makes()
  system = system or M.read_makes(M.PNP_IDS)
  return system
end

local function text(value)
  return type(value) == "string" and value or ""
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Whether a connector is a laptop's own panel.
function M.internal_connector(name)
  name = tostring(name or "")
  return name:match("^eDP") ~= nil or name:match("^LVDS") ~= nil or name:match("^DSI") ~= nil
end

-- The longest make that starts `description` as whole words, or nil.
local function leading_make(description, makes)
  local best
  for i in description:gmatch("()%s") do
    local prefix = description:sub(1, i - 1)
    if makes[prefix] then
      best = prefix
    end
  end
  if makes[description] then
    best = description
  end
  return best
end

-- What is left of a description once a make (`make`, else the longest
-- known one) and the serial are taken off: { make, model } (either "").
local function split(description, serial, make, makes)
  local rest = trim(description)
  if serial ~= "" and rest:sub(-#serial) == serial and (#rest == #serial or rest:sub(-#serial - 1, -#serial - 1):match("%s")) then
    rest = trim(rest:sub(1, -#serial - 1))
  end
  if make == "" then
    make = leading_make(rest, makes or set_of(COMMON)) or ""
  end
  if make ~= "" and (rest == make or rest:sub(1, #make + 1) == make .. " ") then
    rest = trim(rest:sub(#make + 1))
  else
    make = ""
  end
  return make, rest
end

-- The automatic name of a connected monitor ({ name, description, serial,
-- make?, model? }); `makes` (make -> true) defaults to the common ones.
function M.auto(monitor, makes)
  if M.internal_connector(monitor.name) then
    return M.BUILT_IN
  end
  local model = trim(text(monitor.model))
  if model ~= "" then
    return model
  end
  local make, rest = split(text(monitor.description), text(monitor.serial), trim(text(monitor.make)), makes)
  if rest ~= "" then
    return rest
  end
  if make ~= "" then
    return make
  end
  return tostring(monitor.name or "")
end

-- The user's label for a monitor (`labels`: selector -> name), looked up by
-- its description, serial and connector as a desk would select it; or nil.
function M.label(monitor, labels)
  if type(labels) ~= "table" then
    return nil
  end
  for _, field in ipairs({ "description", "serial", "name" }) do
    local value = monitor[field]
    if type(value) == "string" and value ~= "" and labels[value] ~= nil then
      return labels[value]
    end
  end
  return nil
end

-- A connected monitor's display name: its label, else its automatic name.
function M.display(monitor, labels, makes)
  return M.label(monitor, labels) or M.auto(monitor, makes)
end

-- The display name of a desk's selector: the monitor it finds when
-- connected (`monitor`, or nil), else its label, else what the selector
-- itself says: Built-in for a laptop panel's connector, else the selector
-- less a make it starts with (its serial, if any, is not known apart).
function M.of_selector(selector, monitor, labels, makes)
  if monitor then
    return M.display(monitor, labels, makes)
  end
  if type(labels) == "table" and labels[selector] ~= nil then
    return labels[selector]
  end
  if M.internal_connector(selector) then
    return M.BUILT_IN
  end
  local make, rest = split(selector, "", "", makes)
  if rest ~= "" then
    return rest
  end
  return make ~= "" and make or selector
end

-- A name as part of a desk name: lowercase, every run of other characters
-- a single "-" ("Odyssey G95NC" -> odyssey-g95nc).
function M.slug(name)
  local out = tostring(name):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return out
end

return M
