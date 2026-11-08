# A scroll branch on Hyprland's scrolling layout: full-width columns in slot
# order.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (desk N = workspace N).
# Desk 3, arrangement "solo": scroll[left, main, right]. Gaps and borders are
# off, so a full-width column (0.99, the default) is 2376 px wide.
#
# The slotted windows open on desk 1 in shuffled order and are routed to the
# hidden workspace 3; showing desk 3 finds them in slot order and widens them.
# A window with no slot opened next to the first column goes last. A column
# the user moves stays where they put it through focus changes, and a desk
# switch puts it back. The cursor never jumps.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.config({ scrolling = { column_width = 0.49 } })
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
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "scroll[left, main, right]" } },
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

# Classes on workspace $1 in column order (left to right on the tape).
columns() {
  hc clients -j | jq -r --arg w "$1" '[.[] | select(.workspace.id == ($w | tonumber) and (.floating | not))]
    | sort_by(.at[0], .at[1]) | map(.class) | join(" ")'
}

columns_are() { [[ $(columns "$1") == "$2" ]]; }

# Widths on workspace $1 in column order.
widths() {
  hc clients -j | jq -r --arg w "$1" '[.[] | select(.workspace.id == ($w | tonumber) and (.floating | not))]
    | sort_by(.at[0], .at[1]) | map(.size[0] | tostring) | join(" ")'
}

widths_are() { [[ $(widths "$1") == "$2" ]]; }

tiled_layout() {
  hc workspaces -j | jq -r --arg w "$1" 'first(.[] | select(.id == ($w | tonumber))) | .tiledLayout'
}

active_class() { hc activewindow -j | jq -r '.class'; }

# expect_in_view CLASS: the window lies wholly on the 2400 px screen.
expect_in_view() {
  local row
  row=$(hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | "\(.at[0]) \(.size[0])"')
  local x w
  read -r x w <<<"$row"
  if ((x >= 0 && x + w <= 2400)); then
    pass "$1 in view at x=$x (${w} px wide)"
  else
    fail "$1: expected in view on the 2400 px screen, at x=$x ${w} px wide"
  fi
}

grouped_count() { hc clients -j | jq '[.[] | select((.grouped | length) > 0)] | length'; }

test_body() {
  output_create HEADLESS-2

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"

  eventually 5 arrangement_is solo || true
  expect_eq "active arrangement" "solo" "$(state_field arrangement)"

  hc dispatch 'hl.dsp.cursor.move({ x = 300, y = 400 })' >/dev/null
  local cursor_before
  cursor_before=$(hc cursorpos)

  # Given the slotted windows open on desk 1 in shuffled order, they are
  # routed to desk 3, which scrolls, and lined up in slot order there.
  for class in t-right t-left t-main; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
    expect_eq "$class routed to desk 3" "3" "$(workspace_of "$class")"
  done
  expect_eq "workspace 3 is on the scrolling layout" "scrolling" "$(tiled_layout 3)"
  eventually 5 columns_are 3 "t-left t-main t-right" || true
  expect_eq "columns in slot order on the hidden workspace" "t-left t-main t-right" "$(columns 3)"
  expect_eq "the swaps did not move the cursor" "$cursor_before" "$(hc cursorpos)"

  # When desk 3 is shown, its columns become full width.
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' 2>&1)"
  eventually 5 widths_are 3 "2376 2376 2376" || true
  settle 5
  expect_monitor_workspace HEADLESS-2 3
  expect_eq "full-width columns" "2376 2376 2376" "$(widths 3)"
  expect_eq "no Hyprland group anywhere" "0" "$(grouped_count)"

  # And a window with no slot, opened next to the first column, goes last,
  # full width, keeping the focus.
  hc dispatch "hl.dsp.focus({ window = \"address:$(address_of t-left)\" })" >/dev/null
  settle 3
  spawn_and_wait t-other
  eventually 5 columns_are 3 "t-left t-main t-right t-other" || true
  eventually 5 widths_are 3 "2376 2376 2376 2376" || true
  settle 5
  expect_eq "the window with no slot goes last" "t-left t-main t-right t-other" "$(columns 3)"
  expect_eq "it is full width too" "2376 2376 2376 2376" "$(widths 3)"
  expect_eq "it keeps the focus" "t-other" "$(active_class)"
  expect_in_view t-other

  # When the user moves a column, focus changes leave it where they put it ...
  hc dispatch "hl.dsp.focus({ window = \"address:$(address_of t-left)\" })" >/dev/null
  log "swapcol r -> $(hc dispatch 'hl.dsp.layout("swapcol r")')"
  settle 3
  expect_eq "the user's move" "t-main t-left t-right t-other" "$(columns 3)"
  hc dispatch "hl.dsp.focus({ window = \"address:$(address_of t-right)\" })" >/dev/null
  settle 3
  expect_eq "a focus change keeps the user's order" "t-main t-left t-right t-other" "$(columns 3)"

  # ... and a desk switch puts the slot order back.
  repl 'return hyprslots.api.call("desk", "{\"desk\": 1}")' >/dev/null
  settle 3
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  eventually 5 columns_are 3 "t-left t-main t-right t-other" || true
  settle 3
  expect_eq "slot order after a desk switch" "t-left t-main t-right t-other" "$(columns 3)"
  expect_eq "focus kept through the swaps" "t-right" "$(active_class)"
  expect_in_view t-right

  expect_eq "cursor:no_warps put back after the swaps" "false" "$(hc getoption cursor:no_warps -j | jq -r '.bool')"

  log "windows at the end:"
  hc clients -j | jq -r 'sort_by(.at[0])[] | "\(.class) ws=\(.workspace.id) at=\(.at[0]),\(.at[1]) size=\(.size[0])x\(.size[1]) grouped=\(.grouped | length)"' | sed 's/^/    /'
  log "dump:"
  repl 'return hyprslots.dump()' | tail -n 16 | sed 's/^/    /'
}
