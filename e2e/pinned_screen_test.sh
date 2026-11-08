# Pinned screens (docs/design.md §3, §5): a workspace switch leaves a pinned screen
# on whatever it shows, and unplugging it only re-selects the arrangement.
#
# Screens and slots as in workspace_across_screens_test.sh, with side pinned.

# shellcheck source=e2e/workspace_across_screens_test.sh
source "${BASH_SOURCE[0]%/*}/workspace_across_screens_test.sh"

eval "workspace_across_screens_setup() $(declare -f test_setup | tail -n +2)"

test_setup() {
  workspace_across_screens_setup
  sed -i 's/^  arrangements = data.arrangements,$/&\n  pinned = { "side" },/' "$E2E_CONFIG_HOME/hyprslots/config.lua"
  grep -q 'pinned = { "side" }' "$E2E_CONFIG_HOME/hyprslots/config.lua" || harness_fail "could not pin side"
}

focused_monitor() { hc monitors -j | jq -r 'first(.[] | select(.focused)) | .name'; }

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-main t-left; do
    spawn_and_wait "$class"
  done
  settle
  local side_before
  side_before=$(hc monitors -j | jq -r 'first(.[] | select(.name == "HEADLESS-3")) | .activeWorkspace.id')

  # When workspace 3 is activated from the pinned screen.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-3' })" >/dev/null
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' 2>&1)"
  settle

  # Then big shows workspace 3, side keeps its view, and focus stays on side.
  expect_monitor_workspace HEADLESS-2 3
  expect_monitor_workspace HEADLESS-3 "$side_before"
  expect_eq "focus stays on the pinned screen" "HEADLESS-3" "$(focused_monitor)"
  expect_client t-main 3 0 0 2400 1350

  # When the pinned screen is unplugged.
  output_remove HEADLESS-3
  sleep 0.5
  settle

  # Then single applies on big; t-left joins workspace 3 there.
  expect_eq "arrangement" "single" "$(repl 'return hyprslots.api.state()' | jq -r .arrangement)"
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-left 3 0 0 1200 1350
  expect_client t-main 3 1200 0 1200 1350
}
