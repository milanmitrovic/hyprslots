# Completion test for slice 2 (docs/design.md §12): one desk spans two
# screens, and losing a screen switches to the arrangement for what is left.
#
# Screens (matched by connector):
#   big  = HEADLESS-2, 2400x1350 at 0,0      Omarchy block 0: desk N = workspace N
#   side = HEADLESS-3, 1920x1080 at 2400,0   Omarchy block 1: desk N = workspace 10+N
#
# Arrangements for desk 3:
#   dual   (big + side): side = left, big = h[main:2, right:1]
#   single (big only):   big = h[left, main, right]

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "2400x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return {
  slots = data.slots,
  specs = data.specs,
  arrangements = data.arrangements,
}
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  arrangements = {
    dual = {
      screens = { big = "HEADLESS-2", side = "HEADLESS-3" },
      desks = {
        [3] = { side = "left", big = "h[main:2, right:1]" },
      },
    },
    single = {
      screens = { big = "HEADLESS-2" },
      desks = {
        [3] = { big = "h[left, main, right]" },
      },
    },
  },
}
LUA
}

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  [[ $(monitor_names) == "HEADLESS-2 HEADLESS-3" ]] || harness_fail "unexpected monitors: $(monitor_names)"

  # Given three windows opened on big's desk 1, in shuffled order.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-right t-left t-main; do
    spawn_and_wait "$class"
  done
  settle
  # They open on workspace 1, and the router moves each to its desk-3
  # workspace as it opens (design §7), so where they sit now is not a
  # precondition; only that all three exist.
  local mapped
  mapped=$(hc clients -j | jq '[.[] | select(.mapped)] | length')
  [[ $mapped == 3 ]] || harness_fail "expected 3 mapped windows, have: $(client_table)"
  log "windows before desk switch:"
  client_table | sed 's/^/    /'

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"

  # When desk 3 is activated through the Super+3 path.
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' 2>&1)"
  settle

  # Then both screens show desk 3, side holds left, big splits main:right 2:1.
  expect_monitor_workspace HEADLESS-2 3
  expect_monitor_workspace HEADLESS-3 13
  expect_client t-left 13 2400 0 1920 1080
  expect_client t-main 3 0 0 1600 1350
  expect_client t-right 3 1600 0 800 1350

  # When side is unplugged.
  output_remove HEADLESS-3
  sleep 0.5
  settle

  # Then arrangement single tiles all three 1:1:1 on big's desk 3.
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-left 3 0 0 800 1350
  expect_client t-main 3 800 0 800 1350
  expect_client t-right 3 1600 0 800 1350

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
