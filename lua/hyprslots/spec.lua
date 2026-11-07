-- Window specs: which window a slot holds (docs/design.md §7a).
--
--   App            the window class (a Wayland app-id), matched exactly
--   App/pattern    that class, and `pattern` found in the window's extracted
--                  title: a case-insensitive plain substring (not a Lua
--                  pattern); everything after the first '/' is the pattern
--   [Tag]          a browser window whose title contains "[Tag]"
--   [Tag]/Profile  ... and, after it, "(Profile)": the title Chromium gives a
--                  profile window, "[Tag] - Page Title - Person (Profile)"
--
-- Tag specs only match classes in title_matching.browser_apps, so a chat
-- window titled "[Research] ..." never takes a browser slot.
--
-- Title extraction (`identifier`), per class, from `title_matching`:
--   extractors      class -> separator; keep the part before it (plain text)
--   strip_patterns  class -> Lua pattern deleted from what is left
--   browser_apps    the classes tag specs may match
-- `extractors` and `strip_patterns` extend the defaults below; `browser_apps`
-- replaces them (it is a whitelist; an empty list means the defaults).
--
-- Ported from aerolayout (models.py WindowSpec, windows.py Window.matches).
-- Pure: no `hl`, no I/O.

local M = {}

-- Terminals that put a zellij/tmux session name first: "session | info".
M.DEFAULT_EXTRACTORS = { kitty = " | ", Alacritty = " | ", foot = " | " }

-- Strip rules are facts about one app's title decorations: none by default.
M.DEFAULT_STRIP_PATTERNS = {}

-- The Chromium family's Linux classes (Wayland app-ids).
M.DEFAULT_BROWSER_APPS = { "google-chrome", "chromium", "brave-browser", "microsoft-edge" }

local function merged(defaults, supplied)
  local out = {}
  for class, value in pairs(defaults) do
    out[class] = value
  end
  if type(supplied) == "table" then
    for class, value in pairs(supplied) do
      if type(class) == "string" and type(value) == "string" and value ~= "" then
        out[class] = value
      end
    end
  end
  return out
end

-- Normalize a config's `title_matching` table (nil for the defaults). Values
-- of the wrong type are skipped here; config.validate reports them.
function M.title_matching(raw)
  raw = type(raw) == "table" and raw or {}
  local browsers = {}
  if type(raw.browser_apps) == "table" then
    for _, class in ipairs(raw.browser_apps) do
      if type(class) == "string" and class ~= "" then
        browsers[class] = true
      end
    end
  end
  if next(browsers) == nil then
    for _, class in ipairs(M.DEFAULT_BROWSER_APPS) do
      browsers[class] = true
    end
  end
  return {
    extractors = merged(M.DEFAULT_EXTRACTORS, raw.extractors),
    strip_patterns = merged(M.DEFAULT_STRIP_PATTERNS, raw.strip_patterns),
    browser_apps = browsers,
  }
end

local DEFAULT_TM = M.title_matching(nil)

local function trim(text)
  return text:match("^%s*(.-)%s*$")
end

local function invalid(text, why)
  return nil, string.format("spec '%s': %s", text, why)
end

-- Parse spec text. `title_matching` is a normalized table from
-- M.title_matching (default: the defaults); the spec keeps it for matching.
-- Returns { text, kind = "class"|"title"|"tag", class, pattern, tag,
-- profile }, or nil and an error message.
function M.parse(text, title_matching)
  if type(text) ~= "string" then
    return nil, "a spec must be a string, got " .. type(text)
  end
  local trimmed = trim(text)
  if trimmed == "" then
    return nil, "a spec must not be empty"
  end
  local tm = title_matching or DEFAULT_TM
  local out = { text = trimmed, tm = tm }

  if trimmed:sub(1, 1) == "[" then
    local tag, rest = trimmed:match("^%[([^%]]*)%](.*)$")
    if not tag then
      return invalid(trimmed, "a tag needs a closing ']'")
    end
    if trim(tag) == "" then
      return invalid(trimmed, "the tag is empty")
    end
    out.kind, out.tag = "tag", tag
    if rest == "" then
      return out
    end
    local profile = rest:match("^/(.*)$")
    if not profile or trim(profile) == "" then
      return invalid(trimmed, "expected [Tag] or [Tag]/Profile")
    end
    out.profile = trim(profile)
    return out
  end

  local class, pattern = trimmed:match("^([^/]*)/(.*)$")
  if not class then
    out.kind, out.class = "class", trimmed
    return out
  end
  class, pattern = trim(class), trim(pattern)
  if class == "" then
    return invalid(trimmed, "the class before '/' is empty")
  end
  if pattern == "" then
    return invalid(trimmed, "the title pattern after '/' is empty")
  end
  out.kind, out.class, out.pattern = "title", class, pattern
  return out
