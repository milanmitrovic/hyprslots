# Workspaces left behind on a monitor that was turned off (docs/design.md §5).
# Hyprland moves a disabled monitor's workspaces to another one, but when it
# was the only monitor on there is none: they stay on the disabled monitor,
# out of sight, and the monitor that comes up next starts on a workspace of
# its own. hyprslots brings them to the active desk's screens under their
# workspace numbers: block 0 is screen 1's.
#
# Monitors (desks select them by connector):
#   left  = HEADLESS-2, 1920x1080 at 0,0      seeded as Omarchy block 0
#   right = HEADLESS-3, 1920x1080 at 1920,0   seeded as Omarchy block 1
# Desks left (left alone) and right (right alone), both on layout one:
# screen 1 = main. Windows: t-main (workspace 3, slot main) and u-free (no
# slot, opened on workspace 5), both on left; then left is turned off while
# it is the only monitor, and right is plugged in.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "1920x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = { key = "m" } },
  specs = { [3] = { main = "t-main" } },
  desks = {
    left = { monitors = { "HEADLESS-2" }, layout = "one" },
    right = { monitors = { "HEADLESS-3" }, layout = "one" },
  },
  layouts = {
    one = { screens = 1, default = { [1] = "main" } },
  },
}
LUA
}

active_desk() { repl 'return hyprslots.api.state()' | jq -r .desk; }

is_desk() { [[ $(active_desk) == "$1" ]]; }

assignments() { repl 'return hyprslots.api.state()' | jq -cS .assignments; }

client_workspace() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

blocks_file() {
  awk -F'\t' '{ printf "%s:%s ", $1, $2 }' "$E2E_STATE_HOME/omarchy/monitor-workspaces" | sed 's/ $//'
}

occupied() {
  hc workspaces -j | jq -r '[.[] | select(.id > 0 and .windows > 0)] | sort_by(.id) | map("\(.id)@\(.monitor)") | join(" ")'
}

test_body() {
  output_create HEADLESS-2
  [[ $(hyprslots_load_error | head -n1) == "" ]] || harness_fail "hyprslots failed to load: $(hyprslots_load_error)"
  eventually 5 is_desk left || harness_fail "desk never became left: $(active_desk)"

  spawn_and_wait t-main
  hc dispatch "hl.dsp.focus({ workspace = '5' })" >/dev/null
  spawn_and_wait u-free
  settle
  expect_eq "t-main on workspace 3" "3" "$(client_workspace t-main)"
  expect_eq "u-free on workspace 5" "5" "$(client_workspace u-free)"
  local before
  before=$(assignments)

  # When left, the only monitor, is turned off, and right comes up after.
  [[ $(hc eval 'hl.monitor({ output = "HEADLESS-2", disabled = true })') == ok ]] || harness_fail "could not disable HEADLESS-2"
  sleep 0.5
  output_create HEADLESS-3
  eventually 10 is_desk right || fail "desk never became right: $(active_desk)"
  sleep 0.5
  settle
  log "after: $(occupied); blocks: $(blocks_file)"

  # Then nothing is left on the disabled monitor: right holds block 0 and
  # both windows under their workspace numbers.
  expect_eq "Omarchy's blocks" "0:HEADLESS-3" "$(blocks_file)"
  expect_eq "workspaces with windows" "3@HEADLESS-3 5@HEADLESS-3" "$(occupied)"
  expect_eq "t-main on workspace 3" "3" "$(client_workspace t-main)"
  expect_eq "u-free on workspace 5" "5" "$(client_workspace u-free)"
  local shown
  shown=$(hc monitors -j | jq -r 'first(.[] | select(.name == "HEADLESS-3")) | .activeWorkspace.id')
  if ((shown >= 1 && shown <= 9)); then pass "HEADLESS-3 shows workspace $shown"; else fail "HEADLESS-3 shows $shown, not 1-9"; fi
  expect_eq "assignments kept" "$before" "$(assignments)"
}
