# Cross-slice: a keyboard nudge (slice 5) with the overflow column showing
# (slice 4) is pixel-exact, and the editor api (slice 6) saves it, so it
# survives an api reload and a full Hyprland config reload.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (workspace N = workspace id N).
# Workspace 3, arrangement "solo": h[a, b]; t-other has no slot, so the layout is
# h[h[a, b]:3, *:1]: a 900, b 900, overflow 600 px.
#
# "nudge r 100px" on a moves the a|b edge exactly 100 px (a 1000, b 800) and
# leaves the overflow column alone; the nudged tree is h[a:5, b:4].

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
  slots = { a = {}, b = {} },
  specs = {
    [3] = { a = "t-a", b = "t-b" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a, b]" } },
    },
  },
}
LUA
}

api() {
  local args=${2:-'{}'}
  args=${args//\\/\\\\}
  args=${args//\"/\\\"}
  repl "return hyprslots.api.call(\"$1\", \"$args\")"
}

field() { jq -r "$1 | if . == null then \"\" else tostring end" 2>/dev/null; }

main_tree() { api state | field '.arrangements.solo.workspaces["3"].main.tree'; }

tree_is() { [[ $(main_tree) == "$1" ]]; }

active_class() { hc activewindow -j | jq -r '.class // empty'; }

is_active() { [[ $(active_class) == "$1" ]]; }

expect_nudged_layout() {
  expect_client t-a 3 0 0 1000 1350
  expect_client t-b 3 1000 0 800 1350
  expect_client t-other 3 1800 0 600 1350
}

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  for class in t-a t-b t-other; do
    spawn_and_wait "$class"
  done
  settle
  expect_client t-a 3 0 0 900 1350
  expect_client t-b 3 900 0 900 1350
  expect_client t-other 3 1800 0 600 1350

  hc dispatch 'hl.dsp.focus({ window = "class:t-a" })' >/dev/null
  eventually 5 is_active t-a || true
  expect_eq "t-a focused" "t-a" "$(active_class)"

  # When a is nudged 100 px right with the overflow column showing, the edge
  # moves exactly 100 px.
  log "nudge -> $(hc dispatch 'hl.dsp.layout("nudge r 100px")' 2>&1)"
  settle
  expect_nudged_layout

  # Then the api reports the nudge as an unsaved override.
  local state
  state=$(api state)
  expect_eq "state tree" "h[a:5, b:4]" "$(field '.arrangements.solo.workspaces["3"].main.tree' <<<"$state")"
  expect_eq "override listed" "h[a:5, b:4]" "$(field '.resized["solo/3/main"].tree' <<<"$state")"
  expect_eq "unsaved" "true" "$(field .dirty <<<"$state")"

  # When saved, slots.lua holds the nudged tree and the override is gone.
  local reply
  reply=$(api save)
  log "save -> $reply"
  expect_eq "save ok" "true" "$(field .ok <<<"$reply")"
  if grep -q 'main = "h\[a:5, b:4\]"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "slots.lua holds the nudged tree"
  else
    fail "slots.lua does not hold the nudged tree:"
    sed 's/^/    /' "$E2E_CONFIG_HOME/hyprslots/slots.lua"
  fi
  state=$(api state)
  expect_eq "no override after save" "{}" "$(jq -c '.resized' <<<"$state")"
  expect_eq "saved" "false" "$(field .dirty <<<"$state")"
  settle
  expect_nudged_layout

  # When the config is reloaded through the api, the layout stays.
  reply=$(api reload)
  log "reload -> $reply"
  expect_eq "reload ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "tree after api reload" "h[a:5, b:4]" "$(main_tree)"
  settle
  expect_nudged_layout

  # When Hyprland reloads its whole config (Lua state discarded), it stays too.
  log "hyprctl reload -> $(hc reload)"
  eventually 5 tree_is "h[a:5, b:4]" || true
  expect_eq "tree after Hyprland reload" "h[a:5, b:4]" "$(main_tree)"
  settle
  expect_nudged_layout

  log "windows at the end:"
  client_table | sed 's/^/    /'
}
