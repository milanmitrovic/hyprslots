# Slice 4: an accordion is one Hyprland group; unmatched windows overflow.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (desk N = workspace N).
# Desk 3, arrangement "solo": h[a[a, b, c]:1, v[d, *]:1]
#   a, b, c   one group filling the left half      0,0     1200x1350
#   d         the right half's top                 1200,0  1200x675
#   *         the overflow leaf below d            1200,675 1200x675
#
# The slotted windows open on desk 1 and are routed to desk 3; the unmatched
# window opens on desk 3 itself, after the group exists (so Hyprland's
# auto_group drops it into the focused group, and hyprslots must take it out).
# Finally b is taken out of the group by hand and must be put back. The
# groupbar is off so the group's window fills the box to the pixel.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.config({ group = { groupbar = { enabled = false } } })
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
    [3] = { a = "t-a", b = "t-b", c = "t-c", d = "t-d" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a[a, b, c]:1, v[d, *]:1]" } },
    },
  },
}
LUA
}

state_field() {
  repl 'return hyprslots.api.call("state", "{}")' | jq -r --arg k "$1" '.[$k] // empty | tostring' 2>/dev/null
}

arrangement_is() { [[ $(state_field arrangement) == "$1" ]]; }

workspace_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

on_workspace() { [[ $(workspace_of "$1") == "$2" ]]; }

address_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .address'
}

# The classes in CLASS's group, sorted and space-separated (empty: none).
group_classes() {
  hc clients -j | jq -r --arg c "$1" '
    (map({(.address): .class}) | add) as $class
    | first(.[] | select(.class == $c)) | .grouped | map($class[.]) | sort | join(" ")'
}

group_is() { [[ $(group_classes "$1") == "$2" ]]; }

# Geometry of the one visible window of a group whose members are CLASSES.
expect_group_box() {
  local x=$1 y=$2 w=$3 h=$4 row
  row=$(hc clients -j | jq -r '
    first(.[] | select((.class | IN("t-a", "t-b", "t-c")) and (.hidden | not)))
    | "\(.class) \(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
  local class ws ax ay aw ah
  read -r class ws ax ay aw ah <<<"$row"
  if [[ $ws == 3 ]] && near "$ax" "$x" && near "$ay" "$y" && near "$aw" "$w" && near "$ah" "$h"; then
    pass "the group (showing $class) on workspace 3 at $x,$y size ${w}x$h"
  else
    fail "the group: expected workspace 3 at $x,$y size ${w}x$h, got '${row:-no visible member}'"
  fi
}

test_body() {
  output_create HEADLESS-2

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"

  eventually 5 arrangement_is solo || true
  expect_eq "active arrangement" "solo" "$(state_field arrangement)"

  # Given the four slotted windows open on desk 1 in shuffled order, they are
  # routed to desk 3.
  for class in t-c t-d t-a t-b; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
    expect_eq "$class routed to desk 3" "3" "$(workspace_of "$class")"
  done

  # When desk 3 is shown, a, b and c form one group.
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' 2>&1)"
  eventually 10 group_is t-a "t-a t-b t-c" || true
  expect_eq "a, b and c in one group" "t-a t-b t-c" "$(group_classes t-a)"
  expect_eq "d in no group" "" "$(group_classes t-d)"

  # And when an unmatched window opens on desk 3, it ends up in the overflow
  # leaf, out of the group.
  spawn_and_wait t-other
  eventually 10 group_is t-a "t-a t-b t-c" || true
  settle 8
  expect_eq "the group keeps a, b and c only" "t-a t-b t-c" "$(group_classes t-a)"
  expect_eq "t-other in no group" "" "$(group_classes t-other)"

  # Then the tree, to the pixel.
  expect_monitor_workspace HEADLESS-2 3
  expect_group_box 0 0 1200 1350
  expect_client t-d 3 1200 0 1200 675
  expect_client t-other 3 1200 675 1200 675

  # When the user takes b out of the group (no window event fires), the next
  # layout pass sees the accordion split and b goes back in.
  local b
  b=$(address_of t-b)
  log "b out of the group -> $(hc dispatch "hl.dsp.window.move({ out_of_group = true, window = \"address:$b\" })" 2>&1)"
  eventually 10 group_is t-a "t-a t-b t-c" || true
  settle 8
  expect_eq "b back in the group" "t-a t-b t-c" "$(group_classes t-a)"
  local readds
  readds=$(repl 'return hyprslots.dump()' | grep -c "add $b into")
  expect_eq "hyprslots added b twice (routing, then after the drag-out)" "2" "$readds"
  expect_group_box 0 0 1200 1350
  expect_client t-d 3 1200 0 1200 675

  log "windows at the end:"
  hc clients -j | jq -r 'sort_by(.class)[] | "\(.class) ws=\(.workspace.id) at=\(.at[0]),\(.at[1]) size=\(.size[0])x\(.size[1]) hidden=\(.hidden) grouped=\(.grouped | length)"' | sed 's/^/    /'
  log "dump:"
  repl 'return hyprslots.dump()' | tail -n 16 | sed 's/^/    /'
}
