# The Layout tab's screens swapped (docs/design.md §9), in Quickshell on
# the nested Hyprland (part of `make e2e-editor`; needs qs, grim, and
# Omarchy's shell modules, as e2e/editor_smoke.sh does). SMOKE_THEME=<an
# Omarchy theme dir> runs it in that theme (the screenshots then carry its
# name).
#
# Screens: HEADLESS-2, 1920x1080 at 0,0 (screen 1, Omarchy block 0:
# workspace N = id N); HEADLESS-3, 2560x1440 at 1920,0 (screen 2, block 1:
# workspace N = id 10+N). Desk dual (both) uses layout dual, which desk
# office (two monitors never connected) shares: workspace 3 is h[main:2,
# right] on screen 1 and scroll:0.5[side, chat] on screen 2; the shared
# trees h[main, right] and side. Windows t-main, t-right, t-side and t-chat
# are in their slots on workspace 3.
#
# Screen 1's pane is dragged by its title, with the real pointer: let go
# over itself it does nothing; Esc while it is held lets it go, nothing
# changed and the panel open; held over screen 2's pane, that pane is the
# target ("Swap with screen 2", a screenshot mid-drag), and let go there
# the two trees trade places in the drafts, the message naming office,
# which shares the layout. w applies it: main and right go to HEADLESS-3's
# workspace 13, which goes on lua:slots, side and chat to HEADLESS-2's 3,
# which scrolls; Ctrl+S saves it. Then p, the keys' way, swaps them back
# (the selection went with the dragged tree, to screen 2; the next screen
# is 1, round), and w puts the windows back. On workspace 4, which uses the
# shared trees, p first asks whom the edit is for.
# Screenshots: .e2e-tmp/editor-screen-swap[-<theme>]-*.png.

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
    office = { monitors = { "DP-7", "DP-8" }, layout = "dual" },
  },
  layouts = {
    dual = {
      screens = 2,
      default = { [1] = "h[main, right]", [2] = "side" },
      workspaces = { [3] = { [1] = "h[main:2, right]", [2] = "scroll:0.5[side, chat]" } },
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
  local file=$SMOKE_SHOTS/editor-screen-swap$SHOT_TAG-$1.png
  rm -f "$file"
  sleep 0.3
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

workspace_of() { hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'; }
# "<class>@<workspace id>" for every test window, sorted by class.
placement() {
  hc clients -j | jq -r '[.[] | select(.class | startswith("t-"))] | sort_by(.class) | map("\(.class)@\(.workspace.id)") | join(" ")'
}
placement_is() { [[ $(placement) == "$1" ]]; }
tiled_layout() {
  hc workspaces -j | jq -r --arg w "$1" 'first(.[] | select(.id == ($w | tonumber))) | .tiledLayout'
}
watch_is() { [[ $(smoke "$1") == "$2" ]]; }

# The middle of screen $1's pane, well inside its picture: "<x> <y>".
pane_middle() {
  local x y w h
  read -r x y w h <<<"$(smoke bounds "screen:$1")"
  printf '%d %d\n' "$((x + w / 2))" "$((y + h + 200))"
}

test_body() {
  for tool in qs grim; do
    command -v "$tool" >/dev/null || harness_fail "the screen swap scenario needs $tool"
  done
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  expect_eq "desk dual, both screens" "dual" "$(api_state | jq -r .desk)"

  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  local class
  for class in t-main t-right t-side t-chat; do spawn_and_wait "$class"; done
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")')"
  local before='t-chat@13 t-main@3 t-right@3 t-side@13'
  eventually 10 placement_is "$before" || fail "windows before: $(placement)"
  expect_eq "screen 2's workspace 13 scrolls" "scrolling" "$(tiled_layout 13)"
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null

  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5 # let the overlay reveal itself (it waits for the output's scale)
  smoke press Tab >/dev/null
  eventually 3 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke tabs) == *'| Layout' ]]" || fail "tabs: $(smoke tabs)"
  smoke press 3 >/dev/null
  local start='1: h[main:2, right]; 2: scroll:0.5[side, chat]'
  expect_eq "workspace 3's trees" "$start" "$(smoke layout)"
  expect_eq "panes" "Screen 1 · HEADLESS-2 | Screen 2 · HEADLESS-3" "$(smoke panes)"

  # the help row offers p, one line still
  if [[ $(smoke help) == *'swa<b><font color="'*'">p</font></b>'* ]]; then pass "the help row offers p, swap"
  else fail "help: $(smoke help)"; fi
  expect_eq "the help row is one line" "1" "$(smoke helpLines)"

  local x y
  # Let go over its own pane: nothing.
  read -r x y <<<"$(pane_middle 1)"
  smoke_drag screen:1 "$x" "$y" 1500
  if eventually 3 watch_is screenDrag '1 -> none'; then pass "over its own pane: no label"
  else fail "mid-drag over itself: '$(smoke screenDrag)'"; fi
  wait "$SMOKE_DRAG_PID"
  eventually 3 watch_is screenDrag '' || fail "the drag is still held: $(smoke screenDrag)"
  expect_eq "let go over itself: nothing changed" "$start" "$(smoke layout)"

  # Esc while held: let go, nothing changed, the panel open.
  read -r x y <<<"$(pane_middle 2)"
  smoke_drag screen:1 "$x" "$y" 2500
  if eventually 3 watch_is screenDrag '1 -> Swap with screen 2'; then pass "held over screen 2: Swap with screen 2"
  else fail "mid-drag onto screen 2: '$(smoke screenDrag)'"; fi
  expect_eq "Esc lets the drag go" "ok" "$(smoke press Escape)"
  expect_eq "no drag held after Esc" "" "$(smoke screenDrag)"
  wait "$SMOKE_DRAG_PID"
  expect_eq "Esc: nothing changed" "$start" "$(smoke layout)"
  expect_eq "Esc: the panel stays open" "yes" "$(smoke ready)"

  # Held over screen 2, then let go: the trees trade places.
  smoke_drag screen:1 "$x" "$y" 2500
  if eventually 3 watch_is screenDrag '1 -> Swap with screen 2'; then pass "held over screen 2 again"
  else fail "mid-drag onto screen 2: '$(smoke screenDrag)'"; fi
  if [[ -n $(smoke bounds dropzone:screen:2) ]]; then pass "screen 2's pane is outlined as the target"
  else fail "no target outline on screen 2"; fi
  if [[ -z $(smoke bounds dropzone:screen:1) ]]; then pass "and screen 1's is not"
  else fail "screen 1 outlined too"; fi
  if [[ -n $(smoke bounds screenGhost) ]]; then pass "the ghost follows the pointer"
  else fail "no ghost"; fi
  shot 1-mid-drag
  wait "$SMOKE_DRAG_PID"
  local swapped='1: scroll:0.5[side, chat] *; 2: h[main:2, right] *'
  if eventually 3 watch_is layout "$swapped"; then pass "let go over screen 2: the trees swapped in the drafts"
  else fail "after the drop: $(smoke layout); $(smoke message)"; fi
  if [[ $(smoke message) == 'Swapped screens 1 and 2'*'office'* ]]; then pass "the message says so, and names office, which shares the layout"
  else fail "message: $(smoke message)"; fi
  expect_eq "the selection went with the dragged tree" "2 main" "$(smoke selection)"
  expect_eq "nothing applied yet" "h[main:2, right]" "$(api_state | jq -r '.layouts.dual.workspaces["3"]["1"].tree')"
  shot 2-swapped-draft

  # w applies: the windows move between the monitors.
  smoke press w >/dev/null
  eventually 5 state_is '.layouts.dual.workspaces["3"]["1"].tree' 'scroll:0.5[side, chat]' ||
    fail "screen 1's tree in force: $(api_state | jq -r '.layouts.dual.workspaces["3"]["1"].tree')"
  expect_eq "screen 2's tree in force" "h[main:2, right]" "$(api_state | jq -r '.layouts.dual.workspaces["3"]["2"].tree')"
  local after='t-chat@3 t-main@13 t-right@13 t-side@3'
  if eventually 10 placement_is "$after"; then pass "main and right on HEADLESS-3, side and chat on HEADLESS-2"
  else fail "windows after w: $(placement)"; fi
  eventually 5 bash -c "[[ \$(hyprctl -i $E2E_SIG workspaces -j | jq -r 'first(.[] | select(.id == 3)) | .tiledLayout') == scrolling ]]" ||
    fail "workspace 3: $(tiled_layout 3)"
  expect_eq "HEADLESS-2's workspace 3 scrolls" "scrolling" "$(tiled_layout 3)"
  expect_eq "HEADLESS-3's workspace 13 is on lua:slots" "lua:slots" "$(tiled_layout 13)"
  log "workspace 3's columns: $(hc clients -j | jq -r '[.[] | select(.workspace.id == 3)] | sort_by(.at[0]) | map("\(.class) \(.size[0])") | join(", ")')"
  expect_eq "applied: nothing edited" "$(printf '%s' "$swapped" | sed 's/ \*//g')" "$(smoke layout)"
  shot 3-applied

  smoke press Ctrl+s >/dev/null
  eventually 5 state_is .dirty false || fail "Ctrl+S did not save: $(smoke message)"
  if grep -qF '[1] = "scroll:0.5[side, chat]",' "$E2E_CONFIG_HOME/hyprslots/slots.lua" &&
    grep -qF '[2] = "h[main:2, right]",' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "Ctrl+S saved the swapped trees"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi

  # p swaps the selected screen (2) with the next (1, round): back again.
  expect_eq "p" "ok" "$(smoke press p)"
  expect_eq "p swapped them back in the drafts" "1: h[main:2, right] *; 2: scroll:0.5[side, chat] *" "$(smoke layout)"
  expect_eq "the selection went with screen 2's tree, to screen 1" "1 main" "$(smoke selection)"
  smoke press w >/dev/null
  if eventually 10 placement_is "$before"; then pass "w put the windows back"
  else fail "windows after p, w: $(placement)"; fi

  # On a workspace using the shared trees p asks whom the edit is for.
  smoke press 4 >/dev/null
  smoke press p >/dev/null
  if [[ $(smoke message) == 'Apply to (a)ll workspaces or (o)nly workspace 4?'* ]]; then pass "p on workspace 4 asks first"
  else fail "p on workspace 4: $(smoke message)"; fi
  smoke press o >/dev/null
  expect_eq "only workspace 4: its drafts swapped" "1: side *; 2: h[main, right, chat] *" "$(smoke layout)"
  if [[ $(smoke layoutHeader) == *'w gives workspace 4 its own'* ]]; then pass "the header says w gives it its own"
  else fail "header: $(smoke layoutHeader)"; fi
}
