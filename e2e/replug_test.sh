# Hotplug both ways (docs/design.md §8): unplugging side gathers workspace 3 on
# big; plugging it back re-selects dual, sends t-left back to side's
# workspace 3 after Omarchy's own reconcile, and shows the active workspace
# (3) on side again without moving focus.
#
# Screens and config as in workspace_across_screens_test.sh.

# shellcheck source=e2e/workspace_across_screens_test.sh
source "${BASH_SOURCE[0]%/*}/workspace_across_screens_test.sh"

workspace_monitor() {
  hc workspaces -j | jq -r --argjson id "$1" 'first(.[] | select(.id == $id)) | .monitor // empty'
}

arrangement() { repl 'return hyprslots.api.state()' | jq -r .arrangement; }

is_arrangement() { [[ $(arrangement) == "$1" ]]; }

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-right t-left t-main; do
    spawn_and_wait "$class"
  done
  repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' >/dev/null
  settle

  output_remove HEADLESS-3
  eventually 10 is_arrangement single || fail "arrangement never became single"
  settle
  expect_client t-left 3 0 0 800 1350

  # When side comes back.
  output_create HEADLESS-3
  eventually 10 is_arrangement dual || fail "arrangement never became dual: $(arrangement)"
  settle

  # Then side shows the active workspace again (workspace 3 was the last switched
  # to), and focus stays on big.
  expect_monitor_workspace HEADLESS-3 13
  expect_eq "focus stays on HEADLESS-2" "HEADLESS-2" \
    "$(hc monitors -j | jq -r 'first(.[] | select(.focused)) | .name')"

  # And t-left is back on side's workspace 3, big keeps main:right at 2:1.
  expect_eq "workspace 13 is on HEADLESS-3" "HEADLESS-3" "$(workspace_monitor 13)"
  expect_eq "t-left is on workspace 13" "13" \
    "$(hc clients -j | jq -r 'first(.[] | select(.class == "t-left")) | .workspace.id')"
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-main 3 0 0 1600 1350
  expect_client t-right 3 1600 0 800 1350

  # And workspace 3 shows it on side.
  repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' >/dev/null
  settle
  expect_monitor_workspace HEADLESS-3 13
  expect_client t-left 13 2400 0 1920 1080
}
