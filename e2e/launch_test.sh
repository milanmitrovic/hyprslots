# Launching the apps a workspace's empty slots wait for (docs/design.md §9,
# Launching apps): at login, on demand, never twice, never on a reload.
#
# Screen: HEADLESS-2, 1920x1080 at 0,0, Omarchy block 0 (workspace N = id N).
# The test's XDG_DATA_HOME holds t-launch.desktop (a foot window of class
# t-launch) and nothing else is looked in. Workspace 3 (on demand) waits for
# t-launch in main and t-other in aside (no desktop entry: it cannot be
# launched); workspace 5 (at login) for t-launch in main.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2
  export XDG_DATA_HOME=$E2E_DIR/data XDG_DATA_DIRS=$E2E_DIR/system-data
  mkdir -p "$XDG_DATA_HOME/applications" "$XDG_DATA_DIRS"
  cat >"$XDG_DATA_HOME/applications/t-launch.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Launch test
Exec=foot --config=/dev/null --app-id=t-launch --title=t-launch sleep 3600
DESKTOP

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = { key = "m" }, aside = { key = "a" } },
  specs = {
    [3] = { main = "t-launch", aside = "t-other" },
    [5] = { main = "t-launch" },
  },
  desks = { solo = { monitors = { "HEADLESS-2" }, layout = "solo" } },
  layouts = { solo = { screens = 1, default = { [1] = "h[main, aside]" } } },
  launch = { [3] = "on_demand", [5] = "at_login" },
}
LUA
}

launched_count() { hc clients -j | jq '[.[] | select(.class == "t-launch")] | length'; }

# "<workspace>/<slot>" of each t-launch window, sorted.
launched_places() {
  local s
  s=$(api state)
  hc clients -j | jq -r '.[] | select(.class == "t-launch") | .address' | while read -r address; do
    jq -r --arg a "$address" '"\(.assignments[$a].workspace)/\(.assignments[$a].slot)"' <<<"$s"
  done | sort | paste -sd ' '
}

workspaces_of() { hc clients -j | jq -r '[.[] | select(.class == "t-launch") | .workspace.id] | sort | map(tostring) | join(" ")'; }

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  # At login: workspace 5's app, once Hyprland has started.
  eventually 10 bash -c "[[ \$(hyprctl -i $E2E_SIG clients -j | jq '[.[] | select(.class == \"t-launch\")] | length') -ge 1 ]]" \
    || fail "nothing was launched at login"
  settle
  expect_eq "one app launched at login" 1 "$(launched_count)"
  expect_eq "onto workspace 5, into main" "5/main" "$(launched_places)"
  expect_eq "it opened on workspace 5" "5" "$(workspaces_of)"

  local s
  s=$(api state)
  expect_eq "state says how workspace 3's main launches" "t-launch desktop" \
    "$(jq -r '.launch_status["3"].main | "\(.desktop) \(.source)"' <<<"$s")"
  expect_eq "and that aside cannot" "can't launch: set a command" "$(jq -r '.launch_status["3"].aside.reason' <<<"$s")"

  # On demand: workspace 3's main; aside cannot be launched.
  local reply
  reply=$(api launch_missing '{"workspace": 3}')
  log "launch_missing: $reply"
  expect_eq "it launches main's app" "main" "$(jq -r '[.launched[].slot] | join(" ")' <<<"$reply")"
  expect_eq "and says aside cannot be" "aside" "$(jq -r '[.cannot[].slot] | join(" ")' <<<"$reply")"
  reply=$(api launch_missing '{"workspace": 3}')
  expect_eq "not twice while it is on its way" "" "$(jq -r '[.launched[].slot] | join(" ")' <<<"$reply")"
  eventually 10 bash -c "[[ \$(hyprctl -i $E2E_SIG clients -j | jq '[.[] | select(.class == \"t-launch\")] | length') -ge 2 ]]" \
    || fail "the app never opened"
  settle
  expect_eq "it went into workspace 3's main" "3/main 5/main" "$(launched_places)"
  expect_eq "on workspace 3, without showing it" "3 5" "$(workspaces_of)"
  reply=$(api launch_missing '{"workspace": 3}')
  expect_eq "nothing more to launch once it is there" "" "$(jq -r '[.launched[].slot] | join(" ")' <<<"$reply")"
  expect_eq "the command line (the Omarchy menu's entry) says what is left" "cannot launch aside: set a command (workspace 3)." \
    "$("$E2E_PLUGIN_DIR/tools/hyprslots" launch-missing 3 2>&1)"
  expect_eq "and Nothing to launch where every app is there" "Nothing to launch (workspace 5)." \
    "$("$E2E_PLUGIN_DIR/tools/hyprslots" launch-missing 5 2>&1)"

  # A config reload launches nothing.
  hc reload >/dev/null
  sleep 3
  expect_eq "a reload launches nothing" 2 "$(launched_count)"

  # Never: refused.
  expect_eq "launch set to never" true "$(api set_launch '{"workspace": 3, "mode": "never"}' | jq -r .ok)"
  expect_eq "then launch_missing is refused" "workspace 3 launches no apps: its launch setting is never" \
    "$(api launch_missing '{"workspace": 3}' | jq -r .error)"
  local out status=0
  out=$("$E2E_PLUGIN_DIR/tools/hyprslots" launch-missing 3 2>&1) || status=$?
  expect_eq "the command line says so" \
    "Launch missing apps: workspace 3 launches no apps: its launch setting is never" "$out"
  expect_eq "and fails" 1 "$status"
  expect_eq "and nothing launched" 2 "$(launched_count)"
}
