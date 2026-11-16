-- Test seam S3 (on disk): desktop.lua finds the desktop entry an app's
-- window class stands for in the XDG data dirs' applications folders.

local desktop = require("hyprslots.desktop")

describe("desktop", function()
  local root, dirs

  local function write(dir, name, text)
    os.execute("mkdir -p '" .. dir .. "'")
    local file = assert(io.open(dir .. "/" .. name, "w"))
    file:write(text)
    file:close()
  end

  before_each(function()
    root = os.tmpname()
    os.remove(root)
    dirs = { root .. "/home/applications", root .. "/usr/applications" }
    write(dirs[2], "foot.desktop", "[Desktop Entry]\nName=Foot\nExec=foot\n")
    write(dirs[2], "com.mitchellh.ghostty.desktop", "[Desktop Entry]\nExec=/usr/bin/ghostty\n")
    write(dirs[2], "google-chrome.desktop", "[Desktop Entry]\nExec=/usr/bin/google-chrome-stable %U\n")
    write(dirs[2], "code-oss.desktop", "[Desktop Entry]\nExec=code-oss %F\nStartupWMClass=Code - OSS\n")
    write(dirs[2], "org.gnome.Nautilus.desktop", "[Desktop Entry]\nExec=nautilus --new-window %U\n")
    write(dirs[2], "steam.desktop", "[Desktop Entry]\nExec=steam\n")
    -- The user's own copy wins over the system's.
    write(dirs[1], "steam.desktop", "[Desktop Entry]\nExec=steam -silent\n")
  end)

  after_each(function()
    os.execute("rm -rf '" .. root .. "'")
  end)

  it("finds an entry named after the class, the user's first", function()
    assert.same({ "foot", "foot" }, { desktop.resolve("foot", dirs) })
    assert.same({ "com.mitchellh.ghostty", "/usr/bin/ghostty" }, { desktop.resolve("com.mitchellh.ghostty", dirs) })
    assert.same({ "steam", "steam -silent" }, { desktop.resolve("steam", dirs) })
  end)

  it("by the class in lower case, by StartupWMClass, or as the last part of a reverse-domain id", function()
    assert.same({ "foot", "foot" }, { desktop.resolve("Foot", dirs) })
    assert.same({ "code-oss", "code-oss" }, { desktop.resolve("Code - OSS", dirs) })
    assert.same({ "org.gnome.Nautilus", "nautilus --new-window" }, { desktop.resolve("nautilus", dirs) })
  end)

  it("finds nothing for an app with no entry", function()
    assert.is_nil(desktop.resolve("t-main", dirs))
    assert.is_nil(desktop.resolve("", dirs))
  end)

  it("reads the command of an entry by its id", function()
    assert.equal("/usr/bin/google-chrome-stable", desktop.command("google-chrome", dirs))
    assert.is_nil(desktop.command("nope", dirs))
  end)

  it("looks in XDG_DATA_HOME, then XDG_DATA_DIRS", function()
    local found = desktop.dirs({ XDG_DATA_HOME = "/h", XDG_DATA_DIRS = "/a:/b", HOME = "/home/u" })
    assert.same({ "/h/applications", "/a/applications", "/b/applications" }, found)
    found = desktop.dirs({ HOME = "/home/u" })
    assert.same({ "/home/u/.local/share/applications", "/usr/local/share/applications", "/usr/share/applications" }, found)
  end)
end)
