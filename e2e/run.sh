#!/usr/bin/env bash
# e2e harness: run each e2e/*_test.sh against its own nested Hyprland.
#
#   e2e/run.sh                      every test
#   e2e/run.sh e2e/smoke_test.sh    just these
#   E2E_KEEP=1 e2e/run.sh           keep temp dirs (logs) even on success
#
# Per test: a headless sway host (WLR_BACKENDS=headless) gives Hyprland's
# Wayland backend a GPU allocator; Hyprland 0.56.2 itself cannot run
# headless-only inside a live session (its DRM backend cannot take the seat).
# Hyprland runs with -c e2e/hyprland-test.lua, temp XDG_CONFIG_HOME /
# XDG_STATE_HOME / XDG_CACHE_HOME under .e2e-tmp/, and a private
# XDG_RUNTIME_DIR, so neither it nor hyprctl can even see the live session's
# sockets. It is driven only with `hyprctl -i <its signature>`.
#
# Exit status: 0 all passed, 1 a test failed, 2 a harness error.

set -uo pipefail

E2E_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
E2E_TMP_ROOT=$E2E_ROOT/.e2e-tmp
SHIM_SRC=$E2E_ROOT/e2e/shim/clamp-xdg-wm-base.c
SHIM=$E2E_TMP_ROOT/clamp-xdg-wm-base.so

die() {
  printf 'e2e: %s\n' "$*" >&2
  exit 2
}

for tool in sway Hyprland hyprctl foot jq gcc pkg-config; do
  command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

mkdir -p "$E2E_TMP_ROOT"

# The LD_PRELOAD shim that lets aquamarine bind sway's xdg_wm_base (see the
# source for why). Rebuilt when the source changes.
if [[ ! -f $SHIM || $SHIM_SRC -nt $SHIM ]]; then
  # shellcheck disable=SC2046
  gcc -shared -fPIC -O2 -Wall -o "$SHIM" "$SHIM_SRC" $(pkg-config --cflags --libs wayland-client) ||
    die "could not build $SHIM"
fi

# Wait for a condition (a command) for up to $1 seconds.
wait_for() {
  local timeout=$1
  shift
  local deadline=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || return 1
    sleep 0.1
  done
}

alive() { kill -0 "$1" 2>/dev/null; }

