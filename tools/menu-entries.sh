#!/usr/bin/env bash
# hyprslots in the Omarchy menu (Trigger): "hyprslots: Open editor",
# "hyprslots: Capture this workspace" and "hyprslots: Launch missing apps".
# Omarchy builds its menu from its own file and one of yours,
# ~/.config/omarchy/extensions/omarchy-menu.jsonc; this adds the entries to
# yours between two marker lines and takes out only those lines again, the
# rest of the file staying as you wrote it. The shell watches the file, so
# the menu changes at once. The engine's Enable (install-engine.sh --menu)
# runs it; uninstall-engine.sh, and the loader once the plugin is removed,
# take the entries out. The entries hide themselves while the plugin is gone.
#
#   menu-entries.sh install   add (or renew) the entries
#   menu-entries.sh remove    take them out
#   menu-entries.sh status    print "installed" or "missing"

set -euo pipefail

ID=io.github.milanmitrovic.hyprslots
file=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/extensions/omarchy-menu.jsonc
begin="  // >>> hyprslots ($ID): tools/menu-entries.sh remove takes this out"
end='  // <<< hyprslots'

# The entries. Their plugin folder is read when the menu shows them, so they
# go wherever the plugin is.
block() {
  local plugin='${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/'$ID
  local when='[ -d \"'$plugin'\" ]'
  printf '%s\n' "$begin"
  printf '  "trigger.hyprslots-editor": {"icon":"󰕰","label":"hyprslots: Open editor","description":"Your slots, the layout of your screens and which app goes where","when":"%s","action":"omarchy-shell shell summon %s"},\n' "$when" "$ID"
  printf '  "trigger.hyprslots-capture": {"icon":"󰄀","label":"hyprslots: Capture this workspace","description":"Turn the windows on screen into slots and a layout","when":"%s","action":"omarchy-shell shell summon %s '"'"'{\\"capture\\":true}'"'"'"},\n' "$when" "$ID"
  printf '  "trigger.hyprslots-launch": {"icon":"󰐊","label":"hyprslots: Launch missing apps","description":"Open the apps this workspace'"'"'s empty slots wait for","when":"%s","action":"\\"%s/tools/hyprslots\\" launch-missing"},\n' "$when" "$plugin"
  printf '%s\n' "$end"
}

# The file without the entries.
strip() {
  awk '/^[[:space:]]*\/\/ >>> hyprslots/ { skip = 1; next }
       skip && /^[[:space:]]*\/\/ <<< hyprslots/ { skip = 0; next }
       !skip' "$1"
}

# A plain file of the user's, or none: never one through a symlink.
check() {
  if [[ -L $file || (-e $file && ! -f $file) ]]; then
    echo "menu-entries.sh: refusing to edit $file: not a plain file" >&2
    exit 1
  fi
}

# Write stdin to the file, renamed into place.
put() {
  mkdir -p "${file%/*}"
  local tmp
  tmp=$(mktemp "${file%/*}/.omarchy-menu.XXXXXX")
  cat >"$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$file"
}

case ${1:-} in
  install)
    check
    base=$(if [[ -f $file ]]; then strip "$file"; else printf '{\n}\n'; fi)
    if ! grep -q '^[[:space:]]*}[[:space:]]*$' <<<"$base"; then
      echo "menu-entries.sh: $file has no closing } on a line of its own; add the entries by hand" >&2
      exit 1
    fi
    # Before the last closing brace, the entry before ours given a comma.
    BLOCK=$(block) awk '
      { lines[NR] = $0 }
      END {
        close_at = 0
        for (i = NR; i > 0; i--) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { close_at = i; break }
        for (i = close_at - 1; i > 0; i--) {
          if (lines[i] ~ /^[[:space:]]*$/ || lines[i] ~ /^[[:space:]]*\/\//) continue
          if (lines[i] !~ /[,{][[:space:]]*$/) sub(/[[:space:]]*$/, ",", lines[i])
          break
        }
        for (i = 1; i <= NR; i++) {
          if (i == close_at) print ENVIRON["BLOCK"]
          print lines[i]
        }
      }' <<<"$base" | put
    echo "Added hyprslots to the Omarchy menu (Trigger): Open editor, Capture this workspace, Launch missing apps."
    ;;
  remove)
    check
    if [[ -f $file ]] && grep -q '^[[:space:]]*// >>> hyprslots' "$file"; then
      strip "$file" | put
      echo "Took hyprslots out of the Omarchy menu."
    fi
    ;;
  status)
    if [[ -f $file ]] && grep -q '^[[:space:]]*// >>> hyprslots' "$file"; then echo installed; else echo missing; fi
    ;;
  -h | --help) sed -n '2,15s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" ;;
  *)
    echo "usage: menu-entries.sh install|remove|status" >&2
    exit 2
    ;;
esac
