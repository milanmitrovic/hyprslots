# Routing across screens (docs/design.md §7): a window whose slot is on the
# other screen lands on that screen's desk workspace, created there although
# Hyprland creates a missing workspace on the focused monitor, and without
# changing what either screen shows or which one has focus.
#
# Screens and config as in desk_across_screens_test.sh.

# shellcheck source=e2e/desk_across_screens_test.sh
source "${BASH_SOURCE[0]%/*}/desk_across_screens_test.sh"

workspace_monitor() {
  hc workspaces -j | jq -r --argjson id "$1" 'first(.[] | select(.id == $id)) | .monitor // empty'
}

focused_monitor() { hc monitors -j | jq -r 'first(.[] | select(.focused)) | .name'; }

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  local side_before
  side_before=$(hc monitors -j | jq -r 'first(.[] | select(.name == "HEADLESS-3")) | .activeWorkspace.id')

  # When a window whose slot is on side opens on big.
  spawn_and_wait t-left
  settle

  # Then its desk-3 workspace on side holds it, and nothing else changed.
  expect_eq "workspace 13 is on HEADLESS-3" "HEADLESS-3" "$(workspace_monitor 13)"
  expect_eq "t-left is on workspace 13" "13" \
    "$(hc clients -j | jq -r 'first(.[] | select(.class == "t-left")) | .workspace.id')"
  expect_monitor_workspace HEADLESS-3 "$side_before"
  expect_monitor_workspace HEADLESS-2 1
  expect_eq "focus stays on HEADLESS-2" "HEADLESS-2" "$(focused_monitor)"

  # And once side shows desk 3, the window fills it.
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  settle
  expect_client t-left 13 2400 0 1920 1080
  expect_eq "focus is back on HEADLESS-2" "HEADLESS-2" "$(focused_monitor)"
}
