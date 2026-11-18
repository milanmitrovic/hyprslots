-- The hyprslots command (tools/hyprslots), which the Omarchy menu's entries
-- run: its arguments, and what it makes of the engine's reply. It runs here
-- as bash runs it, against a stand-in hyprctl (which records the Lua it is
-- asked to evaluate and answers with a canned reply) and omarchy-shell
-- (which records its arguments), with no session bus, so no notification.

local CLI = "tools/hyprslots"

describe("the hyprslots command", function()
  local root, bin, reply_path, calls_path

  local function sh(command)
    assert(os.execute(command))
  end

  local function write(path, content)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
  end

  local function read(path)
    local file = io.open(path, "r")
    if not file then
      return nil
    end
    local content = file:read("a")
    file:close()
    return content
  end

  local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
  end

  setup(function()
    root = os.tmpname()
    os.remove(root)
    sh("mkdir -p " .. quote(root .. "/bin"))
    bin = root .. "/bin"
    reply_path = root .. "/reply"
    calls_path = root .. "/calls"
    write(bin .. "/hyprctl", "#!/usr/bin/env bash\n"
      .. "printf '%s\\n' \"$*\" >>" .. quote(calls_path) .. "\n"
      .. "cat " .. quote(reply_path) .. "\n")
    write(bin .. "/omarchy-shell", "#!/usr/bin/env bash\n"
      .. "printf 'omarchy-shell %s\\n' \"$*\" >>" .. quote(calls_path) .. "\n")
    sh("chmod +x " .. quote(bin .. "/hyprctl") .. " " .. quote(bin .. "/omarchy-shell"))
  end)

  teardown(function()
    sh("rm -rf " .. quote(root))
  end)

  before_each(function()
    os.remove(calls_path)
    write(reply_path, "")
  end)

  -- Runs the command with `args` (a shell word list) against `reply` (what
  -- hyprctl prints); returns its stdout, stderr and exit status.
  local function run(args, reply)
    write(reply_path, reply or "")
    local out_path, err_path = root .. "/out", root .. "/err"
    local _, _, code = os.execute("env -u DBUS_SESSION_BUS_ADDRESS PATH=" .. quote(bin) .. ":\"$PATH\" bash "
      .. CLI .. " " .. args .. " >" .. quote(out_path) .. " 2>" .. quote(err_path))
    return read(out_path), read(err_path), code
  end

  local function calls()
    return read(calls_path)
  end

  describe("its arguments", function()
    it("prints its usage for --help, -h and no command", function()
      for _, args in ipairs({ "--help", "-h", "" }) do
        local out, err, code = run(args)
        assert.equal(0, code)
        assert.equal("", err)
        assert.matches("^hyprslots from the command line", out)
        assert.matches("\n  hyprslots launch%-missing %[N%]", out)
        assert.matches("shown as a notification%.\n$", out)
        assert.not_matches("#", out)
        assert.not_matches("set %-euo", out)
      end
      assert.is_nil(calls())
    end)

    it("refuses an unknown command, exit 2, asking nothing of the engine", function()
      local out, err, code = run("bogus")
      assert.equal(2, code)
      assert.equal("", out)
      assert.equal("hyprslots: unknown command 'bogus' (see --help)\n", err)
      assert.is_nil(calls())
    end)

    it("refuses a workspace that is not a number, exit 2, asking nothing of the engine", function()
      for _, workspace in ipairs({ "x", "3x", "-1", "1.5", "' 3'" }) do
        local out, err, code = run("launch-missing " .. workspace)
        assert.equal(2, code)
        assert.equal("", out)
        assert.matches("^hyprslots: a workspace is a number, got '", err)
      end
      assert.is_nil(calls())
    end)

    it("opens the editor, and the editor capturing, through omarchy-shell", function()
      assert.equal(0, select(3, run("editor")))
      assert.equal(0, select(3, run("capture")))
      assert.equal("omarchy-shell shell summon io.github.milanmitrovic.hyprslots\n"
        .. "omarchy-shell shell summon io.github.milanmitrovic.hyprslots {\"capture\":true}\n", calls())
    end)
  end)

  describe("launch-missing", function()
    local NOTHING = '{"ok":true,"workspace":3,"launched":[],"open":[],"pending":[],"cannot":[],"seq":7}'

    it("asks the engine for the workspace given", function()
      run("launch-missing 3", NOTHING)
      local lua = calls()
      assert.matches('hyprslots%.api%.call%("launch_missing", %[%[{"workspace": 3}%]%]%)', lua)
      assert.matches("if not hyprslots then return", lua)
    end)

    it("asks for the focused workspace's, with no workspace given", function()
      run("launch-missing", NOTHING)
      assert.matches('hyprslots%.api%.call%("launch_missing", %[%[{}%]%]%)', calls())
    end)

    it("says Nothing to launch when nothing is launched, pending or cannot be", function()
      local out, err, code = run("launch-missing 3", NOTHING)
      assert.equal(0, code)
      assert.equal("", err)
      assert.equal("Nothing to launch (workspace 3).\n", out)
    end)

    it("says Nothing to launch too when the apps are all open already", function()
      local out, _, code = run("launch-missing",
        '{"ok":true,"workspace":4,"launched":[],"open":["main","aside"],"pending":[],"cannot":[],"seq":7}')
      assert.equal(0, code)
      assert.equal("Nothing to launch (workspace 4).\n", out)
    end)

    it("names what it launched, by the command's program, for each slot", function()
      local out, _, code = run("launch-missing 3", '{"ok":true,"workspace":3,'
        .. '"launched":[{"slot":"main","command":"foot --app-id=t sleep 1"},{"slot":"aside","command":"firefox"}],'
        .. '"open":[],"pending":[],"cannot":[],"seq":7}')
      assert.equal(0, code)
      assert.equal("Launched foot for main, firefox for aside (workspace 3).\n", out)
    end)

    it("says which are on their way already", function()
      local out = run("launch-missing 3",
        '{"ok":true,"workspace":3,"launched":[],"open":[],"pending":["main","aside"],"cannot":[],"seq":7}')
      assert.equal("on its way already: main, aside (workspace 3).\n", out)
    end)

    it("says which cannot be launched", function()
      local out = run("launch-missing 3", '{"ok":true,"workspace":3,"launched":[],"open":[],"pending":[],'
        .. '"cannot":[{"slot":"aside","reason":"can\'t launch: set a command"}],"seq":7}')
      assert.equal("cannot launch aside: set a command (workspace 3).\n", out)
    end)

    it("says each part, in order, separated by semicolons", function()
      local out, _, code = run("launch-missing 3", '{"ok":true,"workspace":3,'
        .. '"launched":[{"slot":"main","command":"foot"}],"open":["side"],"pending":["notes"],'
        .. '"cannot":[{"slot":"aside","reason":"x"},{"slot":"extra","reason":"x"}],"seq":7}')
      assert.equal(0, code)
      assert.equal("Launched foot for main; on its way already: notes; cannot launch aside, extra: set a command"
        .. " (workspace 3).\n", out)
    end)

    it("passes on the engine's refusal, exit 1", function()
      local out, err, code = run("launch-missing 3",
        '{"ok":false,"error":"workspace 3 launches no apps: its launch setting is never"}')
      assert.equal(1, code)
      assert.equal("", err)
      assert.equal("Launch missing apps: workspace 3 launches no apps: its launch setting is never\n", out)
    end)

    it("says the engine is not running, exit 1", function()
      local out, _, code = run("launch-missing",
        '{"ok":false,"error":"the hyprslots engine is not running"}')
      assert.equal(1, code)
      assert.equal("Launch missing apps: the hyprslots engine is not running\n", out)
    end)

    it("passes on a reply that is not JSON (Hyprland not reachable), exit 1", function()
      local out, _, code = run("launch-missing 3", "Couldn't connect to the Hyprland socket")
      assert.equal(1, code)
      assert.equal("Launch missing apps: Couldn't connect to the Hyprland socket\n", out)
    end)
  end)
end)
