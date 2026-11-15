# Editor first run (opt-in, like e2e/editor_smoke.sh: run it with `make
# e2e-editor` or `e2e/run.sh e2e/editor_first_run.sh`). Needs qs, grim and
# Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# A fresh install: no hyprslots config dir at all. The engine writes a
# starter config.lua and an empty slots.lua and runs with zero slots, making
# a desk for the monitor. The bar widget asks to be set up (an accent dot,
# "Click to set up your slots"). The panel opens on the Layout tab, whose
# picture explains slots; the Assignment tab sends you back there by a
# button; the button "Create your first slot", clicked with the real
# pointer, makes the first slot through the create prompt; the picture then
# shows it and a line says what comes next; the bar's set-up state is gone;
# Ctrl+S saves the slot without touching config.lua; and the panel next
# opens on the Assignment tab, which says how to put the window there into a
# slot. Screenshots go to .e2e-tmp/editor-first-run[-<theme>]-*.png
# (SMOKE_THEME=<an Omarchy theme dir> runs it in that theme, as the smoke).
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2
  # No $E2E_CONFIG_HOME/hyprslots: a fresh install.
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp
SHOT_TAG=${SMOKE_THEME:+-$(basename "$SMOKE_THEME")}

api_state() { repl 'return hyprslots.api.state()'; }
state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }
smoke_tab() { smoke tabs | sed 's/.* | //'; }
tab_is() { [[ $(smoke_tab) == "$1" ]]; }

