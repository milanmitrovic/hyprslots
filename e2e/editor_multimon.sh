# Editor on two screens (opt-in: not a *_test.sh, so `make e2e` skips it;
# run it with `make e2e-editor-multimon` or `e2e/run.sh
# e2e/editor_multimon.sh`). Needs qs, grim and Omarchy's shell modules, as
# e2e/editor_smoke.sh does. It looks rather than tests: it opens the editor
# on a 2-screen desk and screenshots the Assignment tab, the Layout tab
# (All workspaces, workspace 3's tiles with either screen's pane active, and
# scroll half and full on both) and the Desk tab, into $MULTIMON_SHOTS
# (default .e2e-tmp/multimon/latest): each shot once with both outputs
# (<name>.png) and once with only the one the panel opens on
# (<name>-panel.png). Nothing is applied or saved. SMOKE_THEME works as in
# the smoke.
#
# Screens: HEADLESS-2, 1920x1080 at 0,0 (screen 1, Omarchy block 0:
# workspace N = id N); HEADLESS-3, 2560x1440 at 1920,0 (screen 2, block 1:
# workspace N = id 10+N). Desk dual (both) uses the 2-screen layout dual:
# workspace 3 h[main:2, right] on screen 1, v[side, chat] on screen 2; its
# shared trees h[main, right] and side. Desk solo (HEADLESS-2 alone) uses
# layout solo. Windows: t-main, t-right, t-side and t-chat in their slots on
# workspace 3, and t-stray in none.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "2560x1440@60", position = "1920x0", scale = 1 })
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts, workspaces = 9 }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = { key = "m" }, right = { key = "r" }, side = { key = "s" }, chat = { key = "c" } },
  specs = {
    [3] = { main = "t-main", right = "t-right", side = "t-side", chat = "t-chat" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
  },
  layouts = {
    dual = {
      screens = 2,
      default = { [1] = "h[main, right]", [2] = "side" },
      workspaces = { [3] = { [1] = "h[main:2, right]", [2] = "v[side, chat]" } },
    },
    solo = { screens = 1, default = { [1] = "h[main, right, side, chat]" } },
  },
}
LUA
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
MULTIMON_SHOTS=${MULTIMON_SHOTS:-$E2E_ROOT/.e2e-tmp/multimon/latest}

# Both outputs as one picture, and the one the panel is on.
shot() {
  local all=$MULTIMON_SHOTS/$1.png panel=$MULTIMON_SHOTS/$1-panel.png
  mkdir -p "$MULTIMON_SHOTS"
  rm -f "$all" "$panel"
  sleep 0.3
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim "$all" 2>>"$E2E_DIR/grim.log" &&
    WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$panel" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $all (and -panel)"
  else
    fail "grim could not take $all (see $E2E_DIR/grim.log)"
  fi
}

api_state() { repl 'return hyprslots.api.state()'; }

# Select leaves until one on screen $1 is selected ("<screen> <leaf>"),
# pressing $2 (Left or Right), at most eight times.
select_screen() {
  local i
  for ((i = 0; i < 8; i++)); do
    [[ $(smoke selection) == "$1 "* ]] && return 0
    smoke press "$2" >/dev/null
  done
  [[ $(smoke selection) == "$1 "* ]]
}

test_body() {
  for tool in qs grim; do
    command -v "$tool" >/dev/null || harness_fail "the multimon scenario needs $tool"
  done
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  expect_eq "desk with both screens" "dual" "$(api_state | jq -r .desk)"

  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  local class
  for class in t-main t-right t-side t-chat; do spawn_and_wait "$class"; done
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")')"
  spawn_and_wait t-stray
  settle
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  log "windows:"
  client_table | sed 's/^/    /'

  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5 # let the overlay reveal itself (it waits for the output's scale)
  log "header: $(smoke header)"
  log "assignment page: $(smoke assignmentPage); rows: $(smoke rows)"
  shot 1-assignment

  smoke press Tab >/dev/null
  log "layout strip: $(smoke layoutStrip); panes: $(smoke panes); trees: $(smoke layout)"
  shot 2-layout-all-workspaces

  smoke press 3 >/dev/null
  log "workspace 3: $(smoke layout); selection: $(smoke selection)"
  select_screen 1 Left || fail "no leaf on screen 1 selected: $(smoke selection)"
  shot 3-layout-tiles-screen1
  select_screen 2 Right || fail "no leaf on screen 2 selected: $(smoke selection)"
  log "selection: $(smoke selection)"
  shot 4-layout-tiles-screen2

  smoke press t >/dev/null
  log "t on screen 2: $(smoke layoutMode)"
  shot 5-layout-scroll-half-screen2
  smoke press t >/dev/null
  log "t again: $(smoke layoutMode)"
  shot 6-layout-scroll-full-screen2

  select_screen 1 Left || fail "no leaf on screen 1 selected: $(smoke selection)"
  smoke press t >/dev/null
  log "t on screen 1: $(smoke layoutMode); trees: $(smoke layout)"
  shot 7-layout-scroll-both

  smoke press Tab >/dev/null
  log "desks: $(smoke deskMonitors)"
  shot 8-desk

  expect_eq "nothing applied" "h[main:2, right]" "$(api_state | jq -r '.layouts.dual.workspaces["3"]["1"].tree')"
}
