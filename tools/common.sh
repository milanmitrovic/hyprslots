# Sourced by install-engine.sh and uninstall-engine.sh (not run on its own):
# where the plugin and its loader live, and the wait for the engine after a
# Hyprland reload.

ID=io.github.milanmitrovic.hyprslots
plugin=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID
# Omarchy loads every *.lua file in this folder on each config load.
folder=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts
loader=$folder/zz-hyprslots.lua

# How long reload_and_wait asks: ENGINE_WAIT_TRIES times, ENGINE_WAIT_STEP
# seconds apart (5 seconds in all).
ENGINE_WAIT_TRIES=50
ENGINE_WAIT_STEP=0.1

# reload_and_wait <wanted> <lua>: reload Hyprland, then evaluate <lua> in its
# repl until it answers <wanted> or the time is up. Prints the last answer;
# status 0 when it was <wanted>, 1 when not.
reload_and_wait() {
  local wanted=$1 probe=$2 answer='' try
  hyprctl reload >/dev/null
  for ((try = 1; try <= ENGINE_WAIT_TRIES; try++)); do
    answer=$(hyprctl repl "$probe" 2>&1) || true
    [[ $answer == "$wanted" ]] && break
    ((try < ENGINE_WAIT_TRIES)) && sleep "$ENGINE_WAIT_STEP"
  done
  printf '%s\n' "$answer"
  [[ $answer == "$wanted" ]]
}
