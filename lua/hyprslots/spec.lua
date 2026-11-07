-- Window specs: which window a slot holds.
--
-- Slice 1 knows one form, the window class (a Wayland app-id, e.g.
-- `foot --app-id t-main`), matched exactly. The title and tag forms
-- (`kitty/deltaf`, `[Tag]/Profile`) arrive with the full grammar and are
-- rejected until then, so a config written for them fails loudly instead of
-- matching the wrong windows. Pure: no `hl`, no I/O.

local M = {}

-- Parse spec text. Returns { text, class }, or nil and an error message.
function M.parse(text)
  if type(text) ~= "string" then
    return nil, "a spec must be a string, got " .. type(text)
  end
  local trimmed = text:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil, "a spec must not be empty"
  end
  if trimmed:find("[/%[%]]") then
    return nil, string.format("spec '%s': only class specs are supported yet (no '/' or '[...]')", trimmed)
  end
  return { text = trimmed, class = trimmed }
end

-- Whether a window (anything with a `class` field) matches a parsed spec.
function M.match(spec, window)
  return window.class ~= nil and window.class == spec.class
end

return M
