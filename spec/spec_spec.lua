-- Test seam S3: spec parsing and matching. The title, tag and title-matching
-- cases are ported from aerolayout's tests/test_models.py and
-- tests/test_windows.py, with macOS app names turned into Linux classes.

local spec = require("hyprslots.spec")

local function parsed(text, title_matching)
  local tm = title_matching and spec.title_matching(title_matching) or nil
  local s, err = spec.parse(text, tm)
  assert(s, err)
  return s
end

local function window(class, title)
  return { class = class, title = title }
end

describe("spec", function()
  describe("class specs", function()
    it("matches a window by its class", function()
      assert.is_true(spec.match(parsed("t-main"), { class = "t-main", title = "anything" }))
    end)

    it("does not match another class", function()
      assert.is_false(spec.match(parsed("t-main"), { class = "t-left" }))
    end)

    it("matches the class exactly, not as a pattern or prefix", function()
      assert.is_false(spec.match(parsed("t.main"), { class = "t-main" }))
      assert.is_false(spec.match(parsed("t-main"), { class = "t-main2" }))
    end)

    it("does not match a window with no class yet", function()
      assert.is_false(spec.match(parsed("t-main"), { class = "" }))
      assert.is_false(spec.match(parsed("t-main"), {}))
    end)

    it("keeps the text it was parsed from", function()
      assert.are.equal("kitty", parsed("kitty").text)
    end)

    it("trims surrounding whitespace", function()
      assert.is_true(spec.match(parsed("  kitty "), { class = "kitty" }))
    end)

    it("is class-only", function()
      assert.is_true(spec.class_only(parsed("kitty")))
      assert.is_false(spec.class_only(parsed("kitty/deltaf")))
      assert.is_false(spec.class_only(parsed("[Main]")))
    end)
  end)

  describe("parse", function()
    it("reads [Tag]/Profile as a browser tag with a profile", function()
      local s = parsed("[Main]/Work")
      assert.are.equal("tag", s.kind)
      assert.are.equal("Main", s.tag)
      assert.are.equal("Work", s.profile)
    end)

    it("reads [Tag] as a browser tag without a profile", function()
      local s = parsed("[Music]")
      assert.are.equal("tag", s.kind)
      assert.are.equal("Music", s.tag)
      assert.is_nil(s.profile)
    end)

    it("reads Class/pattern as a class with a title pattern", function()
      local s = parsed("Cursor/models")
      assert.are.equal("title", s.kind)
      assert.are.equal("Cursor", s.class)
      assert.are.equal("models", s.pattern)
    end)

    it("reads Class as a class alone", function()
      local s = parsed("Alacritty")
      assert.are.equal("class", s.kind)
      assert.are.equal("Alacritty", s.class)
    end)

    it("keeps every slash after the first in the pattern", function()
      local s = parsed("VSCode/project/foo")
      assert.are.equal("VSCode", s.class)
      assert.are.equal("project/foo", s.pattern)
    end)

    it("rejects an empty spec", function()
      for _, text in ipairs({ "", "  " }) do
        local s, err = spec.parse(text)
        assert.is_nil(s)
        assert.matches("empty", err)
      end
    end)

    it("rejects a non-string", function()
      local s, err = spec.parse({})
      assert.is_nil(s)
      assert.matches("string", err)
    end)

    it("rejects a missing class or title pattern", function()
      for _, text in ipairs({ "/deltaf", "kitty/", "kitty/  " }) do
        local s, err = spec.parse(text)
        assert.is_nil(s, text)
        assert.matches("spec '", err)
      end
    end)

    it("rejects a malformed tag", function()
      for _, text in ipairs({ "[]", "[Main", "[Main]x", "[Main]/", "[]/Work" }) do
        local s, err = spec.parse(text)
        assert.is_nil(s, text)
        assert.matches("spec '", err)
      end
    end)
  end)

  describe("matching", function()
    it("a browser window with a profile", function()
      assert.is_true(spec.match(parsed("[Main]/Work"),
        window("google-chrome", "[Main] - Some Page – Account Name (Work)")))
    end)

    it("a browser window without a profile", function()
      assert.is_true(spec.match(parsed("[Music]"),
        window("google-chrome", "[Music] - Music Player – Account Name (Personal)")))
    end)

    it("a tag spec ignores apps that are not browsers", function()
      assert.is_false(spec.match(parsed("[Research]"), window("Claude", "[Research] deep dive")))
    end)

    it("a browser window with another tag does not match", function()
      assert.is_false(spec.match(parsed("[Main]/Work"),
        window("google-chrome", "[Other] - Some Page – Account Name (Personal)")))
    end)

    it("a browser window with the tag but another profile does not match", function()
      assert.is_false(spec.match(parsed("[Main]/Work"),
        window("chromium", "[Main] - Some Page – Account Name (Personal)")))
    end)

    it("the profile must come after the tag", function()
      assert.is_false(spec.match(parsed("[Main]/Work"), window("chromium", "(Work) [Main] page")))
    end)

    it("a tag spec does not match a browser window with no title yet", function()
      assert.is_false(spec.match(parsed("[Main]"), window("chromium", nil)))
      assert.is_false(spec.match(parsed("[Main]"), window("chromium", "")))
    end)

    it("a tag is matched literally, not as a pattern", function()
      assert.is_false(spec.match(parsed("[M.in]"), window("chromium", "[Main] page")))
      assert.is_true(spec.match(parsed("[a%b]"), window("chromium", "[a%b] page")))
    end)

    it("an app without a pattern", function()
      assert.is_true(spec.match(parsed("Alacritty"), window("Alacritty", "Terminal Session")))
    end)

    it("an app with a pattern that matches", function()
      assert.is_true(spec.match(parsed("Cursor/models"), window("Cursor", "models - Cursor")))
    end)

    it("an app with a pattern that does not match", function()
      assert.is_false(spec.match(parsed("Cursor/models"), window("Cursor", "dotfiles - Cursor")))
    end)

    it("an app name mismatch", function()
      assert.is_false(spec.match(parsed("Alacritty"), window("Emacs", "Some File")))
      assert.is_false(spec.match(parsed("Alacritty/x"), window("Emacs", "x")))
    end)

    it("the title pattern is a case-insensitive substring", function()
      assert.is_true(spec.match(parsed("Cursor/MODELS"), window("Cursor", "my models - Cursor")))
    end)

    it("the title pattern is plain text, not a Lua pattern", function()
      assert.is_false(spec.match(parsed("Cursor/m.dels"), window("Cursor", "models")))
      assert.is_true(spec.match(parsed("Cursor/50%"), window("Cursor", "at 50% done")))
    end)

    it("a title pattern does not match a window with no title yet", function()
      assert.is_false(spec.match(parsed("Cursor/models"), window("Cursor", nil)))
      assert.is_false(spec.match(parsed("Cursor/models"), window("Cursor", "")))
    end)
  end)

  describe("title matching defaults", function()
    it("extracts for the generic terminals", function()
      local keys = {}
      for class in pairs(spec.title_matching(nil).extractors) do
        keys[#keys + 1] = class
      end
      table.sort(keys)
      assert.are.same({ "Alacritty", "foot", "kitty" }, keys)
    end)

    it("ships no app-specific strip rules", function()
      assert.are.same({}, spec.title_matching(nil).strip_patterns)
    end)

    it("treats the Chromium family as browsers", function()
      local browsers = spec.title_matching(nil).browser_apps
      assert.is_true(browsers["google-chrome"])
      assert.is_true(browsers["chromium"])
      assert.is_true(browsers["brave-browser"])
    end)

    it("extracts a terminal's session name", function()
      local w = window("kitty", "build | fish · ~/src")
      assert.are.equal("build", spec.identifier(w, spec.title_matching(nil)))
      assert.is_true(spec.match(parsed("kitty/build"), w))
      assert.is_false(spec.match(parsed("kitty/fish"), w))
    end)

    it("extracts foot's session name", function()
      assert.is_true(spec.match(parsed("foot/deltaf"), window("foot", "deltaf | zellij")))
    end)

    it("leaves a title without the separator whole", function()
      assert.are.equal("just a shell", spec.identifier(window("kitty", "just a shell"), spec.title_matching(nil)))
    end)

    it("matches an app without rules on its whole title", function()
      assert.is_true(spec.match(parsed("Cursor/Cursor"), window("Cursor", "models - Cursor")))
    end)
  end)

  describe("configured extractors", function()
    local TM = { extractors = { MyEditor = " — " } }

    it("extract a configured app's identifier", function()
      assert.is_true(spec.match(parsed("MyEditor/aerolayout", TM), window("MyEditor", "aerolayout — windows.py")))
    end)

    it("stop the part after the separator from matching", function()
      assert.is_false(spec.match(parsed("MyEditor/windows.py", TM), window("MyEditor", "aerolayout — windows.py")))
    end)

    it("keep the built-in extractors", function()
      assert.are.equal(" | ", spec.title_matching(TM).extractors.kitty)
    end)

    it("can override a default", function()
      local tm = spec.title_matching({ extractors = { kitty = " :: " } })
      assert.are.equal("build", spec.identifier(window("kitty", "build :: fish | x"), tm))
    end)

    it("ignore a separator that is not a string", function()
      assert.are.equal(" | ", spec.title_matching({ extractors = { kitty = 7 } }).extractors.kitty)
    end)

    it("use a separator literally, not as a pattern", function()
      local tm = spec.title_matching({ extractors = { App = "." } })
      assert.are.equal("a", spec.identifier(window("App", "a.b"), tm))
      assert.are.equal("ab", spec.identifier(window("App", "ab"), tm))
    end)
  end)

  describe("configured strip patterns", function()
    local TM = {
      extractors = { MyTerminal = " — " },
      strip_patterns = { MyTerminal = "%[SSH:.-%]" },
    }

    it("delete what the Lua pattern matches from the identifier", function()
      local w = window("MyTerminal", "prod [SSH:host] — shell")
      assert.are.equal("prod", spec.identifier(w, spec.title_matching(TM)))
      assert.is_true(spec.match(parsed("MyTerminal/prod", TM), w))
    end)

    it("work without an extractor", function()
      local tm = spec.title_matching({ strip_patterns = { App = "%s*%(%d+%)$" } })
      assert.are.equal("Inbox", spec.identifier(window("App", "Inbox (12)"), tm))
    end)

    it("a malformed pattern costs only that rule", function()
      local tm = { strip_patterns = { App = "[" } }
      assert.is_true(spec.match(parsed("App/Inbox", tm), window("App", "Inbox")))
    end)
  end)

  describe("configured browsers", function()
    it("let a configured browser match a tag spec", function()
      local tm = { browser_apps = { "firefox" } }
      assert.is_true(spec.match(parsed("[Docs]/Work", tm), window("firefox", "[Docs] - Reference (Work)")))
    end)

    it("replace the defaults", function()
      local tm = { browser_apps = { "firefox" } }
      assert.is_false(spec.match(parsed("[Docs]/Work", tm), window("google-chrome", "[Docs] - Reference (Work)")))
    end)

    it("fall back to the defaults when empty", function()
      assert.is_true(spec.title_matching({ browser_apps = {} }).browser_apps["google-chrome"])
    end)

    it("a Chromium sibling matches out of the box", function()
      assert.is_true(spec.match(parsed("[Docs]/Work"),
        window("brave-browser", "[Docs] - Reference – Account Name (Work)")))
    end)
  end)
end)

-- The Slots view's "take spec from window" (aerolayout's Window.to_spec).
describe("spec.from_window", function()
  it("is the class for a window whose class has no title rules", function()
    assert.are.equal("firefox", spec.from_window(window("firefox", "Mozilla Firefox")))
  end)

  it("adds the extracted title for a class with an extractor", function()
    assert.are.equal("kitty/deltaf", spec.from_window(window("kitty", "deltaf | nvim")))
  end)

  it("keeps the class alone when the title extracts to nothing", function()
    assert.are.equal("kitty", spec.from_window(window("kitty", "")))
    assert.are.equal("kitty", spec.from_window(window("kitty", " | nvim")))
  end)

  it("uses a strip rule as a title rule too", function()
    local tm = spec.title_matching({ strip_patterns = { ssh = "%[SSH:.-%]" } })
    assert.are.equal("ssh/box", spec.from_window(window("ssh", "[SSH:root] box"), tm))
  end)

  it("is a tag, with the profile when the title ends in one, for a browser", function()
    assert.are.equal("[Docs]/Work", spec.from_window(window("chromium", "[Docs] - Reference - Me (Work)")))
    assert.are.equal("[Docs]", spec.from_window(window("chromium", "[Docs] - Reference")))
    assert.are.equal("chromium", spec.from_window(window("chromium", "Reference")))
  end)

  it("is what matches the window back", function()
    for _, w in ipairs({ window("kitty", "deltaf | nvim"), window("chromium", "[Docs] - R - Me (Work)"), window("foot", "x") }) do
      assert.is_true(spec.match(assert(spec.parse(spec.from_window(w))), w))
    end
  end)

  it("is nil for a window with no class", function()
    assert.is_nil(spec.from_window(window(nil, "x")))
  end)
end)
