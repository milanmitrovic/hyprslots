# Editor smoke (opt-in: not a *_test.sh, so `make e2e` skips it; run it with
# `make e2e-editor` or `e2e/run.sh e2e/editor_smoke.sh`). Needs qs
# (Quickshell), grim, and Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# The editor plugin (editor/) runs in Quickshell on the TEST instance, never
# in the live shell: e2e/editor/shell.qml loads the plugin's Engine.qml and
# Panel.qml standalone, with WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE
# of the nested Hyprland and the harness's private XDG_RUNTIME_DIR. The panel
# is opened, a stray window is put into a slot with real key presses (wtype,
# through the panel's keyboard handling), which also makes its spec desk 3's
# for that slot; u takes it out again with that spec (the slot is left
# empty), c clears a Missing slot's spec, through the panel's press() hook,
# and api state must show each; [ ] and the digits page by
# desk. Then the Layout tab flips desk 3's tree, takes a typed ratio,
# applies it (api state and the windows' geometry must follow) and saves it
# (slots.lua must hold it); ] and 3 switch its desk; its slot list (s) edits
# the global slots (a refused then a good rename, the trees and specs
# following; a new slot, put in the tree at once and x taken out again;
# Return on a placed one; delete; describe) with no Slots tab; the
# Arrangements tab creates one for the connected screen, and a save must
# write all of it to slots.lua. Last, the
# bar widget on a stand-in bar strip: its label, the unsaved dot, its menu
# (Save, Re-apply, Record), left clicks toggling the panel, and the error
# state while the hyprslots global is gone.
# Screenshots of the nested compositor go to .e2e-tmp/editor-smoke-*.png.
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0 (desk N = workspace N).
# Desk 3, arrangement "solo": h[main:2, v[right, side]]; t-side never opens.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = {}, right = {}, side = {} },
  specs = {
    [3] = { main = "t-main", right = "t-right", side = "t-side" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[main:2, v[right, side]]" } },
    },
  },
}
LUA
}

SMOKE_QS_DIR='' SMOKE_QS_PID='' SMOKE_WTYPE_PID=''
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp

# qs ipc against the smoke's own Quickshell instance (by pid: the instance
# lives in the harness's private XDG_RUNTIME_DIR).
smoke() { qs ipc --pid "$SMOKE_QS_PID" call smoke "$@" 2>&1; }

smoke_ready() { [[ $(smoke ready) == yes ]]; }
smoke_idle() { [[ $(smoke busy) == no ]]; }

# The test instance's api state, as JSON.
api_state() { repl 'return hyprslots.api.state()'; }

