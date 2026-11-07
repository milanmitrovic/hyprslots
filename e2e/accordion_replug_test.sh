# Cross-slice: an accordion (slice 4) on the side screen of the two-screen
# arrangement (slice 2) survives unplugging and replugging that screen.
#
# Screens (matched by connector):
#   big  = HEADLESS-2, 2400x1350 at 0,0      Omarchy block 0: desk N = workspace N
#   side = HEADLESS-3, 1920x1080 at 2400,0   Omarchy block 1: desk N = workspace 10+N
#
# Desk 3:
#   dual   (big + side): side = a[x, y], big = main
#   single (big only):   big = h[main, a[x, y]]
#
# x and y are one Hyprland group filling side; with side gone they are
# re-routed to big and are still one group, in the right half; with side
# back they return to side as one group. The groupbar is off so the group's
# window fills its box to the pixel.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "2400x0", scale = 1 })
hl.config({ group = { groupbar = { enabled = false } } })
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, arrangements = data.arrangements }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = {
    [3] = { x = "t-x", y = "t-y", main = "t-main" },
  },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = { [3] = { side = "a[x, y]", big = "main" } },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "h[main, a[x, y]]" } },
    },
  },
}
LUA
}

arrangement() { repl 'return hyprslots.api.state()' | jq -r '.arrangement // empty'; }

is_arrangement() { [[ $(arrangement) == "$1" ]]; }

workspace_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

# The classes in CLASS's group, sorted and space-separated (empty: none).
group_classes() {
  hc clients -j | jq -r --arg c "$1" '
    (map({(.address): .class}) | add) as $class
    | first(.[] | select(.class == $c)) | .grouped | map($class[.]) | sort | join(" ")'
}

grouped_on() { [[ $(group_classes t-x) == "t-x t-y" && $(workspace_of t-x) == "$1" && $(workspace_of t-y) == "$1" ]]; }

# The visible member of the x/y group: workspace and box within ±1 px.
expect_group_box() {
  local ws=$1 x=$2 y=$3 w=$4 h=$5 row
  row=$(hc clients -j | jq -r '
    first(.[] | select((.class | IN("t-x", "t-y")) and (.hidden | not)))
    | "\(.class) \(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
  local class aws ax ay aw ah
  read -r class aws ax ay aw ah <<<"$row"
  if [[ $aws == "$ws" ]] && near "$ax" "$x" && near "$ay" "$y" && near "$aw" "$w" && near "$ah" "$h"; then
    pass "the x/y group (showing $class) on workspace $ws at $x,$y size ${w}x$h"
  else
    fail "the x/y group: expected workspace $ws at $x,$y size ${w}x$h, got '${row:-no visible member}'"
  fi
}

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  eventually 10 is_arrangement dual || true
  expect_eq "arrangement with both screens" "dual" "$(arrangement)"

  # Given x, y and main opened on big's desk 1, and desk 3 shown.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-y t-main t-x; do
    spawn_and_wait "$class"
  done
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null

  # Then x and y are one group filling side.
  eventually 15 grouped_on 13 || true
  settle 8
  expect_eq "x and y in one group" "t-x t-y" "$(group_classes t-x)"
  expect_monitor_workspace HEADLESS-3 13
  expect_group_box 13 2400 0 1920 1080
  expect_client t-main 3 0 0 2400 1350

  # When side is unplugged, the accordion moves to big's right half, still
  # one group.
  output_remove HEADLESS-3
  eventually 10 is_arrangement single || fail "arrangement never became single: $(arrangement)"
  eventually 15 grouped_on 3 || true
  settle 8
  expect_eq "still one group on big" "t-x t-y" "$(group_classes t-x)"
  expect_eq "t-x on workspace 3" "3" "$(workspace_of t-x)"
  expect_eq "t-y on workspace 3" "3" "$(workspace_of t-y)"
  expect_group_box 3 1200 0 1200 1350
  expect_client t-main 3 0 0 1200 1350

  # When side comes back, the group returns to it and main fills big again.
  output_create HEADLESS-3
  eventually 10 is_arrangement dual || fail "arrangement never became dual: $(arrangement)"
  eventually 15 grouped_on 13 || true
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  settle 8
  expect_eq "one group on side again" "t-x t-y" "$(group_classes t-x)"
  expect_monitor_workspace HEADLESS-3 13
  expect_group_box 13 2400 0 1920 1080
  expect_client t-main 3 0 0 2400 1350

  local formed
  formed=$(repl 'return hyprslots.api.state()' | jq -r '.groups[0].formed')
  expect_eq "state reports the accordion's group as formed" "true" "$formed"

  log "windows at the end:"
  hc clients -j | jq -r 'sort_by(.class)[] | "\(.class) ws=\(.workspace.id) at=\(.at[0]),\(.at[1]) size=\(.size[0])x\(.size[1]) hidden=\(.hidden) grouped=\(.grouped | length)"' | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 20 | sed 's/^/    /'
}
