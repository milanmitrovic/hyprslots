# Editor smoke (opt-in: not a *_test.sh, so `make e2e` skips it; run it with
# `make e2e-editor` or `e2e/run.sh e2e/editor_smoke.sh`). Needs qs
# (Quickshell), grim, and Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# The editor plugin (editor/) runs in Quickshell on the TEST instance, never
# in the live shell: e2e/editor/shell.qml loads the plugin's Engine.qml and
# Panel.qml standalone, with WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE
# of the nested Hyprland and the harness's private XDG_RUNTIME_DIR. The panel
# is opened, a stray window is put into a slot with real key presses (wtype,
# through the panel's keyboard handling), then taken out again with the
# panel's press() hook, and api state must show both. Then the Layout tab
# flips desk 3's tree, takes a typed ratio, applies it (api state and the
# windows' geometry must follow) and saves it (slots.lua must hold it); the
# Slots tab renames a slot (the trees follow) and sets a spec (a malformed one
# is refused in its prompt first), the Arrangements tab creates one for the
# connected screen, and a save must write all of it to slots.lua.
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
return { slots = data.slots, arrangements = data.arrangements }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = {
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

assigned_to_side() { [[ $(assignment_of "$1") == '{"desk":3,"manual":true,"slot":"side"}' ]]; }
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

notes_taken() { [[ $(api_state | jq -r '.slots["3"].notes') == t-* ]]; }

state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }

# The Slots tab: rename right (every tree that places it is rewritten), a
# refused spec shows in its prompt, then a good one.
slots_view() {
  expect_eq "Tab to Slots" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 9-slots
  # Desk 3's slots by name: main, right, side; main selected.
  press_keys Down r
  expect_eq "r prompts for the new name" "Rename 'right' to [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text aside
  press_keys Return
  if eventually 5 state_is '.slots["3"].aside' t-right; then
    pass "r renamed right to aside"
  else
    fail "right was not renamed: $(api_state | jq -c '.slots'); $(smoke message); errors: $(smoke errors)"
  fi
  expect_eq "the tree is rewritten" "h[main:2, v[aside, side:3]]" \
    "$(api_state | jq -r '.arrangements.solo.desks["3"].main.tree')"
  expect_eq "the edit is unsaved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  log "message: $(smoke message)"

  # side: s, clear the spec, a malformed one is refused in place, then fixed.
  press_keys Down Down s
  press_keys Backspace Backspace Backspace Backspace Backspace Backspace
  press_text "[Tag"
  press_keys Return
  eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == *\"closing ']'\"* ]]" ||
    fail "the refused spec did not show in its prompt: $(smoke message)"
  log "refusal: $(smoke message)"
  sleep 0.3
  shot 10-slots-refused
  press_keys Backspace Backspace Backspace Backspace
  press_text "foot/notes"
  press_keys Return
  if eventually 5 state_is '.slots["3"].side' foot/notes; then
    pass "s set side's spec to foot/notes"
  else
    fail "side's spec is $(api_state | jq -r '.slots["3"].side'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true

  # a adds notes (spec, description), t takes its spec from the first
  # window offered, d deletes it again; e describes main.
  press_keys a
  press_text notes
  press_keys Return
  press_text foot
  press_keys Return
  press_text scratch
  press_keys Return
  if eventually 5 state_is '.slots["3"].notes + " " + .descriptions["3"].notes' "foot scratch"; then
    pass "a added notes with its spec and description"
  else
    fail "notes was not added: $(api_state | jq -c '{slots, descriptions}'); $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys t 1
  if eventually 5 notes_taken; then
    pass "t took notes' spec from a window: $(api_state | jq -r '.slots["3"].notes')"
  else
    fail "notes' spec is $(api_state | jq -r '.slots["3"].notes'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys d
  expect_eq "d asks first" "Delete slot 'notes' from desk 3? (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.slots["3"].notes' null; then
    pass "d, y deleted notes"
  else
    fail "notes is still there: $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys Up Up Up Down e
  press_text "the editor"
  press_keys Return
  if eventually 5 state_is '.descriptions["3"].main' "the editor"; then
    pass "e described main"
  else
    fail "main's description is $(api_state | jq -c '.descriptions'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  sleep 0.3
  shot 11-slots-edited
}

