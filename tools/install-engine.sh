#!/usr/bin/env bash
# Enable the hyprslots engine: put its loader (loader.lua, next to this
# script) into Omarchy's workspace-layouts folder as zz-hyprslots.lua, reload
# Hyprland and check that the engine runs. Omarchy loads every file in that
# folder on each config load; nothing in your Hyprland config is edited.
# The editor's "Enable" button runs this script. Undo: uninstall-engine.sh.
#
#   install-engine.sh              install, reload Hyprland, check
#   install-engine.sh --no-reload  install only (it loads at the next reload)
#   --keys     also bind Super+Ctrl+Y (open the editor) and Super+Ctrl+Shift+C
#              (capture this workspace) through the loader, each only where
#              it is free (Hyprland running); --no-keys: none
#   --menu     also add hyprslots to the Omarchy menu (menu-entries.sh
#              install); --no-menu: take it out
# Without --keys / --no-keys the keys an installed loader binds stay.
#
# Exit status: 0 the engine runs (or Hyprland is not running here), 1 not.

set -euo pipefail

ID=io.github.milanmitrovic.hyprslots
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$ID
folder=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts
loader=$folder/zz-hyprslots.lua

reload=1 keys=keep menu=keep
for arg in "$@"; do
  case $arg in
    --no-reload) reload=0 ;;
    --keys) keys=on ;;
    --no-keys) keys=off ;;
    --menu) menu=on ;;
    --no-menu) menu=off ;;
    -h | --help)
      sed -n '2,19s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "install-engine.sh: unknown option $arg (see --help)" >&2
      exit 2
      ;;
  esac
done

# The loader runs the engine from the plugin folder, so without the plugin
# there it would run nothing (and remove itself).
if [[ ! -f $plugin/lua/hyprslots/init.lua ]]; then
  echo "install-engine.sh: the hyprslots plugin is not installed ($plugin has no engine)." >&2
  echo "Add it first: omarchy plugin add https://github.com/milanmitrovic/hyprslots --enable" >&2
  exit 1
fi

# The loader's KEYS line: the editor's keys it binds. --keys binds each key
# no other bind has (hyprctl binds; a bind of the loader's own, described
# "Hyprslots: ...", is no other); --no-keys none; else the installed
# loader's line stays.
EMPTY_KEYS='local KEYS = {}'
keys_line=$EMPTY_KEYS
if [[ $keys == keep && -f $loader ]]; then
  keys_line=$(grep -m1 '^local KEYS = ' "$loader" || printf '%s' "$EMPTY_KEYS")
elif [[ $keys == on ]]; then
  if binds=$(hyprctl binds -j 2>/dev/null) && [[ -n $binds ]]; then
    entries=()
    # name, modmask (Super 64 + Ctrl 4 [+ Shift 1]), key, Hyprland's spelling, what it does
    while IFS='|' read -r name mask key combo label; do
      taken=$(jq -r --argjson m "$mask" --arg k "$key" \
        'first(.[] | select(.modmask == $m and (.key | ascii_downcase) == $k
          and ((.description // "") | startswith("Hyprslots:") | not)) | (.description // .arg // "")) // empty' \
        <<<"$binds")
      pretty=$(sed -e 's/SUPER/Super/; s/CTRL/Ctrl/; s/SHIFT/Shift/; s/ + /+/g' <<<"$combo")
      if [[ -n $taken ]] || jq -e --argjson m "$mask" --arg k "$key" \
        'any(.[]; .modmask == $m and (.key | ascii_downcase) == $k and ((.description // "") | startswith("Hyprslots:") | not))' \
        <<<"$binds" >/dev/null; then
        echo "$pretty is bound already${taken:+ ($taken)}: left as it is."
      else
        entries+=("$name = \"$combo\"")
        echo "$pretty: $label."
      fi
    done <<'KEYS'
editor|68|y|SUPER + CTRL + Y|open the editor
capture|69|c|SUPER + CTRL + SHIFT + C|capture this workspace
KEYS
    if ((${#entries[@]} > 0)); then
      keys_line="local KEYS = { $(IFS=','; printf '%s' "${entries[*]}" | sed 's/,/, /g') }"
    fi
  else
    echo "Hyprland is not running here, so no key was checked or bound."
  fi
fi

# Written beside it and renamed into place, so a config load never reads half
# a file (Omarchy loads only *.lua files from the folder).
mkdir -p "$folder"
tmp=$(mktemp "$folder/.zz-hyprslots.XXXXXX")
trap 'rm -f "$tmp"' EXIT
awk -v line="$keys_line" -v empty="$EMPTY_KEYS" '$0 == empty { print line; next } { print }' \
  "$here/loader.lua" >"$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$loader"
trap - EXIT
echo "Installed the hyprslots loader: $loader"

case $menu in
  on) "$here/menu-entries.sh" install ;;
  off) "$here/menu-entries.sh" remove ;;
esac

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
