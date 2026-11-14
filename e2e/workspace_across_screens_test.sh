# Completion test for slice 2 (docs/design.md §12): one workspace spans two
# screens, and losing a screen switches to the desk for what is left.
#
# Monitors (desks select them by connector; screens are numbered left to right):
#   big  = HEADLESS-2, 2400x1350 at 0,0      screen 1, Omarchy block 0: workspace N = workspace id N
#   side = HEADLESS-3, 1920x1080 at 2400,0   screen 2, Omarchy block 1: workspace N = workspace id 10+N
#
# Desks and their layouts, for workspace 3:
#   dual   (big + side), layout dual (2 screens): screen 1 = h[main:2, right:1], screen 2 = left
#   single (big only), layout single (1 screen):  screen 1 = h[left, main, right]

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
  desks = data.desks,
  layouts = data.layouts,
}
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { left = { key = "l" }, main = { key = "m" }, right = { key = "r" } },
  specs = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    single = { monitors = { "HEADLESS-2" }, layout = "single" },
  },
  layouts = {
    dual = {
      screens = 2,
      workspaces = {
        [3] = { [1] = "h[main:2, right:1]", [2] = "left" },
      },
    },
    single = {
      screens = 1,
      workspaces = {
        [3] = { [1] = "h[left, main, right]" },
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

  # Given three windows opened on big's workspace 1, in shuffled order.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-right t-left t-main; do
    spawn_and_wait "$class"
  done
  settle
  # They open on workspace 1, and the router moves each to its workspace
  # 3 as it opens (design §7), so where they sit now is not a
  # precondition; only that all three exist.
  local mapped
  mapped=$(hc clients -j | jq '[.[] | select(.mapped)] | length')
  [[ $mapped == 3 ]] || harness_fail "expected 3 mapped windows, have: $(client_table)"
  log "windows before workspace switch:"
  client_table | sed 's/^/    /'

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"
  expect_eq "desk with both screens" "dual" "$(repl 'return hyprslots.api.state()' | jq -r .desk)"
  expect_eq "screens left to right" '["HEADLESS-2","HEADLESS-3"]' "$(repl 'return hyprslots.api.state()' | jq -c .screens)"

  # When workspace 3 is activated through the Super+3 path.
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' 2>&1)"
  settle

  # Then both screens show workspace 3, side holds left, big splits main:right 2:1.
  expect_monitor_workspace HEADLESS-2 3
  expect_monitor_workspace HEADLESS-3 13
  expect_client t-left 13 2400 0 1920 1080
  expect_client t-main 3 0 0 1600 1350
  expect_client t-right 3 1600 0 800 1350

  # When side is unplugged.
  output_remove HEADLESS-3
  sleep 0.5
  settle

  # Then desk single (layout single) tiles all three 1:1:1 on big's workspace 3.
  expect_eq "desk" "single" "$(repl 'return hyprslots.api.state()' | jq -r .desk)"
  expect_eq "layout" "single" "$(repl 'return hyprslots.api.state()' | jq -r .layout)"
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-left 3 0 0 800 1350
  expect_client t-main 3 800 0 800 1350
  expect_client t-right 3 1600 0 800 1350

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
