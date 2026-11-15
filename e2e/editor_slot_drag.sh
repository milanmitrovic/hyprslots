# The Layout tab's slots dragged with the mouse (docs/design.md §9), in
# Quickshell on the nested Hyprland (part of `make e2e-editor`; needs qs,
# grim, and Omarchy's shell modules, as e2e/editor_smoke.sh does).
# SMOKE_THEME=<an Omarchy theme dir> runs it in that theme (the screenshots
# then carry its name).
#
# Screens: HEADLESS-2, 1920x1080 at 0,0 (screen 1, Omarchy block 0:
# workspace N = id N); HEADLESS-3, 2560x1440 at 1920,0 (screen 2, block 1:
# workspace N = id 10+N). Desk dual (both) uses layout dual: workspace 3 is
# h[main:2, right] on screen 1 and scroll:0.5[side, chat, mail] on screen
# 2. Windows t-main, t-right, t-side and t-chat are in their slots on
# workspace 3 (mail has none).
#
# With the real pointer: a click on a tile selects it; right dragged onto
# main's centre swaps them ("Swap with main", a screenshot mid-drag); Esc
# while one is held lets it go, nothing changed; main dragged onto the top
# edge band of right pairs them in a column ("Put above right", a
# screenshot); side dragged between chat and mail in screen 2's filmstrip
# reorders it ("Put between chat and mail", the insertion marker, a
# screenshot); chat dragged from screen 2's filmstrip onto the right edge
# of main on screen 1 moves it there ("Put right of main", a screenshot);
# other windows' place (o) dragged onto another screen is refused, saying
# why. w applies the drafts: t-chat goes to HEADLESS-2's workspace 3.
# Screenshots: .e2e-tmp/editor-slot-drag[-<theme>]-*.png.

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
  slots = { main = { key = "m" }, right = { key = "r" }, side = { key = "s" }, chat = { key = "c" }, mail = { key = "a" } },
  specs = {
    [3] = { main = "t-main", right = "t-right", side = "t-side", chat = "t-chat" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
  },
  layouts = {
    dual = {
      screens = 2,
      default = { [1] = "h[main, right]", [2] = "scroll[side, chat, mail]" },
      workspaces = { [3] = { [1] = "h[main:2, right]", [2] = "scroll:0.5[side, chat, mail]" } },
    },
  },
}
LUA
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp
SHOT_TAG=${SMOKE_THEME:+-$(basename "$SMOKE_THEME")}

api_state() { repl 'return hyprslots.api.state()'; }
state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }

