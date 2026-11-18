-- Test seam S3: launch.lua, the pure half of launching the apps a
-- workspace's empty slots wait for (docs/design.md §9, Launching apps):
-- the command a spec launches with, and which slots to launch for, never
-- for a window already open.

local launch = require("hyprslots.launch")
local spec = require("hyprslots.spec")

local function parsed(text)
  return assert(spec.parse(text))
end

describe("launch.exec_line", function()
  it("is a desktop entry's Exec, its field codes dropped", function()
    assert.equal("foot", launch.exec_line("[Desktop Entry]\nName=Foot\nExec=foot\n"))
    assert.equal("/usr/bin/google-chrome-stable", launch.exec_line(
      "[Desktop Entry]\nExec=/usr/bin/google-chrome-stable %U\n[Desktop Action new-window]\nExec=other\n"))
    assert.equal("code --new-window", launch.exec_line("[Desktop Entry]\nExec=code --new-window %F %i %c %k\n"))
    assert.equal("echo 100%", launch.exec_line("[Desktop Entry]\nExec=echo 100%%\n"))
  end)

  it("is nothing for an entry with no Exec, a hidden one, or one for a terminal", function()
    assert.is_nil(launch.exec_line("[Desktop Entry]\nName=x\n"))
    assert.is_nil(launch.exec_line("[Desktop Entry]\nExec=x\nHidden=true\n"))
    assert.is_nil(launch.exec_line("[Desktop Entry]\nExec=htop\nTerminal=true\n"))
    assert.is_nil(launch.exec_line("[Desktop Action a]\nExec=x\n"))
  end)
end)

describe("launch.command", function()
  local function desktop(class)
    if class == "foot" then
      return "foot", "foot"
    end
    return nil
  end

  it("is the one config.lua gives the spec first", function()
    assert.same({ command = "foot -D ~/src", source = "config" },
      launch.command(parsed("foot"), { ["foot"] = "foot -D ~/src" }, desktop))
    assert.same({ command = "ghostty --working-directory ~/x", source = "config" },
      launch.command(parsed("ghostty/x"), { ["ghostty/x"] = "ghostty --working-directory ~/x" }, desktop))
  end)

  it("else the app's own, from its desktop entry, for a spec of a class alone", function()
    assert.same({ command = "foot", source = "desktop", desktop = "foot" }, launch.command(parsed("foot"), {}, desktop))
  end)

  it("is no command for a title or tag spec without one, or an app with no desktop entry", function()
    assert.same({ reason = launch.NO_COMMAND }, launch.command(parsed("foot/deltaf"), {}, desktop))
    assert.same({ reason = launch.NO_COMMAND }, launch.command(parsed("[Mail]"), {}, desktop))
    assert.same({ reason = launch.NO_COMMAND }, launch.command(parsed("kitty"), {}, desktop))
  end)
end)

describe("launch.missing", function()
  local function plan(input)
    input.workspace = input.workspace or 3
    input.assignments = input.assignments or {}
    input.windows = input.windows or {}
    input.pending = input.pending or {}
    input.command = input.command or function(entry)
      return { command = entry.class, source = "desktop" }
    end
    return launch.missing(input)
  end

  it("launches for each slot with a spec on the workspace that no window fills, by slot name", function()
    local out = plan({ specs = { main = parsed("foot"), aside = parsed("kitty"), chat = parsed("slack") },
      assignments = { ["0x1"] = { workspace = 3, slot = "chat" } } })
    assert.same({ { slot = "aside", spec = "kitty", command = "kitty" }, { slot = "main", spec = "foot", command = "foot" } },
      out.launch)
  end)

  it("for a slot whose app is open only in another workspace's slot: each slot its own window", function()
    local out = plan({ specs = { main = parsed("foot") },
      assignments = { ["0x9"] = { workspace = 5, slot = "main" } },
      windows = { { address = "0x9", class = "foot", title = "foot" } } })
    assert.same({ { slot = "main", spec = "foot", command = "foot" } }, out.launch)
  end)

  it("never for a window already open that the spec matches and no slot holds", function()
    local held = plan({ specs = { main = parsed("foot"), aside = parsed("foot") },
      assignments = { ["0x9"] = { workspace = 3, slot = "main" } },
      windows = { { address = "0x9", class = "foot", title = "foot" } } })
    assert.same({ { slot = "aside", spec = "foot", command = "foot" } }, held.launch, "main's window is no aside's")
    local out = plan({
      specs = { main = parsed("foot"), aside = parsed("foot"), other = parsed("kitty") },
      windows = { { address = "0x9", class = "foot", title = "foot" } }, -- overflowing, or somewhere else
    })
    -- aside (first by name) is that window's to take; main waits for a second foot.
    assert.same({ { slot = "main", spec = "foot", command = "foot" }, { slot = "other", spec = "kitty", command = "kitty" } },
      out.launch)
    assert.same({ "aside" }, out.open)
  end)

  it("not twice while one launched for the slot is on its way", function()
    local out = plan({ specs = { main = parsed("foot") }, pending = { main = true } })
    assert.same({}, out.launch)
    assert.same({ "main" }, out.pending)
  end)

  it("says which empty slots it cannot launch for", function()
    local out = plan({ specs = { main = parsed("foot/deltaf") }, command = function()
      return { reason = launch.NO_COMMAND }
    end })
    assert.same({}, out.launch)
    assert.same({ { slot = "main", spec = "foot/deltaf", reason = launch.NO_COMMAND } }, out.cannot)
  end)
end)

describe("launch modes", function()
  it("cycle never, on demand, at login", function()
    assert.equal("on_demand", launch.next_mode("never"))
    assert.equal("at_login", launch.next_mode("on_demand"))
    assert.equal("never", launch.next_mode("at_login"))
    assert.equal("on_demand", launch.next_mode(nil))
  end)
end)
