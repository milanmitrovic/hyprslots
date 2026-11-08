# Cross-slice: a second window of a class whose only slot is taken (slice 3's
# routing and window rules) lands in that workspace's overflow leaf (slice 4), and
# takes the slot when the first window closes.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (workspace N = workspace id N).
# Workspace 3, arrangement "solo": h[main, right]. With an extra window the layout
# is h[h[main, right]:3, *:1]: main 900, right 900, overflow 600 px.

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
  slots = { main = {}, right = {} },
  specs = {
    [3] = { main = "t-main", right = "t-right" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[main, right]" } },
    },
  },
}
LUA
}

# Rows "pid workspace x y w" for the t-main windows, oldest pid first.
t_main_rows() {
  hc clients -j | jq -r '[.[] | select(.class == "t-main")] | sort_by(.pid)[] | "\(.pid) \(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0])"'
}

count_on_3() { [[ $(hc clients -j | jq '[.[] | select(.workspace.id == 3)] | length') == "$1" ]]; }

expect_row() {
  local what=$1 row=$2 ws=$3 x=$4 w=$5
  local pid aws ax ay aw
  read -r pid aws ax ay aw <<<"$row"
  if [[ $aws == "$ws" ]] && near "$ax" "$x" && near "$ay" 0 && near "$aw" "$w"; then
    pass "$what (pid $pid) on workspace $ws at x=$x width $w"
  else
    fail "$what: expected workspace $ws at x=$x width $w, got '$row'"
  fi
}

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  # Given two t-main windows and a t-right opened on workspace 1.
  spawn_and_wait t-main
  local first_pid=${E2E_CLIENT_PIDS[-1]}
  spawn t-main
  eventually 10 bash -c "[[ \$(hyprctl -i $E2E_SIG clients -j | jq '[.[] | select(.class == \"t-main\" and .mapped)] | length') == 2 ]]" ||
    harness_fail "the second t-main never mapped"
  spawn_and_wait t-right
  eventually 10 count_on_3 3 || true

  # Then all three are on workspace 3: the extra t-main in the overflow column.
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")')"
  settle
  local rows
  mapfile -t rows < <(t_main_rows)
  expect_row "the first t-main in slot main" "${rows[0]}" 3 0 900
  expect_row "the extra t-main in the overflow" "${rows[1]}" 3 1800 600
  expect_client t-right 3 900 0 900 1350

  # When the first t-main closes, the extra one takes its slot.
  kill "$first_pid"
  eventually 10 count_on_3 2 || fail "the first t-main never closed"
  settle
  mapfile -t rows < <(t_main_rows)
  expect_eq "one t-main left" "1" "${#rows[@]}"
  expect_row "the former extra in slot main" "${rows[0]}" 3 0 1200
  expect_client t-right 3 1200 0 1200 1350

  log "windows at the end:"
  client_table | sed 's/^/    /'
  log "log:"
  repl 'return hyprslots.dump()' | sed -n '/^log:/,$p' | tail -n 12 | sed 's/^/    /'
}
