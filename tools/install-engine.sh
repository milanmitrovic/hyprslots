#!/usr/bin/env bash
# Enable the hyprslots engine: put its loader (loader.lua, next to this
# script) into Omarchy's workspace-layouts folder as zz-hyprslots.lua, reload
# Hyprland and check that the engine runs. Omarchy loads every file in that
# folder on each config load; nothing in your Hyprland config is edited.
# The editor's "Enable" button runs this script. Undo: uninstall-engine.sh.
#
#   install-engine.sh              install, reload Hyprland, check
#   install-engine.sh --no-reload  install only (it loads at the next reload)
#
# Exit status: 0 the engine runs (or Hyprland is not running here), 1 not.

set -euo pipefail

ID=io.github.milanmitrovic.hyprslots
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID
folder=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts
loader=$folder/zz-hyprslots.lua

reload=1
case ${1:-} in
  '') ;;
  --no-reload) reload=0 ;;
  -h | --help)
    sed -n '2,12s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "install-engine.sh: unknown option $1 (see --help)" >&2
    exit 2
    ;;
esac

# The loader runs the engine from the plugin folder, so without the plugin
# there it would run nothing (and remove itself).
if [[ ! -f $plugin/lua/hyprslots/init.lua ]]; then
  echo "install-engine.sh: the hyprslots plugin is not installed ($plugin has no engine)." >&2
  echo "Add it first: omarchy plugin add https://github.com/milanmitrovic/hyprslots --enable" >&2
  exit 1
fi

# Written beside it and renamed into place, so a config load never reads half
# a file (Omarchy loads only *.lua files from the folder).
mkdir -p "$folder"
tmp=$(mktemp "$folder/.zz-hyprslots.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cp "$here/loader.lua" "$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$loader"
trap - EXIT
echo "Installed the hyprslots loader: $loader"

if ((!reload)); then
  echo "It loads the engine at the next Hyprland config load (hyprctl reload)."
  exit 0
fi
if ! hyprctl version >/dev/null 2>&1; then
  echo "Hyprland is not running here: the engine starts with it."
  exit 0
fi

hyprctl reload >/dev/null
engine() { hyprctl repl 'if hyprslots then return "running" end return "absent " .. tostring(hyprslots_load_error)' 2>&1; }
state=''
for _ in $(seq 50); do
  state=$(engine)
  [[ $state == running ]] && break
  sleep 0.1
done
if [[ $state == running ]]; then
  echo "Reloaded Hyprland: the hyprslots engine is running."
  exit 0
fi
echo "install-engine.sh: the loader is in place, but the engine did not start: ${state#absent }" >&2
exit 1