shot() {
  local file=$SMOKE_SHOTS/editor-slot-drag$SHOT_TAG-$1.png
  rm -f "$file"
  sleep 0.3
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

# "<class>@<workspace id>" for every test window, sorted by class.
placement() {
  hc clients -j | jq -r '[.[] | select(.class | startswith("t-"))] | sort_by(.class) | map("\(.class)@\(.workspace.id)") | join(" ")'
}
placement_is() { [[ $(placement) == "$1" ]]; }
watch_is() { [[ $(smoke "$1") == "$2" ]]; }

# A point of the control named $1, at fractions $2 $3 of its width and
# height from its top left: "<x> <y>" on the screen.
point_in() {
  local x y w h
  read -r x y w h <<<"$(smoke bounds "$1")"
  [[ -n $w ]] || return 1
  awk -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v fx="$2" -v fy="$3" 'BEGIN { printf "%d %d\n", x + w * fx, y + h * fy }'
}

# Drag control $1 to the point $2 $3, hold it there until the slot drag
# reads $4 (else fail), take screenshot $5 when given, and let go.
drag_shows() {
  local name=$1 x=$2 y=$3 want=$4 picture=${5:-}
  smoke_drag "$name" "$x" "$y" 2500
  if eventually 3 watch_is slotDrag "$want"; then pass "held: $want"
  else fail "mid-drag from $name: '$(smoke slotDrag)' (wanted '$want')"; fi
  if [[ -n $picture ]]; then shot "$picture"; fi
  wait "$SMOKE_DRAG_PID"
  eventually 3 watch_is slotDrag '' || fail "the drag is still held: $(smoke slotDrag)"
}

test_body() {
  for tool in qs grim; do
    command -v "$tool" >/dev/null || harness_fail "the slot drag scenario needs $tool"
  done
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  expect_eq "desk dual, both screens" "dual" "$(api_state | jq -r .desk)"
  expect_eq "nothing unsaved on load" "false" "$(api_state | jq -r .dirty)"

  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  local class
  for class in t-main t-right t-side t-chat; do spawn_and_wait "$class"; done
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")')"
  eventually 10 placement_is 't-chat@13 t-main@3 t-right@3 t-side@13' || fail "windows before: $(placement)"
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null

  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5 # let the overlay reveal itself (it waits for the output's scale)
  smoke press Tab >/dev/null
  eventually 3 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke tabs) == *'| Layout' ]]" || fail "tabs: $(smoke tabs)"
  smoke press 3 >/dev/null
  local start='1: h[main:2, right]; 2: scroll:0.5[side, chat, mail]'
  expect_eq "workspace 3's trees" "$start" "$(smoke layout)"

  # A click (no drag) selects.
  smoke_click tile:1:right
  if eventually 3 watch_is selection '1 right'; then pass "a click on a tile selects it"
  else fail "after the click: $(smoke selection)"; fi
  expect_eq "a click changes no tree" "$start" "$(smoke layout)"

  local x y
  # Its centre: swap.
  read -r x y <<<"$(point_in tile:1:main 0.5 0.5)"
  drag_shows tile:1:right "$x" "$y" '1 right -> Swap with main' 1-swap-held
  local swapped='1: h[right, main:2] *; 2: scroll:0.5[side, chat, mail]'
  if eventually 3 watch_is layout "$swapped"; then pass "let go on main's centre: they swapped"
  else fail "after the swap: $(smoke layout); $(smoke message)"; fi
  expect_eq "the selection went with it" "1 right" "$(smoke selection)"
  if [[ $(smoke message) == 'Swapped right with main.'* ]]; then pass "the message says so"
  else fail "message: $(smoke message)"; fi

  # Esc while held: let go, nothing changed.
  read -r x y <<<"$(point_in tile:1:right 0.5 0.1)"
  smoke_drag tile:1:main "$x" "$y" 2500
  if eventually 3 watch_is slotDrag '1 main -> Put above right'; then pass "over right's top edge: Put above right"
  else fail "mid-drag onto right's top: '$(smoke slotDrag)'"; fi
  if [[ -n $(smoke bounds slotdrop:1:right:up) ]]; then pass "the top half of right lights up"
  else fail "no drop band on right"; fi
  if [[ -n $(smoke bounds slotGhost) ]]; then pass "the ghost follows the pointer"
  else fail "no ghost"; fi
  shot 2-edge-held
  expect_eq "Esc lets the drag go" "ok" "$(smoke press Escape)"
  expect_eq "no drag held after Esc" "" "$(smoke slotDrag)"
  wait "$SMOKE_DRAG_PID"
  expect_eq "Esc: nothing changed" "$swapped" "$(smoke layout)"

  # Its top edge band: main above right, in a column.
  drag_shows tile:1:main "$x" "$y" '1 main -> Put above right'
  local paired='1: v[main:2, right] *; 2: scroll:0.5[side, chat, mail]'
  if eventually 3 watch_is layout "$paired"; then pass "let go on right's top edge: main above it"
  else fail "after the edge drop: $(smoke layout); $(smoke message)"; fi

  # The filmstrip: side between chat and mail.
  read -r x y <<<"$(point_in tile:2:chat 1 0.5)"
  drag_shows tile:2:side "$x" "$y" '2 side -> Put between chat and mail' 3-filmstrip-held
  if [[ -z $(smoke bounds slotdrop:2:gap:2) ]]; then pass "the marker is gone after the drop"
  else fail "a marker still shows"; fi
  local reordered='1: v[main:2, right] *; 2: scroll:0.5[chat, side, mail] *'
  if eventually 3 watch_is layout "$reordered"; then pass "let go between chat and mail: the columns reordered"
  else fail "after the reorder: $(smoke layout); $(smoke message)"; fi
  expect_eq "the selection is the moved column" "2 side" "$(smoke selection)"

  # Across screens: chat from the filmstrip onto main's right edge.
  read -r x y <<<"$(point_in tile:1:main 0.92 0.5)"
  drag_shows tile:2:chat "$x" "$y" '2 chat -> Put right of main' 4-cross-screen-held
  local crossed='1: v[h[main, chat]:2, right] *; 2: scroll:0.5[side, mail] *'
  if eventually 3 watch_is layout "$crossed"; then pass "let go on screen 1: chat moved there, beside main"
  else fail "after the cross-screen drop: $(smoke layout); $(smoke message)"; fi
  expect_eq "the selection went to screen 1" "1 chat" "$(smoke selection)"
  shot 5-cross-screen-dropped

  # Other windows' place stays on its screen.
  smoke press o >/dev/null
  read -r x y <<<"$(point_in tile:2:side 0.5 0.5)"
  smoke_drag 'tile:1:*' "$x" "$y" 1500
  if eventually 3 watch_is slotDrag '1 * -> none'; then pass "other windows over screen 2: nothing to let go on"
  else fail "mid-drag of other windows: '$(smoke slotDrag)'"; fi
  wait "$SMOKE_DRAG_PID"
  if eventually 3 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == 'other windows stay on their screen'* ]]"; then
    pass "let go there, the message says why"
  else
    fail "after letting other windows go on screen 2: $(smoke message)"
  fi
  expect_eq "nothing changed" "$crossed" "$(smoke layout)"
  smoke press o >/dev/null

  # w applies: chat's window goes to HEADLESS-2.
  expect_eq "nothing applied yet" "h[main:2, right]" "$(api_state | jq -r '.layouts.dual.workspaces["3"]["1"].tree')"
  smoke press w >/dev/null
  eventually 5 state_is '.layouts.dual.workspaces["3"]["1"].tree' 'v[h[main, chat]:2, right]' ||
    fail "screen 1's tree in force: $(api_state | jq -r '.layouts.dual.workspaces["3"]["1"].tree')"
  expect_eq "screen 2's tree in force" "scroll:0.5[side, mail]" "$(api_state | jq -r '.layouts.dual.workspaces["3"]["2"].tree')"
  if eventually 10 placement_is 't-chat@3 t-main@3 t-right@3 t-side@13'; then pass "t-chat moved to HEADLESS-2's workspace 3"
  else fail "windows after w: $(placement)"; fi
  shot 6-applied
}
