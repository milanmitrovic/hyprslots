# Editor install (opt-in, like e2e/editor_smoke.sh: run it with `make
# e2e-editor` or `e2e/run.sh e2e/editor_install.sh`). Needs qs, grim and
# Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# A plugin just added (`omarchy plugin add`: the plugin folder a copy of the
# repo) whose engine is not enabled: no loader in Omarchy's workspace-layouts
# folder, so no engine runs, and the plugin's service writes nothing by
# itself. The bar widget asks to be enabled; the panel asks "Enable the
# hyprslots engine?", saying what that writes and that the Hyprland config
# is not edited, and offers two choices: the editor's keys (off) and the
# Omarchy menu's entries (on), toggled by k and m or a click. Its Enable,
# clicked with the real pointer, runs tools/install-engine.sh with the
# choices made (--keys, --menu: the run's arguments are logged by a wrapper
# around the plugin's script), writes the
# loader, reloads Hyprland and finds the engine running: the prompt is gone
# and the panel settles on the Layout tab (no slots yet), Super+1 is
# hyprslots'. Uninstalled again (tools/uninstall-engine.sh), the open panel
# keeps its last state under a banner that asks again; e enables it from the
# keyboard; uninstalled once more, the loader is gone. Screenshots go to
# .e2e-tmp/editor-install[-<theme>]-*.png (SMOKE_THEME=<an Omarchy theme
# dir> runs it in that theme, as the smoke).
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2
  install_plugin_copy
  rm -f "$E2E_LOADER"
  # The plugin's install script, wrapped to log the arguments the editor
  # runs it with.
  local tools=$E2E_PLUGIN_DIR/tools
  mv "$tools/install-engine.sh" "$tools/install-engine.real.sh"
  cat >"$tools/install-engine.sh" <<WRAP
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$E2E_DIR/install-args"
exec bash "\$(dirname "\${BASH_SOURCE[0]}")/install-engine.real.sh" "\$@"
WRAP
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SHOT_NAME=install

engine() { repl 'if hyprslots then return "running" end return "absent " .. tostring(hyprslots_load_error)'; }
engine_is() { [[ $(engine) == "$1" ]]; }
prompt_starts() { [[ $(smoke enablePrompt) == "$1"* ]]; }
super_1() {
  hc binds -j | jq -r 'if any(.[]; .modmask == 64 and .description == "Switch to workspace 1 on every screen")
    then "hyprslots" else "not hyprslots" end'
}

