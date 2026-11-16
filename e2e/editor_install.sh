# Editor install (opt-in, like e2e/editor_smoke.sh: run it with `make
# e2e-editor` or `e2e/run.sh e2e/editor_install.sh`). Needs qs, grim and
# Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# A plugin just added (`omarchy plugin add`: the plugin folder a copy of the
# repo) whose engine is not enabled: no loader in Omarchy's workspace-layouts
# folder, so no engine runs, and the plugin's service writes nothing by
# itself. The bar widget asks to be enabled; the panel asks "Enable the
# hyprslots engine?", saying what that writes and that the Hyprland config
# is not edited. Its Enable, clicked with the real pointer, writes the
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
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp
SHOT_TAG=${SMOKE_THEME:+-$(basename "$SMOKE_THEME")}

engine() { repl 'if hyprslots then return "running" end return "absent " .. tostring(hyprslots_load_error)'; }
engine_is() { [[ $(engine) == "$1" ]]; }
smoke_tab() { smoke tabs | sed 's/.* | //'; }
tab_is() { [[ $(smoke_tab) == "$1" ]]; }
prompt_starts() { [[ $(smoke enablePrompt) == "$1"* ]]; }
super_1() {
  hc binds -j | jq -r 'if any(.[]; .modmask == 64 and .description == "Switch to workspace 1 on every screen")
    then "hyprslots" else "not hyprslots" end'
}

shot() {
  local file=$SMOKE_SHOTS/editor-install$SHOT_TAG-$1.png
  rm -f "$file"
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
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
    "card | Enable the hyprslots engine? | hyprslots puts your windows into their slots from inside Hyprland. Enabling it adds one file, zz-hyprslots.lua, to Omarchy's workspace-layouts folder (~/.local/state/omarchy/workspace-layouts), which Omarchy loads with its own saved layouts, and reloads Hyprland. | It doesn't edit your Hyprland config. Super+1..9 then switch every screen at once. To undo, run tools/uninstall-engine.sh from the plugin's folder. | [e] Enable" \
    "$(smoke enablePrompt)"
  if [[ $(smoke help) == *'<font color="#'*'">e</font></b>nable'* ]]; then
    pass "the help row offers e"
  else
    fail "help row: $(smoke help)"
  fi
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
  if cmp -s "$E2E_PLUGIN_DIR/tools/loader.lua" "$E2E_LOADER"; then
    pass "the loader is in Omarchy's workspace-layouts folder"
  else
    fail "no loader at $E2E_LOADER"
  fi
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  eventually 5 bash -c "[[ -z \$($watch enablePrompt) ]]" || true
  expect_eq "the prompt is gone" "" "$(smoke enablePrompt)"
  eventually 5 tab_is Layout || true
  expect_eq "no slots yet: the panel settles on the Layout tab" "Layout" "$(smoke_tab)"
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

  # e enables it from the keyboard.
  expect_eq "e" "ok" "$(smoke press e)"
  if eventually 15 engine_is running; then
    pass "e started the engine"
  else
    fail "no engine after e: $(engine); prompt: $(smoke enablePrompt)"
  fi
  eventually 5 bash -c "[[ -z \$($watch enablePrompt) ]]" || true
  expect_eq "the banner is gone" "" "$(smoke enablePrompt)"

  # And uninstalled once more: the loader is gone, and the engine with it.
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1) || fail "uninstall-engine.sh: $out"
  if [[ -e $E2E_LOADER ]]; then fail "the loader is still there"; else pass "uninstalled: the loader is gone"; fi
  expect_eq "and the engine" "absent nil" "$(engine)"
  expect_eq "Super+1 is Omarchy's again" "not hyprslots" "$(super_1)"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
