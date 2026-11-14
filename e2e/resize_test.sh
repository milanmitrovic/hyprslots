# Keyboard resize (slice 5): layout messages to the slots provider.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (workspace N = workspace id N).
# Workspace 3, desk and layout "solo": h[a:1, b:1] -> 1200 + 1200 px.
#
# With a focused, `hl.dsp.layout("nudge r 0.1")` moves the a|b edge right by
# 0.1 of the split (240 px): a 1440, b 960. "reset" goes back to 1200 + 1200.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { a = { key = "a" }, b = { key = "b" } },
  specs = {
    [3] = { a = "t-a", b = "t-b" },
  },
  desks = {
    solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
  },
  layouts = {
    solo = {
      screens = 1,
      workspaces = { [3] = { [1] = "h[a:1, b:1]" } },
    },
  },
}
LUA
}

active_class() { hc activewindow -j | jq -r '.class // empty'; }

is_active() { [[ $(active_class) == "$1" ]]; }

# Send a layout message to the focused workspace's layout, as a bind would.
# The reply is kept in LAYOUT_REPLY.
layout_msg() {
  LAYOUT_REPLY=$(hc dispatch "hl.dsp.layout(\"$1\")" 2>&1)
  log "layout \"$1\" -> $LAYOUT_REPLY"
  settle
}

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")' 2>&1)"
  spawn_and_wait t-a
  spawn_and_wait t-b
  settle

  expect_monitor_workspace HEADLESS-2 3
  expect_client t-a 3 0 0 1200 1350
  expect_client t-b 3 1200 0 1200 1350

  hc dispatch 'hl.dsp.focus({ window = "class:t-a" })' >/dev/null
  eventually 5 is_active t-a || true
  expect_eq "t-a focused" "t-a" "$(active_class)"

  # When a nudges right by 0.1 of the split, the a|b edge moves 240 px.
  layout_msg "nudge r 0.1"
  expect_client t-a 3 0 0 1440 1350
  expect_client t-b 3 1440 0 960 1350

  # Pixels, the way the rebound Omarchy resize binds send them.
  layout_msg "resize -100 0"
  expect_client t-a 3 0 0 1340 1350
  expect_client t-b 3 1340 0 1060 1350

  # Reset goes back to the configured tree.
  layout_msg "reset"
  expect_client t-a 3 0 0 1200 1350
  expect_client t-b 3 1200 0 1200 1350

  # A nudge with nothing on that side changes nothing, and says why.
  layout_msg "nudge l 0.1"
  expect_client t-a 3 0 0 1200 1350
  [[ $LAYOUT_REPLY == *"nothing left of 'a'"* ]] && pass "refusal reported" || fail "refusal not reported: $LAYOUT_REPLY"

  # Omarchy's resize keys, rebound: on this lua:slots workspace the action
  # sends "resize 100 0" (the keybindings menu replays the same expression).
  expect_eq "workspace layout" "lua:slots" "$(repl 'return hl.get_active_workspace().tiled_layout')"
  log "bind_resize_keys -> $(repl 'hyprslots.bind_resize_keys() return "done"' 2>&1)"
  log "resize key -> $(hc dispatch 'hyprslots.resize_key(100, 0)' 2>&1)"
  settle
  expect_client t-a 3 0 0 1300 1350
  expect_client t-b 3 1300 0 1100 1350

  log "windows at the end:"
  client_table | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 8 | sed 's/^/    /'
}
