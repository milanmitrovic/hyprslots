# Late titles (docs/design.md §7): a foot window opens with a generic title
# that matches no slot and stays where it opened; when its title changes to
# one matching `foot/deltaf`, it is routed to that slot's desk workspace and
# placed there.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0. Desk 3 tree "main",
# slot main = foot/deltaf (foot's default extractor keeps the part of the
# title before " | ").

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
return {
  slots = { main = {} },
  specs = { [3] = { main = "foot/deltaf" } },
  arrangements = {
    solo = { screens = { big = "HEADLESS-2" }, desks = { [3] = { big = "main" } } },
  },
}
LUA
}

# A foot window titled "shell" that retitles itself (OSC 2) to
# "deltaf | zellij" once $E2E_DIR/retitle exists.
spawn_retitling_foot() {
  local flag=$E2E_DIR/retitle
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY foot --config=/dev/null --app-id=foot --title=shell \
    sh -c "while [ ! -e '$flag' ]; do sleep 0.1; done; printf '\033]2;deltaf | zellij\007'; sleep 3600" \
    >>"$E2E_DIR/clients.log" 2>&1 &
  E2E_CLIENT_PIDS+=("$!")
}

foot_field() { hc clients -j | jq -r --arg f "$1" 'first(.[] | select(.class == "foot")) | .[$f] | tostring'; }

foot_workspace() { hc clients -j | jq -r 'first(.[] | select(.class == "foot")) | .workspace.id'; }

foot_on() { [[ $(foot_workspace) == "$1" ]]; }

assignments() { repl 'return hyprslots.api.state()' | jq -cS '[.assignments[]]'; }

test_body() {
  output_create HEADLESS-2
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null

  # Given a foot window whose title matches no slot.
  spawn_retitling_foot
  eventually 10 client_mapped foot || harness_fail "foot never mapped"
  settle
  expect_eq "foot opened titled shell" "shell" "$(foot_field title)"
  sleep 0.5
  expect_eq "foot stays on workspace 1" "1" "$(foot_workspace)"
  expect_eq "foot has no slot" "[]" "$(assignments)"

  # When its title changes to one matching foot/deltaf.
  touch "$E2E_DIR/retitle"
  eventually 10 foot_on 3 || true

  # Then it is routed to desk 3 and takes slot main.
  expect_eq "foot retitled" "deltaf | zellij" "$(foot_field title)"
  expect_eq "foot routed to workspace 3" "3" "$(foot_workspace)"
  expect_eq "foot holds slot main" '[{"desk":3,"slot":"main"}]' "$(assignments)"
  expect_monitor_workspace HEADLESS-2 1

  # And desk 3 shows it in its slot.
  repl 'return hyprslots.api.call("desk", "{\"desk\": 3}")' >/dev/null
  settle
  expect_client foot 3 0 0 2400 1350
}
