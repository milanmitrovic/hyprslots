# shellcheck shell=bash
# Helpers for the editor scenarios (e2e/editor_smoke.sh,
# e2e/editor_multimon.sh), sourced after e2e/lib.sh: the plugin runs in
# Quickshell on the TEST instance (e2e/editor/shell.qml), never in the live
# shell, and is driven through its `smoke` IPC target.

SMOKE_QS_DIR='' SMOKE_QS_PID=''

# qs ipc against the smoke's own Quickshell instance (by pid: the instance
# lives in the harness's private XDG_RUNTIME_DIR).
smoke() { qs ipc --pid "$SMOKE_QS_PID" call smoke "$@" 2>&1; }

smoke_ready() { [[ $(smoke ready) == yes ]]; }
smoke_idle() { [[ $(smoke busy) == no ]]; }

# SMOKE_THEME's own Hyprland look goes into the nested Hyprland as Omarchy
# sources it: its corner rounding is the shell's Style.cornerRadius, which
# the panel's corners follow (solitude rounds them, most themes do not).
# Call from test_setup, after writing test-extra.lua.
smoke_theme_look() {
  if [[ -n ${SMOKE_THEME:-} && -f $SMOKE_THEME/hyprland.lua ]]; then
    printf 'dofile("%s/hyprland.lua")\n' "$SMOKE_THEME" >>"$E2E_CONFIG_HOME/hypr/test-extra.lua"
  fi
}

start_editor() {
  local omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
  SMOKE_QS_DIR=$E2E_DIR/qs
  mkdir -p "$SMOKE_QS_DIR"
  cp "$E2E_ROOT/e2e/editor/shell.qml" "$SMOKE_QS_DIR/shell.qml"
  ln -s "$E2E_ROOT/editor" "$SMOKE_QS_DIR/editor"
  # qs.Commons / qs.Ui resolve against the config root, as in the shell.
  ln -s "$omarchy/shell/Commons" "$SMOKE_QS_DIR/Commons"
  ln -s "$omarchy/shell/Ui" "$SMOKE_QS_DIR/Ui"

  # SMOKE_THEME=<an Omarchy theme directory> (say
  # /usr/share/omarchy/themes/catppuccin-latte) runs the panel in that theme,
  # to check it in a light one: qs.Commons reads the theme in force from
  # $HOME/.local/state/omarchy/current/theme, so qs gets a home of its own.
  local home=$HOME
  if [[ -n ${SMOKE_THEME:-} ]]; then
    home=$E2E_DIR/home
    mkdir -p "$home/.local/state/omarchy/current" "$home/.config"
    ln -s "$SMOKE_THEME" "$home/.local/state/omarchy/current/theme"
    if [[ -d $HOME/.config/fontconfig ]]; then ln -s "$HOME/.config/fontconfig" "$home/.config/fontconfig"; fi
    log "theme: $SMOKE_THEME"
  fi

  HOME=$home WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG QT_QPA_PLATFORM=wayland \
    OMARCHY_PATH=$omarchy qs --no-color -p "$SMOKE_QS_DIR" >"$E2E_DIR/qs.log" 2>&1 &
  SMOKE_QS_PID=$!
  E2E_CLIENT_PIDS+=("$SMOKE_QS_PID")
  eventually 15 qs ipc --pid "$SMOKE_QS_PID" show ||
    harness_fail "Quickshell never answered ipc (alive: $(kill -0 "$SMOKE_QS_PID" 2>/dev/null && echo yes || echo no)); see $E2E_DIR/qs.log"
}

