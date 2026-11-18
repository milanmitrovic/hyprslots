# The Desk tab's desk maps (docs/design.md §8, §9) in Quickshell on the
# nested Hyprland (part of `make e2e-editor`; needs qs, grim, and Omarchy's
# shell modules, as e2e/editor_smoke.sh does). SMOKE_THEME=<an Omarchy theme
# dir> runs it in that theme (the screenshots then carry its name).
#
# Screens: HEADLESS-2, 1920x1080 at 0,360 (screen 1, Omarchy block 0);
# HEADLESS-3, 2560x1440 at 1920,0 (screen 2, block 1): two sizes, offset.
# Desks: dual (both, listed HEADLESS-3 first: the map numbers by position,
# not by list), solo (HEADLESS-2 alone) and office (two monitors never
# connected). The engine records dual's geometry in slots.lua at once (no
# edit pending); the Desk tab draws dual's two screens in the accent where
# they are, solo's one, office's as two equal boxes side by side; hovering
# a map names its screens. Unplugging HEADLESS-3 makes solo active, and
# dual's map then shows screen 2 outlined, where it was recorded.
# Screenshots: .e2e-tmp/editor-desk-map[-<theme>]-*.png.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x360", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "2560x1440@60", position = "1920x0", scale = 1 })
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = { key = "m" }, side = { key = "s" } },
  specs = { [3] = { main = "t-main", side = "t-side" } },
  desks = {
    dual = { monitors = { "HEADLESS-3", "HEADLESS-2" }, layout = "dual" },
    solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
    office = { monitors = { "DP-7", "DP-8" }, layout = "dual" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "main", [2] = "side" } },
    solo = { screens = 1, default = { [1] = "h[main, side]" } },
  },
}
LUA
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SHOT_NAME=desk-map
SHOT_SETTLE=0.3

# One desk's part of `smoke deskMaps`: "<n> solid|outlined <x>,<y> <w>x<h>, ...".
desk_map() { smoke deskMaps | tr ';' '\n' | sed -n "s/^ *$1\**: //p"; }

# Desk $1's entry in slots.lua, as serialize writes it.
desk_block() { awk -v d="    $1 = {" '$0 == d { on = 1 } on { print } on && /^    },$/ { exit }' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; }

# The drawn rectangle of screen $2 of desk $1: "<x> <y> <w> <h>" on the screen.
drawn() { smoke bounds "deskmap:$1:$2"; }

