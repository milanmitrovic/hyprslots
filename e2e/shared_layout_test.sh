# Two desks share one layout: an edit made on one desk shows on the other
# (docs/design.md §3, §8).
#
# Monitors (desks select them by connector):
#   HEADLESS-2, 2400x1350 at 0,0      Omarchy block 0: workspace N = workspace id N
#   HEADLESS-3, 1920x1080 at 2400,0   Omarchy block 1: workspace N = workspace id 10+N
#
# Desks two = { HEADLESS-2 } and three = { HEADLESS-3 } both use layout solo
# (1 screen): workspace 3, screen 1 = h[left, main].
#
# With HEADLESS-2 alone, desk two tiles left | main 1200 + 1200 px. set_tree
# makes the tree h[main, left] (unsaved). Swapping the monitors (HEADLESS-3
# plugged, HEADLESS-2 unplugged right after: the two-monitor set in between
# is gone long before a new desk would be made for it) selects desk three,
# which shows the edited tree on HEADLESS-3: main | left, 960 + 960 px on
# workspace id 13, where both windows are re-routed. The edit is still
# unsaved: it is the same layout.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "2400x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { left = {}, main = {} },
  specs = {
    [3] = { left = "t-left", main = "t-main" },
  },
  desks = {
    two = { monitors = { "HEADLESS-2" }, layout = "solo" },
    three = { monitors = { "HEADLESS-3" }, layout = "solo" },
  },
  layouts = {
    solo = {
      screens = 1,
      workspaces = { [3] = { [1] = "h[left, main]" } },
    },
  },
}
LUA
}

# hyprslots.api.call(name, json) -> its JSON reply.
api() {
  local args=${2:-'{}'}
  args=${args//\\/\\\\}
  args=${args//\"/\\\"}
  repl "return hyprslots.api.call(\"$1\", \"$args\")"
}

# A field of a JSON reply (jq path).
field() { jq -r "$1 | if . == null then \"\" else tostring end" 2>/dev/null; }

active_desk() { api state | field .desk; }

is_desk() { [[ $(active_desk) == "$1" ]]; }

workspace_of() {
  hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id'
}

on_workspace() { [[ $(workspace_of "$1") == "$2" ]]; }

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  eventually 5 is_desk two || true

  local state
  state=$(api state)
  expect_eq "desk with HEADLESS-2" "two" "$(field .desk <<<"$state")"
  expect_eq "its layout" "solo" "$(field .layout <<<"$state")"
  expect_eq "solo used by both desks" '["three","two"]' "$(jq -c '.layouts.solo.used_by' <<<"$state")"

  # Given t-left and t-main routed to workspace 3 and shown there.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-main t-left; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
  done
  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  settle
  expect_monitor_workspace HEADLESS-2 3
  expect_client t-left 3 0 0 1200 1350
  expect_client t-main 3 1200 0 1200 1350

  # When the layout's tree is edited on desk two.
  local reply
  reply=$(api set_tree '{"workspace": 3, "screen": 1, "tree": "h[main, left]"}')
  log "set_tree -> $reply"
  expect_eq "set_tree ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "set_tree edits the active desk's layout" "solo" "$(field .layout <<<"$reply")"
  expect_eq "set_tree tree" "h[main, left]" "$(field .tree <<<"$reply")"
  settle
  expect_client t-main 3 0 0 1200 1350
  expect_client t-left 3 1200 0 1200 1350
  expect_eq "unsaved" "true" "$(api state | field .dirty)"

  # When the monitors are swapped: HEADLESS-3 in, HEADLESS-2 out right after.
  output_create HEADLESS-3
  output_remove HEADLESS-2
  eventually 10 is_desk three || fail "desk never became three: $(active_desk)"
  for class in t-main t-left; do
    eventually 10 on_workspace "$class" 13 || true
  done

  # Then desk three uses the same, edited, still unsaved layout.
  state=$(api state)
  expect_eq "desk with HEADLESS-3" "three" "$(field .desk <<<"$state")"
  expect_eq "its layout" "solo" "$(field .layout <<<"$state")"
  expect_eq "screens" '["HEADLESS-3"]' "$(jq -c .screens <<<"$state")"
  expect_eq "the edit carried over" "h[main, left]" "$(field '.layouts.solo.workspaces["3"]["1"].tree' <<<"$state")"
  expect_eq "solo used by both desks" '["three","two"]' "$(jq -c '.layouts.solo.used_by' <<<"$state")"
  expect_eq "still unsaved" "true" "$(field .dirty <<<"$state")"

  # And workspace 3 on HEADLESS-3 holds both windows, in the edited tree.
  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  settle
  expect_monitor_workspace HEADLESS-3 13
  expect_client t-main 13 2400 0 960 1080
  expect_client t-left 13 3360 0 960 1080

  # And the two-monitor set the swap passed through got no desk of its own.
  sleep 1.5
  state=$(api state)
  expect_eq "only the configured desks" '["three","two"]' "$(jq -c '.desks | keys' <<<"$state")"
  expect_eq "no auto desk" "0" "$(jq '[.desks[] | select(.auto)] | length' <<<"$state")"
  expect_eq "desk still three" "three" "$(field .desk <<<"$state")"

  log "windows at the end:"
  client_table | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 12 | sed 's/^/    /'
}
