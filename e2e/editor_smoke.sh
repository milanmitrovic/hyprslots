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
# panel's press() hook, and api state must show both. Screenshots of the
# nested compositor go to .e2e-tmp/editor-smoke-*.png.
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
  expect_eq "a prompts with the desk's slots" "Assign to slot: (m)ain, (r)ight, (s)ide? [Esc] cancel" "$(smoke message)"
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

  # The other tabs show, read-only, what D2/D3 will edit; Esc closes.
  expect_eq "Tab" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 4-layout-tab
  expect_eq "Escape" "ok" "$(smoke press Escape)"
  expect_eq "the panel is closed" "no" "$(smoke ready)"

  expect_eq "no editor errors" "" "$(smoke errors)"
  log "assign round trip takes $(time_ms repl "return hyprslots.api.call(\"assign\", \"{\\\"address\\\":\\\"$stray\\\",\\\"desk\\\":3,\\\"slot\\\":\\\"side\\\"}\")") ms"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
