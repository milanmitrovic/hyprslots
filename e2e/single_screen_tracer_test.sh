# Tracer (slice 1): one screen, one desk tree, laid out by lua:slots.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (desk N = workspace N).
# Desk 3, arrangement "solo": h[a:1, b:2, c:1] -> 600 + 1200 + 600 px.
#
# The windows open on desk 1 in shuffled order; the router moves each to desk
# 3 as it opens, and activating desk 3 shows them in their slots.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = {
    [3] = { a = "t-a", b = "t-b", c = "t-c" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a:1, b:2, c:1]" } },
    },
  },
}
LUA
}

# The value of a top-level key in hyprslots.api.call("state").
state_field() {
  repl 'return hyprslots.api.call("state", "{}")' | jq -r --arg k "$1" '.[$k] // empty | tostring' 2>/dev/null
}

arrangement_is() { [[ $(state_field arrangement) == "$1" ]]; }

workspace_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

on_workspace() { [[ $(workspace_of "$1") == "$2" ]]; }

test_body() {
  output_create HEADLESS-2

  local load_error
  load_error=$(hyprslots_load_error | head -n1)
  expect_eq "hyprslots loaded" "" "$load_error"

  # The arrangement for the connected screen is selected (after the monitor
  # appeared, so through monitor.added).
  eventually 5 arrangement_is solo || true
  expect_eq "active arrangement" "solo" "$(state_field arrangement)"

  # Given desk 1 is showing, when the three windows open in shuffled order,
  # then each is routed to desk 3 as it opens.
  expect_monitor_workspace HEADLESS-2 1
  for class in t-c t-a t-b; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
    expect_eq "$class routed to desk 3" "3" "$(workspace_of "$class")"
  done

  # When desk 3 is activated.
  log "desk 3 -> $(repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' 2>&1)"
  settle

  # Then the screen shows desk 3 and the tree h[a:1, b:2, c:1] to the pixel.
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-a 3 0 0 600 1350
  expect_client t-b 3 600 0 1200 1350
  expect_client t-c 3 1800 0 600 1350

  log "windows at the end:"
  client_table | sed 's/^/    /'
  log "dump:"
  repl 'return hyprslots.dump()' | tail -n 12 | sed 's/^/    /'
}