end

-- Whether a spec matches on the class alone (no title involved).
function M.class_only(spec)
  return spec.kind == "class"
end

-- The meaningful part of a window's title under its class's rules: the part
-- before the extractor's separator, minus what the strip pattern matches. A
-- class with no rules gets its whole title. Nil for a window with no title.
function M.identifier(window, title_matching)
  local title, class = window.title, window.class
  if type(title) ~= "string" or title == "" or not class then
    return nil
  end
  local tm = title_matching or DEFAULT_TM
  local identifier = title
  local separator = tm.extractors[class]
  if separator then
    local at = title:find(separator, 1, true)
    if at then
      identifier = trim(title:sub(1, at - 1))
    end
  end
  local pattern = tm.strip_patterns[class]
  if pattern then
    -- A malformed pattern costs that one rule, not every match.
    local ok, stripped = pcall(string.gsub, identifier, pattern, "")
    if ok then
      identifier = trim(stripped)
    end
  end
  return identifier
end

local function match_tag(spec, window)
  local title = window.title
  if not spec.tm.browser_apps[window.class] or type(title) ~= "string" then
    return false
  end
  local _, tag_end = title:find("[" .. spec.tag .. "]", 1, true)
  if not tag_end then
    return false
  end
  if not spec.profile then
    return true
  end
  return title:find("(" .. spec.profile .. ")", tag_end + 1, true) ~= nil
end

-- Whether some title would let this window match the spec: its class is the
-- spec's (a browser_apps class for a tag spec). What a sticky assignment
-- still needs once the title that won it has changed.
function M.admits(spec, window)
  if window.class == nil or window.class == "" then
    return false
  end
  if spec.kind == "tag" then
    return spec.tm.browser_apps[window.class] == true
  end
  return window.class == spec.class
end

-- Whether a window (anything with `class` and `title` fields) matches a
-- parsed spec.
function M.match(spec, window)
  if window.class == nil or window.class == "" then
    return false
  end
  if spec.kind == "tag" then
    return match_tag(spec, window)
  end
  if window.class ~= spec.class then
    return false
  end
  if spec.kind == "class" then
    return true
  end
  local identifier = M.identifier(window, spec.tm)
  if not identifier then
    return false
  end
  return identifier:lower():find(spec.pattern:lower(), 1, true) ~= nil
end

-- The spec that names this window (aerolayout's Window.to_spec), for the
-- editor's "take spec from window": a browser window with "[Tag]" in its
-- title is `[Tag]`, or `[Tag]/Profile` when the title ends in "(Profile)"; a
-- class with title rules (an extractor or a strip pattern) is
-- `class/identifier` when the title leaves one; anything else is its class.
-- Nil for a window with no class.
function M.from_window(window, title_matching)
  local class, title = window.class, window.title
  if type(class) ~= "string" or class == "" then
    return nil
  end
  local tm = title_matching or DEFAULT_TM
  if tm.browser_apps[class] and type(title) == "string" then
    local tag = title:match("%[([^%]]-)%]")
    if tag and trim(tag) ~= "" then
      local profile = title:match("%(([^)]+)%)%s*$")
      if profile then
        return "[" .. tag .. "]/" .. profile
      end
      return "[" .. tag .. "]"
    end
  end
  if tm.extractors[class] or tm.strip_patterns[class] then
    local identifier = M.identifier(window, tm)
    if identifier and identifier ~= "" then
      return class .. "/" .. identifier
    end
  end
  return class
end

return M
