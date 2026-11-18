-- Test seam S2: hyprslots.bind_editor_keys, the keys the loader binds when
-- installed with them (install-engine.sh --keys): one opens the editor,
-- one captures the focused workspace (docs/design.md §9, Keys and the
-- Omarchy menu).

local hl_stub = require("helpers.hl_stub")

describe("bind_editor_keys", function()
  local hl, hyprslots

  before_each(function()
    for name in pairs(package.loaded) do
      if name == "hyprslots" or name:match("^hyprslots%.") then
        package.loaded[name] = nil
      end
    end
    hl = hl_stub.new({ monitors = {} })
    _G.hl = hl
    hyprslots = require("hyprslots")
  end)

  after_each(function()
    _G.hl, _G.o = nil, nil
  end)

  it("binds the editor's key to open it and the capture key to capture, described for the keybindings menu", function()
    _G.o = nil
    hyprslots.bind_editor_keys({ editor = "SUPER + CTRL + Y", capture = "SUPER + CTRL + SHIFT + C" })
    local editor = hl.binds["SUPER + CTRL + Y"]
    assert.equal("Hyprslots: open the editor", editor.opts.description)
    assert.same({ dsp = "exec_cmd", args = "omarchy-shell shell toggle io.github.milanmitrovic.hyprslots" },
      editor.dispatcher)
    local capture = hl.binds["SUPER + CTRL + SHIFT + C"]
    assert.equal("Hyprslots: capture this workspace", capture.opts.description)
    assert.same({ dsp = "exec_cmd",
      args = "omarchy-shell shell summon io.github.milanmitrovic.hyprslots '{\"capture\":true}'" }, capture.dispatcher)
  end)

  it("through Omarchy's o.bind where it is loaded", function()
    local bound = {}
    _G.o = { bind = function(keys, description, command) bound[#bound + 1] = { keys, description, command } end }
    hyprslots.bind_editor_keys({ editor = "SUPER + CTRL + Y" })
    assert.same({ { "SUPER + CTRL + Y", "Hyprslots: open the editor",
      "omarchy-shell shell toggle io.github.milanmitrovic.hyprslots" } }, bound)
  end)

  it("binds nothing for a key it is not given, or one it does not know", function()
    hyprslots.bind_editor_keys({ nonsense = "SUPER + X" })
    assert.same({}, hl.binds)
  end)
end)
