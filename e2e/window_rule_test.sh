# Generated window rules (docs/design.md §7b): a window of a class-only spec
# opens directly on its slot's desk workspace, never on the focused one.
# Hyprland's socket2 `openwindow` event carries the workspace the window
# mapped on, before the router could have moved it.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0. Desk 3 tree "main",
# slot main = class t-main.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
return {
  slots = { [3] = { main = "t-main" } },
  arrangements = {
    solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "main" } } },
  },
}
LUA
}

# Record socket2 events to $E2E_DIR/events.log; the listener is stopped at
# teardown with the clients.
listen_events() {
  local socket=$XDG_RUNTIME_DIR/hypr/$E2E_SIG/.socket2.sock
  [[ -S $socket ]] || harness_fail "no socket2 at $socket"
  socat -u "UNIX-CONNECT:$socket" "OPEN:$E2E_DIR/events.log,creat,append" 2>>"$E2E_DIR/socat.log" &
  E2E_CLIENT_PIDS+=("$!")
}

opened_on() {
  grep -a "^openwindow>>.*,t-main," "$E2E_DIR/events.log" | head -n1 | cut -d'>' -f3 | cut -d, -f2
}

workspace_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

test_body() {
  command -v socat >/dev/null || harness_fail "socat is needed to read socket2"
  output_create HEADLESS-2
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  expect_monitor_workspace HEADLESS-2 1
  listen_events
  sleep 0.3

  # When t-main opens while desk 1 shows.
  spawn_and_wait t-main
  eventually 5 opened_on >/dev/null || true
  settle

  # Then it mapped on workspace 3 itself (no jump from 1), and stays there.
  expect_eq "t-main mapped on workspace 3" "3" "$(opened_on)"
  expect_eq "t-main is on workspace 3" "3" "$(workspace_of t-main)"
  expect_eq "t-main never moved" "0" "$(grep -ac '^movewindow' "$E2E_DIR/events.log")"
  expect_monitor_workspace HEADLESS-2 1

  # And once desk 3 shows, it fills its slot.
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  settle
  expect_client t-main 3 0 0 2400 1350
}