shot() {
  local file=$SMOKE_SHOTS/editor-first-run$SHOT_TAG-$1.png
  rm -f "$file"
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

press_text() {
  local text=$1 i
  for ((i = 0; i < ${#text}; i++)); do
    [[ $(smoke press "${text:i:1}") == ok ]] || fail "press '${text:i:1}' was ignored"
  done
}

test_body() {
  for tool in qs grim wtype; do
    command -v "$tool" >/dev/null || harness_fail "the first-run scenario needs $tool"
  done
  local dir=$E2E_CONFIG_HOME/hyprslots
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  # Given a fresh install: the starter files, written once.
  if [[ -f $dir/config.lua && -f $dir/slots.lua ]]; then
    pass "the engine wrote a starter config.lua and an empty slots.lua"
  else
    fail "no starter files in $dir: $(ls -la "$dir" 2>&1)"
  fi
  grep -q 'slots = data.slots' "$dir/config.lua" || fail "the starter passes no slots.lua data on: $(cat "$dir/config.lua")"
  local starter
  starter=$(sha256sum <"$dir/config.lua")
  expect_eq "no config error" "null" "$(api_state | jq -r .config_error)"
  expect_eq "zero slots" "0" "$(api_state | jq -r '.slots | length')"
  if eventually 5 state_is .desk headless-2; then
    pass "the monitor got a desk"
  else
    fail "no desk: $(api_state | jq -c '{desk, layout, desks}')"
  fi
  spawn_and_wait t-first
  settle

  # The bar asks to be set up.
  start_editor
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "the widget loads" "ok" "$(smoke bar)"
  eventually 5 bash -c "[[ \$($watch barLabel) == setup* ]]" || true
  expect_eq "the bar asks to be set up" "setup 󰕰 set up" "$(smoke barLabel)"
  expect_eq "with an accent dot" "dot" "$(smoke barDot)"
  expect_eq "its tooltip says what a click does" $'Hyprslots: no slots yet\nClick to set up your slots' "$(smoke barTooltip)"
  sleep 0.3
  shot 1-bar-setup

  # When the panel opens (the bar's click), it opens on the Layout tab, whose
  # picture explains slots.
  expect_eq "left click" "ok" "$(smoke barClick left)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  eventually 5 tab_is Layout || true
  expect_eq "zero slots: the panel opens on the Layout tab" "Layout" "$(smoke_tab)"
  expect_eq "the picture explains slots and offers the first" \
    "Start with your slots | Slots are named places on your screens, like left, main and right. Each app you assign goes into its slot. | You choose the names, and how many. Arrange them here, then put windows into them in the Assignment tab. | [a] Create your first slot" \
    "$(smoke empty)"
  if [[ $(smoke help) == 'cre<b><font color="#'*'">a</font></b>te your first slot'* ]]; then
    pass "the help row offers it too"
  else
    fail "help row: $(smoke help)"
  fi
  sleep 0.5
  shot 2-layout-empty

  # The Assignment tab points back to the Layout tab, by a button.
  smoke_click tab:Assignment
  eventually 5 tab_is Assignment || fail "the Assignment tab did not open: $(smoke tabs)"
  expect_eq "the Assignment tab sends you to the Layout tab" \
    "Define slots in the Layout tab first: they are the places your windows go into. | [Tab] Go to Layout" "$(smoke empty)"
  sleep 0.3
  shot 3-assignment-empty
  smoke_click empty:layout
  if eventually 5 tab_is Layout; then
    pass "its button went to the Layout tab"
  else
    fail "the button left the panel on $(smoke tabs)"
  fi

  # The Desk tab is never empty: the desk the engine made, and a line on
  # what desks and layouts are.
  smoke_click tab:Desk
  eventually 5 tab_is Desk || fail "the Desk tab did not open: $(smoke tabs)"
  expect_eq "its rows" "desk:headless-2" "$(smoke selection)"
  sleep 0.3
  shot 4-desk
  smoke_click tab:Layout
  eventually 5 tab_is Layout || fail "back to the Layout tab: $(smoke tabs)"

  # Then "Create your first slot", clicked with the real pointer, opens the
  # create prompt: a name, then an optional description.
  smoke_click welcome:create
  eventually 5 bash -c "[[ \$($watch message) == 'Name your first slot'* ]]" || true
  expect_eq "it asks for the first slot's name" \
    "Name your first slot (main, left, notes…) [Enter] next  [Esc] cancel: ▏" "$(smoke message)"
  press_text main
  [[ $(smoke press Return) == ok ]] || fail "Return on the name"
  press_text "the editor"
  [[ $(smoke press Return) == ok ]] || fail "Return on the description"
  if eventually 5 state_is '.slots[0].name' main; then
    pass "the button made slot main"
  else
    fail "no slot: $(api_state | jq -c .slots); $(smoke message); errors: $(smoke errors)"
  fi
  expect_eq "its key picked from its name" "m" "$(api_state | jq -r '.slots[0].key')"
  eventually 5 smoke_idle || true
  eventually 5 bash -c "[[ \$($watch layout) == '1: main' ]]" || true
  expect_eq "the picture shows it" "1: main" "$(smoke layout)"
  expect_eq "the explanation is gone" "" "$(smoke empty)"
  expect_eq "it says so" "Made slot 'main': it shows in the picture. Ctrl+S saves." "$(smoke message)"
  expect_eq "a line says what comes next" \
    "Add more slots (s, then a), or go to Assignment (Tab) to put windows into them." "$(smoke hint)"
  sleep 0.5
  shot 5-layout-first-slot

  # The bar's set-up state is gone with the first slot.
  if eventually 5 bash -c "[[ \$($watch barLabel) != setup* ]]"; then
    pass "the bar no longer asks to be set up: $(smoke barLabel)"
  else
    fail "the bar still shows $(smoke barLabel)"
  fi
  expect_eq "no dot" "none" "$(smoke barDot)"

  # Ctrl+S saves the slot into slots.lua; config.lua stays the starter.
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  if eventually 5 state_is .dirty false; then
    pass "Ctrl+S saved"
  else
    fail "unsaved after Ctrl+S: $(smoke message)"
  fi
  grep -q 'main' "$dir/slots.lua" || fail "slots.lua lacks main: $(cat "$dir/slots.lua")"
  expect_eq "config.lua is never written again" "$starter" "$(sha256sum <"$dir/config.lua")"

  # And the panel next opens on the Assignment tab, which says how to put
  # the window on this workspace into a slot.
  [[ $(smoke press Escape) == ok ]] || fail "Escape"
  expect_eq "the panel closed" "no" "$(smoke ready)"
  expect_eq "left click" "ok" "$(smoke barClick left)"
  eventually 10 smoke_ready || fail "the panel never reopened: $(smoke errors)"
  expect_eq "with a slot the panel opens on the Assignment tab" "Assignment" "$(smoke_tab)"
  expect_eq "no empty state" "" "$(smoke empty)"
  expect_eq "it says how to assign the window" \
    "Select a window and press a (or click assign) to put it into a slot." "$(smoke hint)"
  sleep 0.5
  shot 6-assignment-hint

  # Assigning it ends the hint.
  [[ $(smoke press Down) == ok ]] || fail "Down"
  expect_eq "the window selected" "none - t-first" "$(smoke selection)"
  [[ $(smoke press a) == ok ]] || fail "a"
  [[ $(smoke press m) == ok ]] || fail "m"
  if eventually 5 state_is '.specs["1"].main' t-first; then
    pass "a, m assigned it"
  else
    fail "not assigned: $(api_state | jq -c .specs); $(smoke message)"
  fi
  eventually 5 bash -c "[[ -z \$($watch hint) ]]" || true
  expect_eq "the hint is gone" "" "$(smoke hint)"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