# The real pointer over the panel's control named $1, without a click.
# vpointer's absolute motion spans the box around every output (smoke_click
# takes the first output's size, right for one output at 0,0 only), so the
# point is made relative to that box and the box's size given (scale 1).
hover() {
  local point x y box
  point=$(smoke point "$1")
  if [[ ! $point =~ ^-?[0-9]+\ -?[0-9]+$ ]]; then
    fail "no control '$1' to hover (got '$point')"
    return 1
  fi
  read -r x y <<<"$point"
  box=$(hc monitors -j | jq -r --argjson x "$x" --argjson y "$y" \
    '(map(.x) | min) as $l | (map(.y) | min) as $t
     | "\($x - $l) \($y - $t) \((map(.x + .width) | max) - $l) \((map(.y + .height) | max) - $t)"')
  # shellcheck disable=SC2086
  vpointer_do $box move || harness_fail "vpointer failed (see $E2E_DIR/vpointer.log)"
}

# The desk map's tip of desk $2 (row $1) hides nothing on its row: it starts
# below the row, and its name cell and map show whole.
tip_clear_of_row() {
  local tx ty tw th rx ry rw rh nx ny nw nh
  read -r tx ty tw th <<<"$(smoke bounds "deskmaptip:$2")"
  read -r rx ry rw rh <<<"$(smoke bounds "row:$1")"
  read -r nx ny nw nh <<<"$(smoke bounds "deskname:$2")"
  log "tip at $tx,$ty ${tw}x$th; row $1 at $rx,$ry ${rw}x$rh; name at $nx,$ny ${nw}x$nh"
  if [[ -n $ty && -n $ry ]] && ((ty >= ry + rh)); then pass "$2's tip shows under its row, hiding nothing on it"
  else fail "$2's tip at '$tx $ty $tw $th', its row at '$rx $ry $rw $rh'"; fi
  if [[ -n $ny ]] && ((ty >= ny + nh || ty + th <= ny || tx >= nx + nw || tx + tw <= nx)); then pass "and clear of $2's name"
  else fail "$2's tip over its name: tip '$tx $ty $tw $th', name '$nx $ny $nw $nh'"; fi
}

test_body() {
  for tool in qs grim; do
    command -v "$tool" >/dev/null || harness_fail "the desk map scenario needs $tool"
  done
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  expect_eq "desk dual, both screens" "dual" "$(api_state | jq -r .desk)"

  # the geometry, recorded quietly: nothing else was unsaved
  local data=$E2E_CONFIG_HOME/hyprslots/slots.lua
  if eventually 5 grep -q 'geometry' "$data"; then pass "dual's geometry went into slots.lua"
  else fail "no geometry in slots.lua: $(cat "$data")"; fi
  expect_eq "HEADLESS-2's box" '["HEADLESS-2"] = { x = 0, y = 360, w = 1920, h = 1080 },' \
    "$(desk_block dual | grep -o '\["HEADLESS-2"\] = {[^}]*},')"
  expect_eq "HEADLESS-3's box" '["HEADLESS-3"] = { x = 1920, y = 0, w = 2560, h = 1440 },' \
    "$(desk_block dual | grep -o '\["HEADLESS-3"\] = {[^}]*},')"
  expect_eq "not dirty" "false" "$(api_state | jq -r .dirty)"
  expect_eq "state: dual's map, one box per monitor it lists" \
    '[{"h":1440,"screen":2,"w":2560,"x":1920,"y":0},{"h":1080,"screen":1,"w":1920,"x":0,"y":360}]' \
    "$(api_state | jq -c '.desks.dual.geometry | map(to_entries | sort_by(.key) | from_entries)')"

  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5
  smoke press Tab >/dev/null
  smoke press Tab >/dev/null
  eventually 3 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke tabs) == *'| Desk' ]]" || fail "tabs: $(smoke tabs)"
  log "desk maps: $(smoke deskMaps)"
  # dual lists HEADLESS-3 first, but its monitors read in screen order, as its map
  if [[ $(smoke deskMonitors) == *"dual: 1 · HEADLESS-2 + 2 · HEADLESS-3;"* ]]; then
    pass "dual's monitors in screen order: $(smoke deskMonitors)"
  else
    fail "desk monitors: $(smoke deskMonitors)"
  fi

  # dual: screen 1 (HEADLESS-2, lower and narrower) left, screen 2 right and taller
  expect_eq "dual's map" "1 solid 0,6 31x17, 2 solid 31,0 41x23" "$(desk_map dual)"
  expect_eq "solo's map: one screen" "1 solid 0,0 64x36" "$(desk_map solo)"
  expect_eq "office's map: never seen, equal boxes side by side, outlined" \
    "1 outlined 0,0 36x20, 2 outlined 36,0 36x20" "$(desk_map office)"
  if [[ $(smoke deskMaps) == *'dual*:'* ]]; then pass "dual is the active desk"; else fail "$(smoke deskMaps)"; fi

  # the drawn rectangles, as arranged: screen 2 right of screen 1, taller, its top above
  local x1 y1 w1 h1 x2 y2 w2 h2
  read -r x1 y1 w1 h1 <<<"$(drawn dual 1)"
  read -r x2 y2 w2 h2 <<<"$(drawn dual 2)"
  log "drawn: screen 1 at $x1,$y1 ${w1}x$h1; screen 2 at $x2,$y2 ${w2}x$h2"
  if [[ -n $x1 && -n $x2 ]] && ((x2 > x1 + w1 - 1 && y2 < y1 && h2 > h1 && w2 > w1)); then
    pass "dual's two screens are drawn side by side, the second larger and higher"
  else
    fail "dual's drawn screens: '$(drawn dual 1)' and '$(drawn dual 2)'"
  fi
  if [[ -z $(drawn dual 3) ]]; then pass "and no third"; else fail "a third screen: $(drawn dual 3)"; fi

  # hovering the map names its screens, under the row: nothing on it hidden
  hover deskmap:dual
  if eventually 3 bash -c "[[ -n \$(qs ipc --pid $SMOKE_QS_PID call smoke bounds deskmaptip:dual) ]]"; then
    pass "hovering dual's map shows its tip"
  else
    fail "no tip over dual's map"
  fi
  tip_clear_of_row 0 dual
  shot 1-two-screens

  # unplug HEADLESS-3: solo is active, dual's screen 2 outlined where it was recorded
  output_remove HEADLESS-3
  eventually 5 state_is .desk solo || fail "desk after the unplug: $(api_state | jq -r .desk)"
  eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke deskMaps) == *'solo*:'* ]]" ||
    fail "the panel did not follow: $(smoke deskMaps)"
  log "desk maps: $(smoke deskMaps)"
  expect_eq "dual's map after the unplug: screen 2 outlined" "1 solid 0,6 31x17, 2 outlined 31,0 41x23" "$(desk_map dual)"
  expect_eq "solo's map" "1 solid 0,0 64x36" "$(desk_map solo)"
  if eventually 5 grep -qF '["HEADLESS-2"] = { x = 0, y = 0, w = 1920, h = 1080 },' "$data"; then
    pass "solo's geometry recorded too"
  else
    fail "solo's geometry: $(cat "$data")"
  fi
  expect_eq "dual's kept" '["HEADLESS-3"] = { x = 1920, y = 0, w = 2560, h = 1440 },' \
    "$(desk_block dual | grep -o '\["HEADLESS-3"\] = {[^}]*},')"
  expect_eq "still not dirty" "false" "$(api_state | jq -r .dirty)"
  hover deskmap:dual
  if eventually 3 bash -c "[[ -n \$(qs ipc --pid $SMOKE_QS_PID call smoke bounds deskmaptip:dual) ]]"; then
    pass "hovering dual's map still shows its tip"
  else
    fail "no tip over dual's map after the unplug"
  fi
  tip_clear_of_row 0 dual
  shot 2-unplugged
}