# The Arrangements tab: n makes "desk" for the connected screen, copying
# solo's trees; it sorts before solo, so these monitors run it.
arrangements_view() {
  expect_eq "Tab to Arrangements" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 12-arrangements
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
  shot 13-arrangements-created
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
  for want in 'aside = "t-right"' 'side = "foot/notes"' 'main = "h[main:2, v[aside, side:3]]"' 'desk = {' 'solo = {' \
    'descriptions = {' 'main = "the editor"'; do
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
  if eventually 5 state_is '.arrangements.home.desks["3"].main.tree' "h[aside, main, side]"; then
    pass "c, d, y gave home the default trees"
  else
    fail "home's tree is $(api_state | jq -r '.arrangements.home.desks["3"].main.tree'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys e m Backspace Backspace Backspace Backspace
  press_text big
  press_keys Return Return
  if eventually 5 state_is '.arrangements.home.desks["3"].big.tree' "h[aside, main, side]"; then
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
  shot 14-arrangements-edited
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

  # Then `a` on the stray puts it into slot side, as real key presses: Down
  # x3 (main, right, the side placeholder, stray), a, then s for side.
  expect_eq "the panel opens on desk 3, main selected" "slot main t-main" "$(smoke selection)"
  keys_in_background -k Down -k Down -k Down -s 1000 -k a -s 1500 -k s
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  eventually 5 bash -c "[[ \$($watch selection) == 'none - t-stray' ]]"
  expect_eq "Down x3 selects the stray" "none - t-stray" "$(smoke selection)"
  eventually 3 bash -c "[[ \$($watch message) == 'Assign to slot:'* ]]" || fail "a opened no prompt: $(smoke message)"
  expect_eq "a prompts with the desk's slots" "Assign to slot: (m)ain, (r)ight, (s)ide? [Esc] cancel   → main" "$(smoke message)"
  wait "$SMOKE_WTYPE_PID" 2>/dev/null
  if eventually 5 assigned_to_side "$stray"; then
    pass "keys a, s assigned the stray to side by hand"
  else
    fail "the stray is not in side: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  eventually 5 smoke_idle || true
  settle
  sleep 0.3
  shot 2-assigned
  expect_client t-stray 3 1280 540 640 540
  expect_eq "the row says so" "manual side t-stray" "$(smoke selection)"
  log "message: $(smoke message)"

  # And u, y (through the panel's press() hook) takes it out again.
  expect_eq "u" "ok" "$(smoke press u)"
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 unassigned "$stray"; then
    pass "u, y unassigned the stray"
  else
    fail "the stray is still assigned: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  eventually 5 smoke_idle || true
  sleep 0.3
  shot 3-unassigned

  # The Layout tab edits desk 3's tree as a draft: / flips it, r takes a
  # typed ratio, t refuses what an accordion cannot hold, w applies, Ctrl+S
  # saves (s is no key of the view any more).
  expect_eq "Tab" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 4-layout-tab
  expect_eq "the Layout view opens on desk 3's main screen, main selected" "main main" "$(smoke selection)"
  expect_eq "its draft is the tree in force" "main: h[main:2, v[right, side]]" "$(smoke layout)"
  expect_eq "/" "ok" "$(smoke press /)"
  expect_eq "/ flips every split, in the draft" "main: v[main:2, h[right, side]] *" "$(smoke layout)"
  smoke press t >/dev/null
  expect_eq "t on main refuses: its container holds a split" \
    "an accordion holds slots only, found 'h[' inside it" "$(smoke message)"
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

  expect_eq "s does not save" "ignored" "$(smoke press s)"
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
  log "message: $(smoke message)"
  sleep 0.3
  shot 7-layout-saved

  # An accordion in the draft (Down selects right, t stacks its container),
  # then d, y puts the screen back to what slots.lua holds (api reset).
  smoke press Down >/dev/null
  expect_eq "Down selects right" "main right" "$(smoke selection)"
  smoke press t >/dev/null
  expect_eq "t stacks right's container" "main: v[main:2, a[right, side]] *" "$(smoke layout)"
  sleep 0.3
  shot 8-layout-accordion
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

  slots_view
  arrangements_view
  save_and_check
  arrangement_edits

  # The Layout tab was on solo, which is gone: it follows the running home,
  # whose screen role is big now.
  press_keys Tab Tab
  expect_eq "the Layout tab follows the running arrangement" "big: h[aside, main, side]" "$(smoke layout)"
  expect_eq "and says so" "Arrangement 'solo' is gone; editing desk 3 of home." "$(smoke message)"
  sleep 0.3
  shot 15-layout-follows

  expect_eq "Escape" "ok" "$(smoke press Escape)"
  expect_eq "the panel is closed" "no" "$(smoke ready)"

  # The last failed call is the pin the Arrangements tab was refused on
  # purpose (the malformed spec before it was too).
  expect_eq "no editor errors but the refused pin" \
    " | config.lua does not take pinned from slots.lua, so the edit would change nothing; change it in config.lua" \
    "$(smoke errors)"
  log "assign round trip takes $(time_ms repl "return hyprslots.api.call(\"assign\", \"{\\\"address\\\":\\\"$stray\\\",\\\"desk\\\":3,\\\"slot\\\":\\\"side\\\"}\")") ms"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