address_of() { hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .address'; }

assignment_of() {
  api_state | jq -cS --arg a "$1" '.assignments[$a] // null'
}

assigned_to_side() { [[ $(assignment_of "$1") == '{"desk":3,"slot":"side"}' ]]; }
# Desk 3's tree in force on the main screen, and whether all is saved.
tree_in_force() { api_state | jq -r '.arrangements.solo.desks["3"].main.tree'; }
tree_in_force_is() { [[ $(tree_in_force) == "$1" ]]; }
saved() { [[ $(api_state | jq -r .dirty) == false ]]; }

unassigned() { api_state | jq -e --arg a "$1" '(.assignments[$a] == null) and (.unassigned | index($a) != null)' >/dev/null; }

# Real key presses into the nested compositor (the panel holds the keyboard).
# Each wtype is a new virtual keyboard: the first key of the first one is
# lost while its keymap lands, and a second wtype's keys were not delivered
# at all, so the whole sequence is one wtype, started with a key the panel
# ignores (F13), run in the background while the smoke watches the panel.
keys_in_background() {
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY wtype -d 60 -k F13 -s 300 "$@" >>"$E2E_DIR/wtype.log" 2>&1 &
  SMOKE_WTYPE_PID=$!
  E2E_CLIENT_PIDS+=("$SMOKE_WTYPE_PID")
}

shot() {
  local file=$SMOKE_SHOTS/editor-smoke-$1.png
  rm -f "$file"
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

# Milliseconds one repl round trip takes.
time_ms() {
  local start end
  start=$(date +%s%N)
  "$@" >/dev/null
  end=$(date +%s%N)
  printf '%d' $(((end - start) / 1000000))
}

start_editor() {
  local omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
  SMOKE_QS_DIR=$E2E_DIR/qs
  mkdir -p "$SMOKE_QS_DIR"
  cp "$E2E_ROOT/e2e/editor/shell.qml" "$SMOKE_QS_DIR/shell.qml"
  ln -s "$E2E_ROOT/editor" "$SMOKE_QS_DIR/editor"
  # qs.Commons / qs.Ui resolve against the config root, as in the shell.
  ln -s "$omarchy/shell/Commons" "$SMOKE_QS_DIR/Commons"
  ln -s "$omarchy/shell/Ui" "$SMOKE_QS_DIR/Ui"

  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG QT_QPA_PLATFORM=wayland \
    OMARCHY_PATH=$omarchy qs --no-color -p "$SMOKE_QS_DIR" >"$E2E_DIR/qs.log" 2>&1 &
  SMOKE_QS_PID=$!
  E2E_CLIENT_PIDS+=("$SMOKE_QS_PID")
  eventually 15 qs ipc --pid "$SMOKE_QS_PID" show ||
    harness_fail "Quickshell never answered ipc (alive: $(kill -0 "$SMOKE_QS_PID" 2>/dev/null && echo yes || echo no)); see $E2E_DIR/qs.log"
}

# Type text into the panel, one press() per character.
press_text() {
  local text=$1 i
  for ((i = 0; i < ${#text}; i++)); do
    [[ $(smoke press "${text:i:1}") == ok ]] || fail "press '${text:i:1}' was ignored"
  done
}

press_keys() {
  local k
  for k in "$@"; do
    [[ $(smoke press "$k") == ok ]] || fail "press $k was ignored"
  done
}

state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }

slot_names() { api_state | jq -r '[.slots[].name] | join(" ")'; }

# The Layout tab's slot list (s): the global slots, name and description
# only. A rename to a taken name is refused in its prompt, then right
# becomes aside (every tree and desk 3's spec follow); a makes notes and,
# on y, puts it in the tree after the selected leaf (main), where x takes it out
# again; Return on a slot the desk places selects it in the picture; d asks
# naming what a slot goes from, deletes the unused notes; e describes main.
layout_slots() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "three tabs, no Slots tab" "Assignment Layout Arrangements | Layout" "$(smoke tabs)"
  expect_eq "the global slots" "main right side" "$(slot_names)"
  expect_eq "s moves the keys to the slot list" "ok" "$(smoke press s)"
  expect_eq "by name, the first selected" "slots main" "$(smoke selection)"
  sleep 0.3
  shot 9-layout-slots
  press_keys Down r
  expect_eq "r prompts for the new name" \
    "Rename 'right' to (every tree and desk follows) [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text main
  press_keys Return
  eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == *\"there is a slot 'main' already\"* ]]" ||
    fail "the taken name was not refused in its prompt: $(smoke message)"
  log "refusal: $(smoke message)"
  sleep 0.3
  shot 10-layout-slots-refused
  press_keys Backspace Backspace Backspace Backspace
  press_text aside
  press_keys Return
  if eventually 5 state_is '.specs["3"].aside' t-right; then
    pass "r renamed right to aside, desk 3's spec along"
  else
    fail "right was not renamed: $(api_state | jq -c '{slots, specs}'); $(smoke message); errors: $(smoke errors)"
  fi
  expect_eq "the global slots" "aside main side" "$(slot_names)"
  expect_eq "the tree is rewritten" "h[main:2, v[aside, side:3]]" "$(tree_in_force)"
  eventually 5 bash -c "[[ \$($watch layout) == 'main: h[main:2, v[aside, side:3]]' ]]" || true
  expect_eq "and so is the picture" "main: h[main:2, v[aside, side:3]]" "$(smoke layout)"
  expect_eq "the edit is unsaved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  log "message: $(smoke message)"

  # a makes notes (name, description), then offers to put it in the tree.
  press_keys a
  press_text notes
  press_keys Return
  press_text scratch
  press_keys Return
  if eventually 5 state_is '.slots[] | select(.name == "notes") | .description' scratch; then
    pass "a added the global slot notes with its description"
  else
    fail "notes was not added: $(api_state | jq -c .slots); $(smoke message)"
  fi
  eventually 5 bash -c "[[ \$($watch message) == *'(y/n)'* ]]" || true
  expect_eq "and offers to put it in the tree after the selected leaf" \
    "Added slot 'notes'. Put it in main's tree on desk 3 after main? (y/n)" "$(smoke message)"
  press_keys y
  expect_eq "y put notes after main, in the draft" "main: h[main:2, notes, v[aside, side:3]] *" "$(smoke layout)"
  expect_eq "the keys are the picture's again, notes selected" "main notes" "$(smoke selection)"
  sleep 0.3
  shot 11-layout-new-slot-placed
  press_keys x
  expect_eq "x took it out again" "main: h[main:2, v[aside, side:3]]" "$(smoke layout)"

  # Return on a slot the desk places selects it in the picture.
  press_keys s Up Up Up Down
  expect_eq "main selected in the list" "slots main" "$(smoke selection)"
  press_keys Return
  expect_eq "Return on a placed slot selects it" "main main" "$(smoke selection)"
  expect_eq "and says where" "main is on main already: selected it there." "$(smoke message)"

  # d on side names the tree it goes from (n keeps it); d on notes deletes it.
  press_keys s Down Down Down d
  expect_eq "d names what side goes from" "Delete slot 'side'? It goes from the trees solo/3/main. (y/n)" \
    "$(smoke message)"
  press_keys n
  press_keys Up d
  expect_eq "d on the unused notes asks plainly" "Delete slot 'notes'? (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.slots | length' 3; then
    pass "d, y deleted notes"
  else
    fail "notes is still there: $(slot_names); $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys Up Up Down e
  expect_eq "e describes main" "Description for 'main' (empty removes it) [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text "the editor"
  press_keys Return
  if eventually 5 state_is '.slots[] | select(.name == "main") | .description' "the editor"; then
    pass "e described main"
  else
    fail "main's description: $(api_state | jq -c '.slots'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  sleep 0.3
  shot 12-layout-slots-edited
  expect_eq "Escape goes back to the picture" "ok" "$(smoke press Escape)"
  expect_eq "the panel stays open" "yes" "$(smoke ready)"
  expect_eq "the picture's keys again" "main main" "$(smoke selection)"
}

# The Arrangements tab: n makes "desk" for the connected screen, copying
# solo's trees; it sorts before solo, so these monitors run it.
arrangements_view() {
  expect_eq "Tab to Arrangements" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 13-arrangements
  press_keys n
  press_text desk
  press_keys Return
  expect_eq "a role is suggested for the monitor" "main" \
    "$(smoke message | sed -E 's/.*cancel: (.*)▏.*/\1/')"
  press_keys Return
  expect_eq "then where its trees come from" \
    "Trees for 'desk' from: (d)efault, (e)mpty, (s)olo? [Esc] cancel   → default" "$(smoke message)"
  press_keys s
  if eventually 5 state_is .arrangement desk; then
    pass "n created desk from these screens, and they run it"
  else
    fail "desk is not running: $(api_state | jq -c '{arrangement, a: (.arrangements | keys)}'); $(smoke message)"
  fi
  local selector
  selector=$(api_state | jq -r '.monitors[0] | if .description != "" then .description elif .serial != "" then .serial else .name end')
  expect_eq "desk selects the monitor by $selector" "$selector" "$(api_state | jq -r '.arrangements.desk.screens.main')"
  expect_eq "desk has solo's trees" "h[main:2, v[aside, side:3]]" \
    "$(api_state | jq -r '.arrangements.desk.desks["3"].main.tree')"
  eventually 5 smoke_idle || true
  log "message: $(smoke message)"
  sleep 0.3
  shot 14-arrangements-created
}

save_and_check() {
  local file=$E2E_CONFIG_HOME/hyprslots/slots.lua
  expect_eq "w does not save" "ignored" "$(smoke press w)"
  press_keys Ctrl+s
  if eventually 5 state_is .dirty false; then
    pass "Ctrl+S saved"
  else
    fail "still unsaved: $(smoke message)"
  fi
  local saved
  saved=$(cat "$file")
  for want in 'aside = {},' 'description = "the editor",' 'aside = "t-right",' 'main = "t-main",' \
    'main = "h[main:2, v[aside, side:3]]"' 'desk = {' 'solo = {'; do
    if grep -qF "$want" <<<"$saved"; then
      pass "slots.lua holds $want"
    else
      fail "slots.lua lacks $want:"$'\n'"$saved"
    fi
  done
}

# More of the Arrangements tab, unsaved: r renames desk to home, p is refused
# (this config.lua does not read pinned from slots.lua), c copies the
# default trees into home, e renames its screen role, x deletes solo.
arrangement_edits() {
  press_keys r
  press_text home
  press_keys Return
  if eventually 5 state_is .arrangement home; then
    pass "r renamed desk to home, still running"
  else
    fail "home is not running: $(api_state | jq -r .arrangement); $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys p m
  eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == *config.lua* ]]" ||
    fail "p was not refused: $(smoke message)"
  log "p: $(smoke message)"
  press_keys c d
  expect_eq "c asks first" "Replace every tree of 'home' with the default trees? (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.arrangements.home.desks["3"].main.tree' "h[aside, main]"; then
    pass "c, d, y gave home the default trees"
  else
    fail "home's tree is $(api_state | jq -r '.arrangements.home.desks["3"].main.tree'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys e m Backspace Backspace Backspace Backspace
  press_text big
  press_keys Return Return
  if eventually 5 state_is '.arrangements.home.desks["3"].big.tree' "h[aside, main]"; then
    pass "e renamed home's screen role main to big, its tree along"
  else
    fail "home is $(api_state | jq -c '.arrangements.home'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys Down x
  expect_eq "x asks first" "Delete arrangement 'solo'? It takes its trees for desks 3. (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.arrangements.solo' null; then
    pass "x, y deleted solo"
  else
    fail "solo is still there: $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "home still runs" "home" "$(api_state | jq -r .arrangement)"
  expect_eq "unsaved" "true" "$(api_state | jq -r .dirty)"
  sleep 0.3
  shot 15-arrangements-edited
}

# The bar widget (the plugin's bar-widget entry point) on the smoke's
# stand-in bar: its label follows the engine's state through the shared
# service (no poller of its own), a dot while edits are unsaved; a left
# click opens and closes the panel; the right-click menu's Save saves and
# Re-apply lays the desk out again; with the hyprslots global gone the
# widget turns red and says why, and comes back with it.
bar_widget() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "the widget loads" "ok" "$(smoke bar)"
  eventually 5 bash -c "[[ \$($watch barLabel) == 'dirty 󰕰 home · 3 •' ]]" || true
  expect_eq "it shows the running arrangement and desk, a dot for the unsaved edits" \
    "dirty 󰕰 home · 3 •" "$(smoke barLabel)"
  expect_eq "its tooltip says so" $'Hyprslots: home, desk 3 · unsaved edits\nClick: editor · Right-click: menu' \
    "$(smoke barTooltip)"
  sleep 0.3
  shot 17-bar-widget

  expect_eq "right click" "ok" "$(smoke barClick right)"
  expect_eq "opens the menu, Save on with unsaved edits" "open: arrange on, record on, save on, reload on" \
    "$(smoke barMenu)"
  sleep 0.5
  shot 18-bar-menu
  expect_eq "Save" "ok" "$(smoke barChoose save)"
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'normal 󰕰 home · 3' ]]"; then
    pass "the menu's Save saved: the dot is gone"
  else
    fail "after Save the widget shows $(smoke barLabel); dirty $(api_state | jq -r .dirty)"
  fi
  expect_eq "the menu closed" "closed: arrange on, record on, save off, reload on" "$(smoke barMenu)"
  eventually 5 bash -c "[[ \$($watch barRun) == *Saved* ]]" || true
  expect_eq "and the outcome is a notification" \
    "notify-send -a Hyprslots Hyprslots 'Saved $E2E_CONFIG_HOME/hyprslots/slots.lua.'" "$(smoke barRun)"
  eventually 5 smoke_idle || true

  expect_eq "Re-apply layout" "ok" "$(smoke barChoose arrange)"
  if eventually 5 bash -c "[[ \$($watch barRun) == *'Desk 3 laid out again.'* ]]"; then
    pass "Re-apply ran desk 3, then arrange"
  else
    fail "Re-apply: $(smoke barRun); errors: $(smoke errors)"
  fi
  eventually 5 smoke_idle || true

  expect_eq "the panel is closed" "no" "$(smoke ready)"
  expect_eq "left click" "ok" "$(smoke barClick left)"
  if eventually 5 smoke_ready; then
    pass "a left click opened the panel"
  else
    fail "the panel did not open: $(smoke errors)"
  fi
  sleep 0.5
  shot 19-bar-panel
  expect_eq "left click again" "ok" "$(smoke barClick left)"
  expect_eq "closed it" "no" "$(smoke ready)"

  # Record opens the panel on the Layout tab's record flow (R): the preview
  # asks before applying anything; n keeps the tree.
  expect_eq "Record desk" "ok" "$(smoke barChoose record)"
  if eventually 5 bash -c "[[ \$($watch message) == Recorded*'Apply it?'* ]]"; then
    pass "Record opened the panel on the record preview"
  else
    fail "Record: ready $(smoke ready), message $(smoke message)"
  fi
  log "record: $(smoke message)"
  sleep 0.3
  shot 20-bar-record
  press_keys n Escape
  expect_eq "nothing applied" "false" "$(api_state | jq -r .dirty)"
  expect_eq "the panel closed" "no" "$(smoke ready)"

  # hyprslots not loaded: the next state read fails, the widget turns red.
  repl 'hyprslots_smoke = hyprslots; hyprslots = nil; return "gone"' >/dev/null
  repl 'hl.dispatch(hl.dsp.event("hyprslots changed 900")); return "ok"' >/dev/null
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'error '* ]]"; then
    pass "with hyprslots gone the widget is an error"
  else
    fail "the widget shows $(smoke barLabel)"
  fi
  local tooltip
  tooltip=$(smoke barTooltip)
  if [[ $tooltip == "Hyprslots: "*"attempt to index a nil value (global 'hyprslots')"* ]]; then
    pass "its tooltip names the error"
  else
    fail "tooltip: $tooltip"
  fi
  expect_eq "only Reload is offered" "closed: arrange off, record off, save off, reload on" "$(smoke barMenu)"
  sleep 0.3
  shot 21-bar-error
  repl 'hyprslots = hyprslots_smoke; hyprslots_smoke = nil; return "back"' >/dev/null
  repl 'hl.dispatch(hl.dsp.event("hyprslots changed 901")); return "ok"' >/dev/null
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'normal 󰕰 home · 3' ]]"; then
    pass "with hyprslots back the widget is too"
  else
    fail "the widget shows $(smoke barLabel)"
  fi
}