test_body() {
  for tool in qs grim wtype; do
    command -v "$tool" >/dev/null || harness_fail "the install scenario needs $tool"
  done
  output_create HEADLESS-2

  # Given a plugin just added: no loader, no engine.
  expect_eq "no engine" "absent nil" "$(engine)"

  start_editor
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "the widget loads" "ok" "$(smoke bar)"
  eventually 5 bash -c "[[ \$($watch barLabel) == 'setup 󰕰 enable' ]]" || true
  expect_eq "the bar asks to enable the engine" "setup 󰕰 enable" "$(smoke barLabel)"
  expect_eq "with an accent dot" "dot" "$(smoke barDot)"
  expect_eq "its tooltip says what a click does" $'Hyprslots: the engine is not enabled\nClick to enable it' "$(smoke barTooltip)"
  if [[ -e $E2E_LOADER ]]; then fail "the service wrote the loader by itself"; else pass "the service wrote nothing by itself"; fi

  # When the panel opens (the bar's click), it asks.
  expect_eq "left click" "ok" "$(smoke barClick left)"
  eventually 10 prompt_starts "card" || true
  expect_eq "the panel asks to enable the engine, saying what that does" \
    "card | Enable the hyprslots engine? | hyprslots puts your windows into their slots from inside Hyprland. Enabling it adds one file, zz-hyprslots.lua, to Omarchy's workspace-layouts folder (~/.local/state/omarchy/workspace-layouts), which Omarchy loads with its own saved layouts, and reloads Hyprland. | It doesn't edit your Hyprland config. Super+1..9 then switch every screen at once. To undo, run ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/uninstall-engine.sh. | [e] Enable" \
    "$(smoke enablePrompt)"
  if [[ $(smoke help) == *'<font color="#'*'">e</font></b>nable'*'">k</font></b>eys'*'">m</font></b>enu'* ]]; then
    pass "the help row offers e, k and m"
  else
    fail "help row: $(smoke help)"
  fi
  local keys_off="[ ] k Also bind Super+Ctrl+Y to open the editor and Super+Ctrl+Shift+C to capture"
  local keys_on="[x] k Also bind Super+Ctrl+Y to open the editor and Super+Ctrl+Shift+C to capture"
  local menu_on="[x] m Add hyprslots to the Omarchy menu (Open editor, Capture this workspace, Launch missing apps)"
  local menu_off="[ ] m Add hyprslots to the Omarchy menu (Open editor, Capture this workspace, Launch missing apps)"
  expect_eq "its choices: no keys, the menu" "$keys_off; $menu_on" "$(smoke enableChoices)"
  # k toggles the keys; a click on the menu's choice toggles it, twice back.
  expect_eq "k" "ok" "$(smoke press k)"
  expect_eq "k binds the keys" "$keys_on; $menu_on" "$(smoke enableChoices)"
  smoke_click enable:menu
  eventually 5 bash -c "[[ \$($watch enableChoices) == *'[ ] m'* ]]" || true
  expect_eq "a click leaves the menu alone" "$keys_on; $menu_off" "$(smoke enableChoices)"
  smoke_click enable:menu
  eventually 5 bash -c "[[ \$($watch enableChoices) == *'[x] m'* ]]" || true
  expect_eq "and another adds it again" "$keys_on; $menu_on" "$(smoke enableChoices)"
  sleep 0.5
  shot 1-enable
  if [[ -e $E2E_LOADER ]]; then fail "asking wrote the loader"; else pass "still nothing written"; fi

  # Then Enable, clicked with the real pointer.
  smoke_click enable:engine
  if eventually 15 engine_is running; then
    pass "Enable started the engine"
  else
    fail "no engine after Enable: $(engine); prompt: $(smoke enablePrompt); qs log: $(tail -n 5 "$E2E_DIR/qs.log")"
  fi
  expect_eq "Enable ran the script with the choices" "--keys --menu" "$(head -n1 "$E2E_DIR/install-args")"
  if [[ -f $E2E_LOADER ]]; then
    pass "the loader is in Omarchy's workspace-layouts folder"
  else
    fail "no loader at $E2E_LOADER"
  fi
  expect_eq "it binds the editor's keys (both free here)" \
    'local KEYS = { editor = "SUPER + CTRL + Y", capture = "SUPER + CTRL + SHIFT + C" }' \
    "$(grep -m1 '^local KEYS = ' "$E2E_LOADER" 2>/dev/null)"
  if grep -q 'hyprslots: Open editor' "$E2E_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc" 2>/dev/null; then
    pass "hyprslots is in the Omarchy menu"
  else
    fail "no menu entries in $E2E_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
  fi
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  eventually 5 bash -c "[[ -z \$($watch enablePrompt) ]]" || true
  expect_eq "the prompt is gone" "" "$(smoke enablePrompt)"
  eventually 5 tab_is Layout || true
  expect_eq "no slots yet: the panel settles on the Layout tab" "Layout" "$(smoke_tab)"
  # Where it settles, it says what the script did with the keys and the menu.
  eventually 5 bash -c "[[ \$($watch message) == *Reloaded* ]]" || true
  expect_eq "it says so" \
    "Super+Ctrl+Y: open the editor. Super+Ctrl+Shift+C: capture this workspace. Added hyprslots to the Omarchy menu (Trigger): Open editor, Capture this workspace, Launch missing apps. Reloaded Hyprland: the hyprslots engine is running." \
    "$(smoke message)"
  expect_eq "Super+1 is hyprslots'" hyprslots "$(super_1)"
  expect_eq "no config errors" "" "$(hc configerrors -j | jq -r '.[] | select(. != "")')"
  eventually 5 bash -c "[[ \$($watch barLabel) == 'setup 󰕰 set up' ]]" || true
  expect_eq "the bar now asks for slots" "setup 󰕰 set up" "$(smoke barLabel)"
  sleep 0.5
  shot 2-enabled

  # Uninstalled from the command line while the panel is open: it keeps its
  # last state, under a banner that asks again.
  local out
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1) || fail "uninstall-engine.sh: $out"
  eventually 10 prompt_starts "banner" || true
  expect_eq "a banner asks again over the last state" \
    "banner | The hyprslots engine is not running: what shows here is from before. | Enable it? That adds one file to Omarchy's workspace-layouts folder and reloads Hyprland; your Hyprland config is not edited. | [e] Enable" \
    "$(smoke enablePrompt)"
  expect_eq "the bar asks to enable it" "setup 󰕰 enable" "$(smoke barLabel)"
  sleep 0.5
  shot 3-banner

  expect_eq "the banner offers the choices too, as made" "$keys_on; $menu_on" "$(smoke enableChoices)"

  # k leaves the keys alone this time; e enables it from the keyboard.
  expect_eq "k" "ok" "$(smoke press k)"
  expect_eq "e" "ok" "$(smoke press e)"
  if eventually 15 engine_is running; then
    pass "e started the engine"
  else
    fail "no engine after e: $(engine); prompt: $(smoke enablePrompt)"
  fi
  eventually 5 bash -c "[[ -z \$($watch enablePrompt) ]]" || true
  expect_eq "the banner is gone" "" "$(smoke enablePrompt)"
  expect_eq "e ran it with the menu alone" "--menu" "$(sed -n 2p "$E2E_DIR/install-args")"

  # And uninstalled once more: the loader is gone, and the engine with it.
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1) || fail "uninstall-engine.sh: $out"
  if [[ -e $E2E_LOADER ]]; then fail "the loader is still there"; else pass "uninstalled: the loader is gone"; fi
  expect_eq "and the engine" "absent nil" "$(engine)"
  expect_eq "Super+1 is Omarchy's again" "not hyprslots" "$(super_1)"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
