#!/usr/bin/env bash
# Disable the hyprslots engine: remove its loader (zz-hyprslots.lua) from
# Omarchy's workspace-layouts folder and reload Hyprland, which then runs
# without hyprslots (Omarchy's own Super+1..9 and resize keys come back).
# Your hyprslots config (~/.config/hyprslots) is kept. Undo: install-engine.sh.
#
#   uninstall-engine.sh              remove, reload Hyprland, check
#   uninstall-engine.sh --no-reload  remove only (it is gone at the next reload)
#
# Exit status: 0 the engine is gone (or Hyprland is not running here), 1 not.

set -euo pipefail

folder=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts
loader=$folder/zz-hyprslots.lua

reload=1
case ${1:-} in
  '') ;;
  --no-reload) reload=0 ;;
  -h | --help)
    sed -n '2,11s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "uninstall-engine.sh: unknown option $1 (see --help)" >&2
    exit 2
    ;;
esac

if [[ -e $loader ]]; then
  rm -f "$loader"
  echo "Removed the hyprslots loader: $loader"
else
  echo "The hyprslots loader is not installed ($loader)."
fi

((reload)) || exit 0
if ! hyprctl version >/dev/null 2>&1; then
  echo "Hyprland is not running here."
  exit 0
fi

hyprctl reload >/dev/null
engine() { hyprctl repl 'return hyprslots and "running" or "absent"' 2>&1; }
state=''
for _ in $(seq 50); do
  state=$(engine)
  [[ $state == absent ]] && break
  sleep 0.1
done
if [[ $state == absent ]]; then
  echo "Reloaded Hyprland: the hyprslots engine is off."
  exit 0
fi
echo "uninstall-engine.sh: the loader is gone, but Hyprland still runs hyprslots ($state)." >&2
exit 1
