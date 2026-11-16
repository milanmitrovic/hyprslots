# Editor first run (opt-in, like e2e/editor_smoke.sh: run it with `make
# e2e-editor` or `e2e/run.sh e2e/editor_first_run.sh`). Needs qs, grim and
# Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# A fresh install: no hyprslots config dir at all. The engine writes a
# starter config.lua and an empty slots.lua and runs with zero slots, making
# a desk for the monitor, which it saves at once and without a notification
# (nothing reads as unsaved: no dirty state, no "unsaved" in the header), on
# workspaces 1 to 9 (the default; the strip ends at 9). The bar widget asks to be set up (an accent dot,
# "Click to set up your slots"). The panel opens on the Layout tab, whose
# picture explains slots; the Assignment tab sends you back there by a
# button; its first button, "Capture my windows", clicked with the real
# pointer, asks whom the capture is for and previews the window there as a
# slot, and n leaves everything as it was; the button "Create your first
# slot", clicked with the real pointer, makes the first slot through the
# create prompt; the picture then
# shows it and a line says what comes next; the bar's set-up state is gone;
# Ctrl+S saves the slot without touching config.lua; and the panel next
# opens on the Assignment tab, which says how to put the window there into a
# slot. Then two windows arranged by hand on workspace 4 (a saved Omarchy
# dwindle mode keeps it Hyprland's own tiling), 2:1, are captured from the
# Layout tab: c, o (only workspace 4), the preview, y: two new slots, the
# workspace's own tree h[t-left:2, t-right, main] (every tree holds every
# slot: main, empty there, takes no room), each window's app assigned
# there, unsaved until Ctrl+S. Screenshots go to
# .e2e-tmp/editor-first-run[-<theme>]-*.png
# (SMOKE_THEME=<an Omarchy theme dir> runs it in that theme, as the smoke).
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
-- Hyprland's own tiling puts a new window right of the one it splits,
-- wherever the pointer is: the windows arranged by hand stand as spawned.
hl.config({ dwindle = { force_split = 2 } })
-- Every notification's text, for the test to read (none on a first run).
e2e_notifications = {}
e2e_notifications_seen = pcall(function()
  local create = hl.notification.create
  hl.notification.create = function(spec)
    e2e_notifications[#e2e_notifications + 1] = spec and spec.text
    return create(spec)
  end
end)
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2
  # Workspace 4 keeps Hyprland's own tiling (Super+L's choice, saved), so
  # its windows are arranged by hand.
  printf 'o.workspace_mode({ workspace = "4", mode = "dwindle" })\n' >"${E2E_LOADER%/*}/4.lua"
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
  # Saved at once, silently: nothing on first contact reads as unsaved.
  if eventually 5 state_is .dirty false; then
    pass "the desk and its layout are saved: nothing unsaved"
  else
    fail "unsaved on first run: $(api_state | jq -c '{dirty, desks}')"
  fi
  expect_eq "the desk is not new-and-unsaved" "null" "$(api_state | jq -r '.desks["headless-2"].auto')"
  grep -q 'headless-2' "$dir/slots.lua" || fail "slots.lua lacks the desk: $(cat "$dir/slots.lua")"
  expect_eq "notifications are observed" "true" "$(repl 'return tostring(e2e_notifications_seen)')"
  expect_eq "no notification" "0" "$(repl 'return #e2e_notifications')"
  # (The wrapper does see one: a probe, gone in a millisecond.)
  repl 'hl.notification.create({ text = "e2e probe", timeout = 1 })' >/dev/null
  expect_eq "the probe was seen" "e2e probe" "$(repl 'return e2e_notifications[1]')"
  repl 'e2e_notifications = {}' >/dev/null
  expect_eq "workspaces 1 to 9 by default" "9" "$(api_state | jq -r .workspace_count)"
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
  if [[ $(smoke header) == *nsaved* ]]; then
    fail "the header reads as unsaved: $(smoke header)"
  else
    pass "nothing unsaved in the header"
  fi
  expect_eq "the strip shows workspaces 1 to 9" "[All workspaces] · 1 2 3 4 5 6 7 8 9" "$(smoke layoutStrip)"
  expect_eq "the picture explains slots and offers capturing your windows first, then the first slot" \
    "Start with your slots | Slots are named places on your screens, like left, main and right. Each app you assign goes into its slot. | Quickest: arrange your windows on a workspace the way you like them, then capture. Each window becomes a slot, and the arrangement is remembered. | Or make them one by one: you choose the names, and how many. Arrange them here, then put windows into them in the Assignment tab. | [c] Capture my windows | [a] Create your first slot" \
    "$(smoke empty)"
  if [[ $(smoke help) == *'">c</font></b>apture my windows'*'cre<b><font color="#'*'">a</font></b>te your first slot'* ]]; then
    pass "the help row offers them too"
  else
    fail "help row: $(smoke help)"
  fi
  sleep 0.5
  shot 2-layout-empty

  # "Capture my windows", clicked with the real pointer: whom it is for,
  # then the preview, t-first as a slot of its own; n leaves it all as it was.
  smoke_click welcome:capture
  eventually 5 bash -c "[[ \$($watch message) == 'Capture workspace 1:'* ]]" || true
  expect_eq "it asks whom the capture of the focused workspace is for" \
    "Capture workspace 1: apply to (a)ll workspaces or (o)nly workspace 1? [Esc] cancel" "$(smoke message)"
  expect_eq "a" "ok" "$(smoke press a)"
  eventually 5 bash -c "[[ -n \$($watch capturePreview) ]]" || true
  expect_eq "the picture previews the capture" "1: t-first" "$(smoke capturePreview)"
  expect_eq "and asks y/n, naming the slot it makes and its key" \
    "Capture workspace 1 for all workspaces: makes slot t-first (t), puts 1 window into its slot. Apply it? (y/n)" "$(smoke message)"
  sleep 0.5
  shot 2b-capture-preview
  expect_eq "n" "ok" "$(smoke press n)"
  expect_eq "it says nothing changed" "Capture cancelled: nothing changed." "$(smoke message)"
  expect_eq "the preview is gone" "" "$(smoke capturePreview)"
  expect_eq "still zero slots" "0" "$(api_state | jq -r '.slots | length')"
  expect_eq "nothing unsaved" "false" "$(api_state | jq -r .dirty)"
  if [[ $(smoke empty) == "Start with your slots"* ]]; then pass "the explanation is back"; else fail "empty: $(smoke empty)"; fi

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
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  eventually 5 state_is .dirty false || fail "unsaved after Ctrl+S: $(smoke message)"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  # Two windows arranged by hand on workspace 4 (Hyprland's own tiling
  # there, Super+L's saved choice): t-left two thirds, t-right one.
  hc dispatch "hl.dsp.focus({ workspace = '4' })" >/dev/null
  spawn_and_wait t-left
  spawn_and_wait t-right
  settle
  hc dispatch 'hl.dsp.focus({ window = "class:t-left" })' >/dev/null
  hc dispatch 'hl.dsp.window.resize({ x = 320, y = 0, relative = true })' >/dev/null
  settle
  expect_client t-left 4 0 0 1280 1080
  expect_client t-right 4 1280 0 640 1080

  # The Layout tab's c captures the focused workspace from All workspaces:
  # o (only workspace 4), the preview, y.
  expect_eq "left click" "ok" "$(smoke barClick left)"
  eventually 10 smoke_ready || fail "the panel never reopened: $(smoke errors)"
  smoke_click tab:Layout
  eventually 5 tab_is Layout || fail "the Layout tab did not open: $(smoke tabs)"
  if [[ $(smoke help) == *'">c</font></b>apture'* ]]; then pass "the help row offers c capture"; else fail "help row: $(smoke help)"; fi
  expect_eq "c" "ok" "$(smoke press c)"
  expect_eq "c asks whom the capture of workspace 4 is for" \
    "Capture workspace 4: apply to (a)ll workspaces or (o)nly workspace 4? [Esc] cancel" "$(smoke message)"
  expect_eq "o" "ok" "$(smoke press o)"
  eventually 5 bash -c "[[ -n \$($watch capturePreview) ]]" || true
  expect_eq "the preview: the windows as they are arranged, main (empty here) at the end" \
    "1: h[t-left:2, t-right, main]" "$(smoke capturePreview)"
  local preview
  preview=$(smoke message)
  if [[ $preview == "Capture workspace 4 for workspace 4 only: makes slots t-left ("?") and t-right ("?"), puts 2 windows into their slots. Apply it? (y/n)" ]]; then
    pass "it asks y/n, naming the new slots and their keys: $preview"
  else
    fail "preview message: $preview"
  fi
  expect_eq "the strip shows workspace 4" "All workspaces · 1 2 3 [4] 5 6 7 8 9" "$(smoke layoutStrip)"
  expect_eq "nothing applied yet" "false" "$(api_state | jq -r .dirty)"
  sleep 0.5
  shot 7-capture-preview
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 state_is '.specs["4"]["t-left"]' t-left; then
    pass "y captured workspace 4"
  else
    fail "not captured: $(api_state | jq -c '.specs'); $(smoke message); errors: $(smoke errors)"
  fi
  local layout
  layout=$(api_state | jq -r .layout)
  expect_eq "workspace 4's own tree" "h[t-left:2, t-right, main]" "$(api_state | jq -r --arg l "$layout" '.layouts[$l].workspaces["4"]["1"].tree')"
  expect_eq "the slots" "main t-left t-right" "$(api_state | jq -r '[.slots[].name] | sort | join(" ")')"
  expect_eq "t-right's app on workspace 4" "t-right" "$(api_state | jq -r '.specs["4"]["t-right"]')"
  expect_eq "unsaved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  if [[ $(smoke message) == "Captured workspace 4 for workspace 4 only: made slots t-left ("?") and t-right ("?"); 2 windows are in their slots. Ctrl+S saves." ]]; then
    pass "it says what it made: $(smoke message)"
  else
    fail "message: $(smoke message)"
  fi
  if [[ $(smoke header) == *"unsaved"* ]]; then pass "the header says unsaved"; else fail "header: $(smoke header)"; fi
  expect_eq "the picture shows the tree in force" "1: h[t-left:2, t-right, main]" "$(smoke layout)"
  expect_client t-left 4 0 0 1280 1080
  expect_client t-right 4 1280 0 640 1080
  sleep 0.5
  shot 8-captured
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  if eventually 5 state_is .dirty false; then pass "Ctrl+S saved the capture"; else fail "unsaved after Ctrl+S: $(smoke message)"; fi
  grep -q 't-left' "$dir/slots.lua" || fail "slots.lua lacks t-left: $(cat "$dir/slots.lua")"
  expect_eq "config.lua is never written" "$starter" "$(sha256sum <"$dir/config.lua")"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
