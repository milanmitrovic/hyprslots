# Cross-slice: a scroll branch on the side screen of the two-screen
# arrangement survives unplugging and replugging that screen.
#
# Screens (matched by connector):
#   big  = HEADLESS-2, 2400x1350 at 0,0      Omarchy block 0: desk N = workspace N
#   side = HEADLESS-3, 1920x1080 at 2400,0   Omarchy block 1: desk N = workspace 10+N
#
# Desk 3:
#   dual   (big + side): side = scroll[x, y], big = main
#   single (big only):   big = scroll[main, x, y]
#
# x and y scroll on side in full-width columns (0.99 of 1920 = 1901 px, gaps
# and borders off) in slot order; with side gone, big's workspace 3 goes from
# lua:slots to scrolling and holds main, x and y in that order, 2376 px each;
# with side back, x and y return to side in order and main fills big again on
# lua:slots. No window is ever in a Hyprland group.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "2400x0", scale = 1 })
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
      desks = { [3] = { side = "scroll[x, y]", big = "main" } },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = { [3] = { big = "scroll[main, x, y]" } },
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

# Classes on workspace $1 in column order (left to right on the tape).
columns() {
  hc clients -j | jq -r --arg w "$1" '[.[] | select(.workspace.id == ($w | tonumber) and (.floating | not))]
    | sort_by(.at[0], .at[1]) | map(.class) | join(" ")'
}

columns_are() { [[ $(columns "$1") == "$2" ]]; }

widths() {
  hc clients -j | jq -r --arg w "$1" '[.[] | select(.workspace.id == ($w | tonumber) and (.floating | not))]
    | sort_by(.at[0], .at[1]) | map(.size[0] | tostring) | join(" ")'
}

widths_are() { [[ $(widths "$1") == "$2" ]]; }

tiled_layout() {
  hc workspaces -j | jq -r --arg w "$1" 'first(.[] | select(.id == ($w | tonumber))) | .tiledLayout'
}

grouped_count() { hc clients -j | jq '[.[] | select((.grouped | length) > 0)] | length'; }

focus_monitor() { hc dispatch "hl.dsp.focus({ monitor = '$1' })" >/dev/null; }

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  eventually 10 is_arrangement dual || true
  expect_eq "arrangement with both screens" "dual" "$(arrangement)"

  # Given y, main and x opened on big's desk 1, and desk 3 shown.
  focus_monitor HEADLESS-2
  for class in t-y t-main t-x; do
    spawn_and_wait "$class"
  done
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null

  # Then x and y scroll on side, in slot order; side's columns widen once
  # side is the focused screen.
  eventually 15 columns_are 13 "t-x t-y" || true
  focus_monitor HEADLESS-3
  eventually 10 widths_are 13 "1901 1901" || true
  settle 5
  expect_eq "side's workspace 13 scrolls" "scrolling" "$(tiled_layout 13)"
  expect_eq "x and y in slot order on side" "t-x t-y" "$(columns 13)"
  expect_eq "full-width columns on side" "1901 1901" "$(widths 13)"
  expect_eq "big's workspace 3 is on lua:slots" "lua:slots" "$(tiled_layout 3)"
  expect_client t-main 3 0 0 2400 1350

  # When side is unplugged, big's workspace 3 scrolls with main, x and y.
  output_remove HEADLESS-3
  eventually 10 is_arrangement single || fail "arrangement never became single: $(arrangement)"
  eventually 15 columns_are 3 "t-main t-x t-y" || true
  focus_monitor HEADLESS-2
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  eventually 10 widths_are 3 "2376 2376 2376" || true
  settle 5
  expect_eq "big's workspace 3 scrolls" "scrolling" "$(tiled_layout 3)"
  expect_eq "main, x and y in slot order on big" "t-main t-x t-y" "$(columns 3)"
  expect_eq "full-width columns on big" "2376 2376 2376" "$(widths 3)"

  # When side comes back, x and y return to it in order and main fills big
  # again.
  output_create HEADLESS-3
  eventually 10 is_arrangement dual || fail "arrangement never became dual: $(arrangement)"
  eventually 15 columns_are 13 "t-x t-y" || true
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  focus_monitor HEADLESS-3
  eventually 10 widths_are 13 "1901 1901" || true
  settle 5
  expect_eq "x and y back on side in slot order" "t-x t-y" "$(columns 13)"
  expect_eq "full-width columns on side again" "1901 1901" "$(widths 13)"
  expect_eq "big's workspace 3 back on lua:slots" "lua:slots" "$(tiled_layout 3)"
  expect_client t-main 3 0 0 2400 1350
  expect_eq "no Hyprland group anywhere" "0" "$(grouped_count)"

  local described
  described=$(repl 'return hyprslots.api.state()' | jq -c '[.scroll[] | {workspace, managed, in_order}]')
  expect_eq "state: side's scroll workspace kept and in order" '[{"workspace":13,"managed":true,"in_order":true}]' "$described"

  log "windows at the end:"
  hc clients -j | jq -r 'sort_by(.class)[] | "\(.class) ws=\(.workspace.id) at=\(.at[0]),\(.at[1]) size=\(.size[0])x\(.size[1]) grouped=\(.grouped | length)"' | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 20 | sed 's/^/    /'
}