test_body() {
  for tool in qs grim wtype; do
    command -v "$tool" >/dev/null || harness_fail "the editor smoke needs $tool"
  done
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  # Given t-main and t-right in their slots on desk 3 and a stray window there.
  spawn_and_wait t-main
  spawn_and_wait t-right
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")')"
  spawn_and_wait t-stray
  settle
  local stray
  stray=$(address_of t-stray)
  expect_eq "the stray has no slot" "null" "$(assignment_of "$stray")"
  log "state read takes $(time_ms api_state) ms (budget 250 ms inside Hyprland)"

  # When the editor opens on the test instance.
  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5 # let the overlay reveal itself (it waits for the output's scale)
  shot 1-open

  # Then `a` on the stray puts it into slot side and makes its spec desk 3's
  # for side, as real key presses: Down x3 (main, right, the side
  # placeholder, stray), a, then s for side.
  expect_eq "the panel opens on desk 3, main selected" "slot main t-main" "$(smoke selection)"
  keys_in_background -k Down -k Down -k Down -s 1000 -k a -s 1500 -k s
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  eventually 5 bash -c "[[ \$($watch selection) == 'none - t-stray' ]]"
  expect_eq "Down x3 selects the stray" "none - t-stray" "$(smoke selection)"
  eventually 3 bash -c "[[ \$($watch message) == 'Assign to desk 3 slot'* ]]" || fail "a opened no prompt: $(smoke message)"
  expect_eq "a prompts with the global slots on desk 3" \
    "Assign to desk 3 slot (takes its spec): (m)ain, (r)ight, (s)ide? [Esc] cancel   → main" "$(smoke message)"
  wait "$SMOKE_WTYPE_PID" 2>/dev/null
  if eventually 5 assigned_to_side "$stray"; then
    pass "keys a, s put the stray in side"
  else
    fail "the stray is not in side: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  expect_eq "and made its spec desk 3's for side" "t-stray" "$(api_state | jq -r '.specs["3"].side')"
  expect_eq "in memory until saved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  settle
  sleep 0.3
  shot 2-assigned
  expect_client t-stray 3 1280 540 640 540
  expect_eq "the row says so" "slot side t-stray" "$(smoke selection)"
  log "message: $(smoke message)"

  # And u, y (through the panel's press() hook) takes it out again, the
  # spec a took from it with it: side is left empty, not Missing t-stray.
  expect_eq "u" "ok" "$(smoke press u)"
  expect_eq "u asks, naming the spec it clears" \
    "Unassign t-stray from side and clear desk 3's spec for it (t-stray)? (the slot is left empty) (y/n)" "$(smoke message)"
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 unassigned "$stray"; then
    pass "u, y unassigned the stray"
  else
    fail "the stray is still assigned: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  if eventually 5 state_is '.specs["3"].side' null; then
    pass "and cleared desk 3's spec for side"
  else
    fail "side's spec is $(api_state | jq -r '.specs["3"].side'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys Up
  expect_eq "side's row is empty: no spec, nothing Missing" "empty side -" "$(smoke selection)"
  expect_eq "side stays a slot" "main right side" "$(slot_names)"
  sleep 0.3
  shot 3-unassigned

  # c clears the spec of a slot whose window is not open (a Missing row);
  # side waits for t-side again (set through the api), c, y clears it.
  repl 'return hyprslots.api.call("set_spec", "{\"desk\": 3, \"slot\": \"side\", \"spec\": \"t-side\"}")' >/dev/null
  eventually 5 bash -c "[[ \$($watch selection) == 'missing side t-side' ]]" || true
  expect_eq "side is Missing t-side" "missing side t-side" "$(smoke selection)"
  press_keys c
  expect_eq "c asks first" "Clear desk 3's spec for side (t-side)? (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.specs["3"].side' null; then
    pass "c, y cleared desk 3's spec for side"
  else
    fail "side's spec is $(api_state | jq -r '.specs["3"].side'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true

  # [ pages back to every window, 3 jumps to desk 3's page, 7 has none.
  press_keys [
  expect_eq "[ pages to every window" "slot main t-main" "$(smoke selection)"
  press_keys 7
  expect_eq "7: desk 7 has no page" "Desk 7 has no slots: no tree places one and it has no spec." "$(smoke message)"
  press_keys 3
  expect_eq "3 jumps to desk 3's page" "slot main t-main" "$(smoke selection)"

  # The Layout tab edits desk 3's tree as a draft: / flips it, r takes a
  # typed ratio, w applies, Ctrl+S saves (s is no key of the view any more).
  expect_eq "Tab" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 4-layout-tab
  expect_eq "the Layout view opens on desk 3's main screen, main selected" "main main" "$(smoke selection)"
  expect_eq "its draft is the tree in force" "main: h[main:2, v[right, side]]" "$(smoke layout)"
  expect_eq "/" "ok" "$(smoke press /)"
  expect_eq "/ flips every split, in the draft" "main: v[main:2, h[right, side]] *" "$(smoke layout)"
  expect_eq "r" "ok" "$(smoke press r)"
  expect_eq "r prompts with the current ratio" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: ▏" "$(smoke message)"
  # A ratio the grammar refuses opens the prompt again, the entry kept.
  press_text 2:1:1
  press_keys Return
  expect_eq "a refused ratio reopens its prompt with the refusal" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: 2:1:1▏ | expected 2 values for the outer container, got 3" \
    "$(smoke message)"
  press_keys Backspace Backspace
  local c ratio_entry='[1:3]'
  for ((i = 0; i < ${#ratio_entry}; i++)); do
    c=${ratio_entry:i:1}
    [[ $(smoke press "$c") == ok ]] || fail "typing $c into the ratio prompt"
  done
  expect_eq "the prompt shows what was typed" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: 2:1[1:3]▏" "$(smoke message)"
  expect_eq "Return" "ok" "$(smoke press Return)"
  expect_eq "the ratio lands in the draft" "main: v[main:2, h[right, side:3]] *" "$(smoke layout)"
  expect_eq "nothing is applied yet" "h[main:2, v[right, side]]" "$(tree_in_force)"
  sleep 0.3
  shot 5-layout-draft

  expect_eq "w" "ok" "$(smoke press w)"
  if eventually 5 tree_in_force_is 'v[main:2, h[right, side:3]]'; then
    pass "w applied the draft (set_trees)"
  else
    fail "the tree in force is $(tree_in_force); editor: $(smoke message) $(smoke errors)"
  fi
  expect_eq "applied, not saved" "true" "$(api_state | jq -r '.dirty')"
  eventually 5 smoke_idle || true
  settle
  # h[v[main:2, h[right, side:3]]:3, *:1] with side absent: the tree takes
  # 1440 px, the overflow column (the unassigned stray) 480.
  expect_client t-main 3 0 0 1440 720
  expect_client t-right 3 0 720 1440 360
  expect_client t-stray 3 1440 0 480 1080
  expect_eq "the draft is clean again" "main: v[main:2, h[right, side:3]]" "$(smoke layout)"
  sleep 0.3
  shot 6-layout-applied

  expect_eq "S does not save" "ignored" "$(smoke press S)"
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  if eventually 5 saved; then
    pass "Ctrl+S saved"
  else
    fail "still dirty after Ctrl+S: $(smoke message) $(smoke errors)"
  fi
  if grep -qF 'main = "v[main:2, h[right, side:3]]"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "slots.lua holds the edited tree"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi
  if grep -qE 'side = "t-' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    fail "slots.lua still has a spec for side: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  else
    pass "slots.lua has no spec for side after u"
  fi
  log "message: $(smoke message)"
  sleep 0.3
  shot 7-layout-saved

  # A scroll branch in the draft (t makes the whole tree full-width
  # scrolling columns in slot order, a filmstrip, l moves right a column
  # on), then d, y puts the screen back to what slots.lua holds (api reset).
  smoke press Down >/dev/null
  expect_eq "Down selects right" "main right" "$(smoke selection)"
  smoke press t >/dev/null
  expect_eq "t makes the tree a scroll branch" "main: scroll[main, right, side] *" "$(smoke layout)"
  smoke press l >/dev/null
  expect_eq "l moves right a column on" "main: scroll[main, side, right] *" "$(smoke layout)"
  sleep 0.3
  shot 8-layout-scroll
  smoke press d >/dev/null
  expect_eq "d asks first" "Put desk 3 on main back to the tree slots.lua holds? (y/n)" "$(smoke message)"
  smoke press y >/dev/null
  local clean='main: v[main:2, h[right, side:3]]'
  if eventually 5 bash -c "[[ \$($watch layout) == '$clean' ]]"; then
    pass "d, y dropped the draft: back to slots.lua"
  else
    fail "after d, y the draft is $(smoke layout): $(smoke message) $(smoke errors)"
  fi
  expect_eq "nothing unsaved" "false" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true

  # Ctrl+S with an edited draft applies it first, then saves.
  expect_eq "/" "ok" "$(smoke press /)"
  expect_eq "/ flips the draft back" "main: h[main:2, v[right, side:3]] *" "$(smoke layout)"
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  if eventually 5 bash -c "[[ \$($watch layout) == 'main: h[main:2, v[right, side:3]]' ]]" && eventually 5 saved; then
    pass "Ctrl+S applied the draft and saved it"
  else
    fail "after Ctrl+S: draft $(smoke layout), tree $(tree_in_force), dirty $(api_state | jq -r .dirty): $(smoke message)"
  fi
  expect_eq "the tree in force is the draft" "h[main:2, v[right, side:3]]" "$(tree_in_force)"
  if grep -qF 'main = "h[main:2, v[right, side:3]]"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "slots.lua holds it"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi
  eventually 5 smoke_idle || true

  # ] and the digits switch the desk (the arrows stay the picture's): desk 4
  # has no tree yet, 3 jumps back.
  expect_eq "]" "ok" "$(smoke press ])"
  expect_eq "] edits desk 4" "Editing desk 4 of solo." "$(smoke message)"
  expect_eq "which has no tree here" "main: -" "$(smoke layout)"
  sleep 0.3
  shot 8b-layout-desk-4
  expect_eq "3" "ok" "$(smoke press 3)"
  expect_eq "3 jumps back to desk 3" "Editing desk 3 of solo." "$(smoke message)"
  expect_eq "its tree" "main: h[main:2, v[right, side:3]]" "$(smoke layout)"

  layout_slots
  arrangements_view
  save_and_check
  arrangement_edits

  # The Layout tab was on solo, which is gone: it follows the running home,
  # whose screen role is big now.
  press_keys Tab Tab
  expect_eq "the Layout tab follows the running arrangement" "big: h[aside, main]" "$(smoke layout)"
  expect_eq "and says so" "Arrangement 'solo' is gone; editing desk 3 of home." "$(smoke message)"
  sleep 0.3
  shot 16-layout-follows

  expect_eq "Escape" "ok" "$(smoke press Escape)"
  expect_eq "the panel is closed" "no" "$(smoke ready)"

  # The last failed call is the pin the Arrangements tab was refused on
  # purpose (the malformed spec before it was too).
  expect_eq "no editor errors but the refused pin" \
    " | config.lua does not take pinned from slots.lua, so the edit would change nothing; change it in config.lua" \
    "$(smoke errors)"
  bar_widget

  log "assign round trip takes $(time_ms repl "return hyprslots.api.call(\"assign\", \"{\\\"address\\\":\\\"$stray\\\",\\\"desk\\\":3,\\\"slot\\\":\\\"side\\\"}\")") ms"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
