# Workspace numbers follow the active desk (docs/design.md §5): screen 1
# shows workspaces 1-10, screen 2 11-20, whatever Omarchy's state file said
# before. A monitor turned off in the config, as hyprmoncfg's profiles do,
# holds no block, so the screen left on its own shows 1-9, and turning it
# back on gives the screens their order again.
#
# Monitors (desks select them by connector; screens are numbered left to right):
#   left  = HEADLESS-2, 1920x1080 at 0,0      seeded as Omarchy block 0
#   right = HEADLESS-3, 1920x1080 at 1920,0   seeded as Omarchy block 1
# The config turns left off while $XDG_CONFIG_HOME/hypr/left-off exists, and
# `hyprctl reload` applies it, the way hyprmoncfg applies a profile.
#
# Desks: dual (both) on layout dual: screen 1 = main, screen 2 = side;
# right (right alone) on layout one: screen 1 = h[main, side].
# Windows: t-main (workspace 3, slot main), t-side (workspace 5, slot side),
# u-free (no slot, opened on right's workspace 7 = id 17).

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "1920x0", scale = 1 })
local flag = io.open(os.getenv("XDG_CONFIG_HOME") .. "/hypr/left-off", "r")
if flag then
  flag:close()
  hl.monitor({ output = "HEADLESS-2", disabled = true })
end
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = {}, side = {} },
  specs = {
    [3] = { main = "t-main" },
    [5] = { side = "t-side" },
  },
  desks = {
    dual = { monitors = { "HEADLESS-2", "HEADLESS-3" }, layout = "dual" },
    right = { monitors = { "HEADLESS-3" }, layout = "one" },
  },
  layouts = {
    dual = { screens = 2, default = { [1] = "main", [2] = "side" } },
    one = { screens = 1, default = { [1] = "h[main, side]" } },
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

workspace_monitor() {
  hc workspaces -j | jq -r --argjson id "$1" 'first(.[] | select(.id == $id)) | .monitor // empty'
}

# Omarchy's block file as "block:connector" pairs, one line.
blocks_file() {
  awk -F'\t' '{ printf "%s:%s ", $1, $2 }' "$E2E_STATE_HOME/omarchy/monitor-workspaces" | sed 's/ $//'
}

# Workspaces holding windows, as "id@monitor", sorted by id.
occupied() {
  hc workspaces -j | jq -r '[.[] | select(.id > 0 and .windows > 0)] | sort_by(.id) | map("\(.id)@\(.monitor)") | join(" ")'
}

expect_workspace_between() {
  local monitor=$1 low=$2 high=$3 actual
  actual=$(hc monitors -j | jq -r --arg m "$monitor" 'first(.[] | select(.name == $m)) | .activeWorkspace.id')
  if [[ -n $actual ]] && ((actual >= low && actual <= high)); then
    pass "$monitor shows workspace $actual (in $low-$high)"
  else
    fail "$monitor: expected a workspace in $low-$high, shows ${actual:-nothing}"
  fi
}

test_body() {
  output_create HEADLESS-2
  output_create HEADLESS-3
  [[ $(hyprslots_load_error | head -n1) == "" ]] || harness_fail "hyprslots failed to load: $(hyprslots_load_error)"
  eventually 5 is_desk dual || harness_fail "desk never became dual: $(active_desk)"

  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  spawn_and_wait t-main
  spawn_and_wait t-side
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-3' })" >/dev/null
  hc dispatch "hl.dsp.focus({ workspace = '17' })" >/dev/null
  spawn_and_wait u-free
  settle
  expect_eq "t-main on left's workspace 3" "3" "$(client_workspace t-main)"
  expect_eq "t-side on right's workspace 5" "15" "$(client_workspace t-side)"
  expect_eq "u-free on right's workspace 7" "17" "$(client_workspace u-free)"
  local before
  before=$(assignments)
  log "assignments: $before"

  # When left is turned off in the config and the config reloaded.
  touch "$E2E_CONFIG_HOME/hypr/left-off"
  hc reload >/dev/null
  eventually 10 is_desk right || fail "desk never became right: $(active_desk)"
  sleep 0.5
  settle
  log "left off: $(occupied); blocks: $(blocks_file)"

  # Then right, screen 1 now, holds block 0: workspaces 1-9, none in 11-19.
  expect_eq "Omarchy's blocks" "0:HEADLESS-3" "$(blocks_file)"
  expect_workspace_between HEADLESS-3 1 9
  expect_eq "workspaces with windows" "3@HEADLESS-3 5@HEADLESS-3 7@HEADLESS-3" "$(occupied)"
  expect_eq "t-main on workspace 3" "3" "$(client_workspace t-main)"
  expect_eq "t-side on workspace 5" "5" "$(client_workspace t-side)"
  expect_eq "u-free on workspace 7" "7" "$(client_workspace u-free)"
  expect_eq "assignments kept" "$before" "$(assignments)"

  # When left is turned back on.
  rm "$E2E_CONFIG_HOME/hypr/left-off"
  hc reload >/dev/null
  eventually 10 is_desk dual || fail "desk never became dual again: $(active_desk)"
  sleep 0.5
  settle
  log "left on: $(occupied); blocks: $(blocks_file)"

  # Then left is screen 1 again (1-9) and right screen 2 (11-19).
  expect_eq "Omarchy's blocks" "0:HEADLESS-2 1:HEADLESS-3" "$(blocks_file)"
  expect_workspace_between HEADLESS-2 1 9
  expect_workspace_between HEADLESS-3 11 19
  expect_eq "t-main on left's workspace 3" "3" "$(client_workspace t-main)"
  expect_eq "workspace 3 on left" "HEADLESS-2" "$(workspace_monitor 3)"
  expect_eq "t-side on right's workspace 5" "15" "$(client_workspace t-side)"
  expect_eq "workspace 15 on right" "HEADLESS-3" "$(workspace_monitor 15)"
  expect_eq "assignments kept" "$before" "$(assignments)"
  expect_eq "no workspace with windows left out of 1-9, 11-19" "" \
    "$(hc workspaces -j | jq -r '[.[] | select(.id > 0 and .windows > 0 and (.id % 10 == 0 or .id > 19))] | map(.id) | join(" ")')"

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
