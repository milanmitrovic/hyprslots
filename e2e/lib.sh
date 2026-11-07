# shellcheck shell=bash
# Helpers for e2e tests, sourced by run.sh. A test file defines:
#
#   test_setup   (optional) runs before Hyprland starts; writes config under
#                $E2E_CONFIG_HOME (hyprslots/config.lua, hypr/test-extra.lua)
#                and state under $E2E_STATE_HOME.
#   test_body    runs against the live test instance.
#
# Inside test_body, `harness_fail` aborts the test as a harness error (the
# environment is broken, the result means nothing); `expect_*` record a test
# failure and carry on, so one run reports every unmet expectation.

E2E_FAILURES=0

log() { printf '  %s\n' "$*"; }

harness_fail() {
  printf '  HARNESS ERROR: %s\n' "$*" >&2
  exit 2
}

fail() {
  printf '  FAIL: %s\n' "$*"
  E2E_FAILURES=$((E2E_FAILURES + 1))
}

pass() { printf '  ok: %s\n' "$*"; }

# hyprctl, always against the test instance.
hc() {
  [[ -n ${E2E_SIG:-} ]] || harness_fail "hc called with no test instance"
  hyprctl -i "$E2E_SIG" "$@"
}

# Evaluate Lua in the test instance and print what it returns.
repl() { hc repl "$1"; }

# Retry a command until it succeeds or the timeout (seconds) runs out.
eventually() {
  local timeout=$1
  shift
  local deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || return 1
    sleep 0.2
  done
}

monitor_names() { hc monitors -j | jq -r '.[].name' | sort | tr '\n' ' ' | sed 's/ $//'; }

has_monitor() { hc monitors -j | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null; }

lacks_monitor() { ! has_monitor "$1"; }

output_create() {
  local name=$1 reply
  reply=$(hc output create headless "$name")
  [[ $reply == ok ]] || harness_fail "output create headless $name: $reply"
  eventually 5 has_monitor "$name" || harness_fail "monitor $name never appeared (have: $(monitor_names))"
}

output_remove() {
  local name=$1 reply
  reply=$(hc output remove "$name")
  [[ $reply == ok ]] || harness_fail "output remove $name: $reply"
  eventually 5 lacks_monitor "$name" || harness_fail "monitor $name never went away (have: $(monitor_names))"
}

# Seed Omarchy's per-monitor workspace blocks so connector N in the argument
# list owns block N-1 (the first gets workspaces 1-10, the second 11-20...).
# Call from test_setup.
seed_workspace_blocks() {
  local block=0 file=$E2E_STATE_HOME/omarchy/monitor-workspaces
  mkdir -p "${file%/*}"
  : >"$file"
  for connector in "$@"; do
    printf '%d\t\t%s\n' "$block" "$connector" >>"$file"
    block=$((block + 1))
  done
}

# Start a foot client whose app-id (Hyprland class) is $1, on the test
# instance's Wayland socket. It is killed at teardown.
spawn() {
  local class=$1
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY foot --config=/dev/null --app-id="$class" --title="$class" \
    sleep 3600 >>"$E2E_DIR/clients.log" 2>&1 &
  E2E_CLIENT_PIDS+=("$!")
}

client_mapped() {
  hc clients -j | jq -e --arg c "$1" 'any(.[]; .class == $c and .mapped)' >/dev/null
}

spawn_and_wait() {
  spawn "$1"
  eventually 10 client_mapped "$1" || harness_fail "client $1 never mapped"
}

# Wait until window geometry stops changing (three identical polls in a row).
settle() {
  local previous='' current same=0 deadline=$((SECONDS + ${1:-5}))
  while ((SECONDS < deadline)); do
    current=$(hc clients -j | jq -c 'sort_by(.class) | map([.class, .workspace.id, .at, .size])')
    if [[ $current == "$previous" ]]; then
      same=$((same + 1))
      ((same >= 3)) && return 0
    else
      same=0
    fi
    previous=$current
    sleep 0.15
  done
}

# Print one line per client: class workspace x y w h
client_table() {
  hc clients -j | jq -r 'sort_by(.class)[] | "\(.class) ws=\(.workspace.id) at=\(.at[0]),\(.at[1]) size=\(.size[0])x\(.size[1])"'
}

near() { local d=$(($1 - $2)); ((d >= -1 && d <= 1)); }

# expect_client CLASS WORKSPACE X Y W H — geometry within ±1 px.
expect_client() {
  local class=$1 ws=$2 x=$3 y=$4 w=$5 h=$6 row
  row=$(hc clients -j | jq -r --arg c "$class" 'first(.[] | select(.class == $c)) | "\(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
  if [[ -z $row ]]; then
    fail "$class: no such client"
    return
  fi
  local aws ax ay aw ah
  read -r aws ax ay aw ah <<<"$row"
  if [[ $aws == "$ws" ]] && near "$ax" "$x" && near "$ay" "$y" && near "$aw" "$w" && near "$ah" "$h"; then
    pass "$class on workspace $ws at $x,$y size ${w}x$h"
  else
    fail "$class: expected workspace $ws at $x,$y size ${w}x$h, got workspace $aws at $ax,$ay size ${aw}x$ah"
  fi
}

# expect_monitor_workspace MONITOR WORKSPACE
expect_monitor_workspace() {
  local monitor=$1 ws=$2 actual
  actual=$(hc monitors -j | jq -r --arg m "$monitor" 'first(.[] | select(.name == $m)) | .activeWorkspace.id')
  if [[ $actual == "$ws" ]]; then
    pass "$monitor shows workspace $ws"
  else
    fail "$monitor: expected workspace $ws, shows ${actual:-nothing}"
  fi
}

# expect_eq DESCRIPTION EXPECTED ACTUAL
expect_eq() {
  if [[ $3 == "$2" ]]; then
    pass "$1"
  else
    fail "$1: expected '$2', got '$3'"
  fi
}

# The error hyprland-test.lua caught while loading hyprslots, or empty.
# (`hyprctl repl` answers an empty string with "unknown request", so the
# no-error case travels as a sentinel.)
hyprslots_load_error() {
  local reply
  reply=$(repl 'return hyprslots_load_error or "<none>"')
  [[ $reply == "<none>" ]] && reply=''
  printf '%s' "$reply"
}
