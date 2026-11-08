# Gaps and borders, as Omarchy configures them (the other tests run with
# gaps and borders off).
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0. gaps_out 10,
# gaps_in 5, border 2.
#
# Hyprland hands the layout ctx.area already inside gaps_out (10,10 2380x1330)
# and place() takes the border and gaps_in off each box edge that meets
# another box, so the boxes are exact integer shares of the area and the
# visible windows keep a gaps_out margin at the screen edges and a
# 2 * gaps_in gap between each other:
#
#   workspace 3, h[a, b:2, c]: boxes 595 + 1190 + 595 px
#     a  12,12 586x1326     b  612,12 1176x1326     c  1802,12 586x1326
#   workspace 4, scroll[d, e]: Hyprland's scrolling layout, which works in the
#     same area: each column is 0.99 of its 2380 px (2356), d's is fitted
#     to the left edge with e's next to it, and the windows inside keep the
#     same margins (no gaps_in at the screen edge, 2 * gaps_in between):
#     d  12,12 2347x1326     e  2373,12 2347x1326 (off to the right)
#     No window is in a Hyprland group, so no groupbar takes any height.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.config({
  general = { gaps_in = 5, gaps_out = 10, border_size = 2 },
})
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { a = {}, b = {}, c = {}, d = {}, e = {} },
  specs = {
    [3] = { a = "t-a", b = "t-b", c = "t-c" },
    [4] = { d = "t-d", e = "t-e" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = {
        [3] = { main = "h[a, b:2, c]" },
        [4] = { main = "scroll[d, e]" },
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

# Widths on workspace $1 in column order (left to right on the tape).
widths() {
  hc clients -j | jq -r --arg w "$1" '[.[] | select(.workspace.id == ($w | tonumber) and (.floating | not))]
    | sort_by(.at[0], .at[1]) | map(.size[0] | tostring) | join(" ")'
}

widths_are() { [[ $(widths "$1") == "$2" ]]; }

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

  # Given workspace 3 is shown, its three slots tile 1:2:1 inside the gaps.
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' 2>&1)"
  settle
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-a 3 12 12 586 1326
  expect_client t-b 3 612 12 1176 1326
  expect_client t-c 3 1802 12 586 1326

  # Given workspace 4 is shown, d and e are full-width scrolling columns, d
  # (the first) in view, both inside the gaps.
  log "workspace 4 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 4}")' 2>&1)"
  hc dispatch "hl.dsp.focus({ window = \"address:$(hc clients -j | jq -r 'first(.[] | select(.class == "t-d")) | .address')\" })" >/dev/null
  eventually 10 widths_are 4 "2347 2347" || true
  settle
  expect_monitor_workspace HEADLESS-2 4
  expect_eq "workspace 4 scrolls" "scrolling" "$(hc workspaces -j | jq -r 'first(.[] | select(.id == 4)) | .tiledLayout')"
  expect_eq "no Hyprland group" "0" "$(hc clients -j | jq '[.[] | select((.grouped | length) > 0)] | length')"
  expect_client t-d 4 12 12 2347 1326
  expect_client t-e 4 2373 12 2347 1326

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
