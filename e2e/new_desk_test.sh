# A monitor set no desk knows gets a desk of its own (docs/design.md §8):
# once the set has held for a second, the engine makes a desk named after its
# monitors, with a new layout (screen 1 = h[left, main, right]) when no
# layout for that many screens has run yet, else the most recently used one.
# Both are unsaved until `save` writes them to slots.lua.
#
# Monitors (desks select them by connector; screens are numbered left to right):
#   HEADLESS-2, 2400x1350 at 0,0      Omarchy block 0: workspace N = workspace id N
#   HEADLESS-3, 1920x1080 at 2400,0   Omarchy block 1
#   HEADLESS-4, 1920x1080 at 2400,0   Omarchy block 2
#
# The only configured desk is solo = { HEADLESS-2 }, layout solo (1 screen):
# workspace 3 = h[left, main:2, right] -> 600 + 1200 + 600 px. With
# HEADLESS-3 added, desk headless-2+headless-3 gets a new layout of that name
# whose default trees put left, main and right in three equal columns
# (800 px each) on screen 1 (HEADLESS-2), screen 2 empty. Swapping
# HEADLESS-3 for HEADLESS-4 makes desk headless-2+headless-4, which reuses
# that layout (the most recently used 2-screen one) rather than layout
# a-wide (an empty 2-screen layout, first by name) or a new one.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HEADLESS-3", mode = "1920x1080@60", position = "2400x0", scale = 1 })
hl.monitor({ output = "HEADLESS-4", mode = "1920x1080@60", position = "2400x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2 HEADLESS-3 HEADLESS-4

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { left = {}, main = {}, right = {} },
  specs = {
    [3] = { left = "t-left", main = "t-main", right = "t-right" },
  },
  desks = {
    solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
  },
  layouts = {
    solo = {
      screens = 1,
      workspaces = { [3] = { [1] = "h[left, main:2, right]" } },
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

# What slots.lua on disk says about desk $1 and its layout, one line.
saved_desk() {
  local file=$E2E_CONFIG_HOME/hyprslots/slots.lua
  repl "local d = dofile('$file')
    local desk = (d.desks or {})['$1']
    if not desk then return 'no desk' end
    local layout = (d.layouts or {})[desk.layout]
    if not layout then return 'monitors=' .. table.concat(desk.monitors or {}, ',') .. ' layout=' .. tostring(desk.layout) .. ' (missing)' end
    return 'monitors=' .. table.concat(desk.monitors or {}, ',') .. ' layout=' .. tostring(desk.layout)
      .. ' screens=' .. tostring(layout.screens) .. ' default1=' .. tostring((layout.default or {})[1])
      .. ' default2=' .. tostring((layout.default or {})[2])"
}

expect_three_columns() {
  expect_client t-left 3 0 0 800 1350
  expect_client t-main 3 800 0 800 1350
  expect_client t-right 3 1600 0 800 1350
}

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  eventually 5 is_desk solo || true
  expect_eq "desk with HEADLESS-2" "solo" "$(active_desk)"

  # Given the three windows routed to workspace 3 and shown in solo's tree.
  hc dispatch "hl.dsp.focus({ monitor = 'HEADLESS-2' })" >/dev/null
  for class in t-right t-left t-main; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
  done
  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  settle
  expect_client t-left 3 0 0 600 1350
  expect_client t-main 3 600 0 1200 1350
  expect_client t-right 3 1800 0 600 1350
  expect_eq "saved to start with" "false" "$(api state | field .dirty)"

  # When HEADLESS-3 joins, a set no desk knows, and stays.
  output_create HEADLESS-3
  eventually 5 is_desk headless-2+headless-3 || fail "no new desk: desk is $(active_desk)"

  # Then a desk is made for it, with a new layout of the same name.
  local state name=headless-2+headless-3
  state=$(api state)
  expect_eq "new desk" "$name" "$(field .desk <<<"$state")"
  expect_eq "made by the engine" "true" "$(field ".desks[\"$name\"].auto" <<<"$state")"
  expect_eq "its monitors" '["HEADLESS-2","HEADLESS-3"]' "$(jq -c --arg n "$name" '.desks[$n].monitors' <<<"$state")"
  expect_eq "its screens" '["HEADLESS-2","HEADLESS-3"]' "$(jq -c .screens <<<"$state")"
  expect_eq "new layout" "$name" "$(field .layout <<<"$state")"
  expect_eq "desk's layout" "$name" "$(field ".desks[\"$name\"].layout" <<<"$state")"
  expect_eq "layout screens" "2" "$(field ".layouts[\"$name\"].screens" <<<"$state")"
  expect_eq "default tree, screen 1" "h[left, main, right]" "$(field ".layouts[\"$name\"].default[\"1\"].tree" <<<"$state")"
  expect_eq "unsaved" "true" "$(field .dirty <<<"$state")"

  # And workspace 3 on HEADLESS-2 shows the three slots in equal columns.
  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  settle
  expect_monitor_workspace HEADLESS-2 3
  expect_three_columns

  # When saved, slots.lua holds the desk and its layout, and they are no
  # longer the engine's own.
  local reply
  reply=$(api save)
  log "save -> $reply"
  expect_eq "save ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "slots.lua holds the desk and layout" \
    "monitors=HEADLESS-2,HEADLESS-3 layout=$name screens=2 default1=h[left, main, right] default2=nil" \
    "$(saved_desk "$name")"
  expect_eq "slots.lua keeps desk solo" \
    "monitors=HEADLESS-2 layout=solo screens=1 default1=nil default2=nil" "$(saved_desk solo)"
  state=$(api state)
  expect_eq "saved" "false" "$(field .dirty <<<"$state")"
  expect_eq "no longer auto" "" "$(field ".desks[\"$name\"].auto // empty" <<<"$state")"

  # Given another 2-screen layout, first by name but never used.
  reply=$(api add_layout '{"name": "a-wide", "screens": 2}')
  log "add_layout -> $reply"
  expect_eq "add_layout ok" "true" "$(field .ok <<<"$reply")"

  # When HEADLESS-3 is swapped for HEADLESS-4.
  output_remove HEADLESS-3
  eventually 5 is_desk solo || fail "desk never went back to solo: $(active_desk)"
  output_create HEADLESS-4
  local second=headless-2+headless-4
  eventually 5 is_desk "$second" || fail "no second new desk: desk is $(active_desk)"

  # Then the second new desk reuses the most recently used 2-screen layout.
  state=$(api state)
  expect_eq "second new desk" "$second" "$(field .desk <<<"$state")"
  expect_eq "made by the engine" "true" "$(field ".desks[\"$second\"].auto" <<<"$state")"
  expect_eq "its monitors" '["HEADLESS-2","HEADLESS-4"]' "$(jq -c --arg n "$second" '.desks[$n].monitors' <<<"$state")"
  expect_eq "reused layout" "$name" "$(field .layout <<<"$state")"
  expect_eq "no layout made for it" "" "$(field ".layouts[\"$second\"] // empty" <<<"$state")"
  expect_eq "layouts" "[\"a-wide\",\"$name\",\"solo\"]" "$(jq -c '.layouts | keys' <<<"$state")"
  expect_eq "the layout is used by both new desks" "[\"$name\",\"$second\"]" \
    "$(jq -c --arg n "$name" '.layouts[$n].used_by' <<<"$state")"
  expect_eq "unsaved" "true" "$(field .dirty <<<"$state")"

  log "workspace 3 -> $(api workspace '{"workspace": 3}')"
  settle
  expect_three_columns

  log "windows at the end:"
  client_table | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 12 | sed 's/^/    /'
}