# Stop a process we started: TERM, then KILL after $2 seconds.
stop() {
  local pid=$1 grace=${2:-3}
  alive "$pid" || return 0
  kill -TERM "$pid" 2>/dev/null
  wait_for "$grace" bash -c "! kill -0 $pid" || kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

# Run one test file in a subshell that owns its whole environment.
run_test() (
  local test_file=$1 name
  name=$(basename "$test_file" .sh)

  E2E_DIR=$(mktemp -d "$E2E_TMP_ROOT/$name.XXXXXX")
  E2E_CONFIG_HOME=$E2E_DIR/config
  E2E_STATE_HOME=$E2E_DIR/state
  E2E_CACHE_HOME=$E2E_DIR/cache
  mkdir -p "$E2E_CONFIG_HOME/hypr" "$E2E_STATE_HOME" "$E2E_CACHE_HOME"

  # Unix socket paths are limited to 108 bytes and Hyprland's live at
  # $XDG_RUNTIME_DIR/hypr/<62-char signature>/.socket2.sock, so the private
  # runtime dir sits directly under the user's.
  E2E_RUNTIME_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hs.XXXXXX") || die "no runtime dir"
  chmod 700 "$E2E_RUNTIME_DIR"

  SWAY_PID='' HYPR_PID='' E2E_SIG='' E2E_CLIENT_PIDS=()

  teardown() {
    local status=$?
    for pid in "${E2E_CLIENT_PIDS[@]}"; do stop "$pid" 1; done
    if [[ -n $HYPR_PID ]] && alive "$HYPR_PID"; then
      [[ -n $E2E_SIG ]] && hyprctl -i "$E2E_SIG" dispatch 'hl.dsp.exit()' >/dev/null 2>&1
      wait_for 5 bash -c "! kill -0 $HYPR_PID" || stop "$HYPR_PID" 2
    fi
    [[ -n $SWAY_PID ]] && stop "$SWAY_PID" 2
    if [[ -n $E2E_SIG && -f $E2E_RUNTIME_DIR/hypr/$E2E_SIG/hyprland.log ]]; then
      cp "$E2E_RUNTIME_DIR/hypr/$E2E_SIG/hyprland.log" "$E2E_DIR/hyprland.log"
    fi
    rm -rf "$E2E_RUNTIME_DIR"
    if ((status == 0)) && [[ -z ${E2E_KEEP:-} ]]; then
      rm -rf "$E2E_DIR"
    else
      printf '  logs: %s\n' "$E2E_DIR"
    fi
    exit "$status"
  }
  trap teardown EXIT
  trap 'exit 130' INT TERM

  # Nothing below may reach the live session: no inherited compositor,
  # instance, X display, session bus or systemd notify socket.
  unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DISPLAY SWAYSOCK DBUS_SESSION_BUS_ADDRESS NOTIFY_SOCKET
  export XDG_RUNTIME_DIR=$E2E_RUNTIME_DIR
  export XDG_CONFIG_HOME=$E2E_CONFIG_HOME XDG_STATE_HOME=$E2E_STATE_HOME XDG_CACHE_HOME=$E2E_CACHE_HOME
  export HYPRSLOTS_ROOT=$E2E_ROOT
  export E2E_DIR E2E_CONFIG_HOME E2E_STATE_HOME

  # shellcheck source=e2e/lib.sh
  source "$E2E_ROOT/e2e/lib.sh"
  # shellcheck disable=SC1090
  source "$test_file"
  declare -F test_body >/dev/null || die "$test_file defines no test_body"

  printf '%s\n' "$name"
  if declare -F test_setup >/dev/null; then test_setup; fi

  # The host compositor.
  WLR_BACKENDS=headless WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 \
    WLR_LIBINPUT_NO_DEVICES=1 SWAYSOCK=$E2E_RUNTIME_DIR/sway.sock \
    sway --config "$E2E_ROOT/e2e/sway.conf" >"$E2E_DIR/sway.log" 2>&1 &
  SWAY_PID=$!
  local host_socket=''
  host_ready() {
    # The runtime dir is fresh, so sway's socket is the only one in it.
    local sock
    for sock in "$E2E_RUNTIME_DIR"/wayland-*; do
      [[ -S $sock ]] && host_socket=${sock##*/} && return 0
    done
    return 1
  }
  wait_for 10 host_ready || { alive "$SWAY_PID" || harness_fail "sway exited, see $E2E_DIR/sway.log"; harness_fail "sway socket never appeared"; }

  # Hyprland, on sway, through its Wayland backend.
  WAYLAND_DISPLAY=$host_socket LD_PRELOAD=$SHIM \
    HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 \
    Hyprland --config "$E2E_ROOT/e2e/hyprland-test.lua" >"$E2E_DIR/hyprland.stdout" 2>&1 &
  HYPR_PID=$!

  find_instance() {
    E2E_SIG=$(hyprctl instances -j 2>/dev/null | jq -r --argjson pid "$HYPR_PID" 'first(.[] | select(.pid == $pid)) | .instance // empty')
    [[ -n $E2E_SIG ]] && hyprctl -i "$E2E_SIG" version -j >/dev/null 2>&1
  }
  if ! wait_for 15 find_instance; then
    alive "$HYPR_PID" || harness_fail "Hyprland exited at startup, see $E2E_DIR/hyprland.stdout"
    harness_fail "Hyprland (pid $HYPR_PID) never answered hyprctl"
  fi
  E2E_WAYLAND_DISPLAY=$(hyprctl instances -j | jq -r --arg s "$E2E_SIG" 'first(.[] | select(.instance == $s)) | .wl_socket')
  export E2E_SIG E2E_WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG
  log "instance $E2E_SIG (pid $HYPR_PID, $E2E_WAYLAND_DISPLAY on host $host_socket)"

  local errors
  errors=$(hc configerrors -j | jq -r '.[] | select(. != "")')
  [[ -z $errors ]] || log "config errors: $errors"

  test_body
  ((E2E_FAILURES == 0)) || exit 1
  exit 0
)

tests=("$@")
if ((${#tests[@]} == 0)); then
  tests=("$E2E_ROOT"/e2e/*_test.sh)
fi

passed=0 failed=0 broken=0
for test_file in "${tests[@]}"; do
  [[ -f $test_file ]] || die "no such test: $test_file"
  run_test "$test_file"
  case $? in
    0) passed=$((passed + 1)); printf '  PASS\n' ;;
    1) failed=$((failed + 1)); printf '  FAILED\n' ;;
    *) broken=$((broken + 1)); printf '  BROKEN (harness error)\n' ;;
  esac
done

printf '\n%d passed, %d failed, %d broken\n' "$passed" "$failed" "$broken"
((broken > 0)) && exit 2
((failed > 0)) && exit 1
exit 0
