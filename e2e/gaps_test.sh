# Gaps, borders and the groupbar, as Omarchy configures them (the other
# tests run with gaps and borders off).
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0. gaps_out 10,
# gaps_in 5, border 2; groupbar 22 px tall, indicator 1, gaps_in 5.
#
# Hyprland hands the layout ctx.area already inside gaps_out (10,10 2380x1330)
# and place() takes the border and gaps_in off each box edge that meets
# another box, so the boxes are exact integer shares of the area and the
# visible windows keep a gaps_out margin at the screen edges and a
# 2 * gaps_in gap between each other:
#
#   desk 3, h[a, b:2, c]: boxes 595 + 1190 + 595 px
#     a  12,12 586x1326     b  612,12 1176x1326     c  1802,12 586x1326
#   desk 4, a[d, e]: one group filling the area; Hyprland draws the
#     groupbar inside the box (22 + indicator 1 = 23 px with this config;
#     Omarchy's live theme makes it 28), so the window starts below it and
#     still ends on the box's bottom edge:  12,35 2376x1303

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.config({
  general = { gaps_in = 5, gaps_out = 10, border_size = 2 },
  group = { groupbar = { enabled = true, height = 22, indicator_height = 1, gaps_in = 5, gaps_out = 0 } },
})
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
    [3] = { a = "t-a", b = "t-b", c = "t-c" },
    [4] = { d = "t-d", e = "t-e" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = {
        [3] = { main = "h[a, b:2, c]" },
        [4] = { main = "a[d, e]" },
      },
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

grouped_with() {
  hc clients -j | jq -e --arg a "$1" --arg b "$2" '
    (map({(.class): .address}) | add) as $addr
    | any(.[]; .class == $a and (.grouped | index($addr[$b]) != null))' >/dev/null
}

test_body() {
  output_create HEADLESS-2

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"
  eventually 5 arrangement_is solo || true
  expect_eq "active arrangement" "solo" "$(state_field arrangement)"

  for class in t-c t-a t-b; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
  done
  for class in t-d t-e; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 4 || true
  done

  # Given desk 3 is shown, its three slots tile 1:2:1 inside the gaps.
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' 2>&1)"
  settle
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-a 3 12 12 586 1326
  expect_client t-b 3 612 12 1176 1326
  expect_client t-c 3 1802 12 586 1326

  # Given desk 4 is shown, d and e are one group under its groupbar.
  log "desk 4 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 4}")' 2>&1)"
  eventually 10 grouped_with t-d t-e || true
  settle
  expect_monitor_workspace HEADLESS-2 4
  if grouped_with t-d t-e; then pass "d and e in one group"; else fail "d and e are not grouped"; fi
  expect_client t-d 4 12 35 2376 1303
  expect_client t-e 4 12 35 2376 1303

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
