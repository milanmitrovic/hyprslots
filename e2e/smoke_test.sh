# Harness smoke test: the nested instance comes up, a headless output can be
# created, and a client maps and tiles on it. No hyprslots behaviour.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2
}

test_body() {
  output_create HEADLESS-2
  expect_eq "monitors" "HEADLESS-2" "$(monitor_names)"

  spawn_and_wait t-smoke
  settle
  expect_client t-smoke 1 0 0 1920 1080
}
