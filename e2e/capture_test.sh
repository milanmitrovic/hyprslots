# Capture: windows arranged by hand turned into slots, trees and specs in one
# edit (api capture, docs/design.md §9), from a first run (no config at all,
# zero slots).
#
# Screen: HEADLESS-2, 1920x1080 at 0,0, Omarchy block 0 (workspace N = id N).
# Workspace 2 is Hyprland's dwindle: three foot windows, alpha on the left,
# beta over gamma on the right, alpha widened by hand to two thirds.
# Workspace 4 scrolls (a saved Omarchy mode, so hyprslots leaves it be):
# two foot windows, delta then epsilon, columns half the screen.
#
# Capturing workspace 2 for all workspaces makes slots foot, foot-2 and
# foot-3 (h[foot:2, v[foot-2, foot-3]], the shared tree) with each window's
# spec (foot/alpha, ...) on workspace 2; capturing workspace 4 for itself
# reuses foot and foot-2, which it leaves empty, as a half-width scroll
# branch of its own. Saved, a Hyprland config reload brings back the same
# slots, trees and assignments, and the windows where they were.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.config({ scrolling = { column_width = 0.5 } })
LUA
  seed_workspace_blocks HEADLESS-2
  # Workspace 4's saved mode, as Super+L leaves it (hyprslots leaves it be).
  printf 'hl.workspace_rule({ workspace = "4", layout = "scrolling" }) -- mode = "scrolling"\n' \
    >"$E2E_STATE_HOME/omarchy/workspace-layouts/4.lua"
  rm -rf "$E2E_CONFIG_HOME/hyprslots"
}

api() {
  local args=${2:-'{}'}
  args=${args//\\/\\\\}
  args=${args//\"/\\\"}
  repl "return hyprslots.api.call(\"$1\", \"$args\")"
}

state() { api state; }

# A foot window of class foot titled $1 on the focused workspace.
spawn_titled() {
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY foot --config=/dev/null --app-id=foot --title="$1" \
    sleep 3600 >>"$E2E_DIR/clients.log" 2>&1 &
  E2E_CLIENT_PIDS+=("$!")
  eventually 10 titled_mapped "$1" || harness_fail "window $1 never mapped"
}

titled_mapped() { hc clients -j | jq -e --arg t "$1" 'any(.[]; .title == $t and .mapped)' >/dev/null; }

address_of() { hc clients -j | jq -r --arg t "$1" 'first(.[] | select(.title == $t)) | .address'; }

# "<workspace> <x> <y> <w> <h>" of the window titled $1.
geometry() { hc clients -j | jq -r --arg t "$1" 'first(.[] | select(.title == $t)) | "\(.workspace.id) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"'; }

# "<workspace> <x> <w>": where a window sits across the screen.
across() { geometry "$1" | awk '{ print $1, $2, $4 }'; }

show() { hc dispatch "hl.dsp.focus({ workspace = '$1' })" >/dev/null; }

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  eventually 5 bash -c "[[ \$(hyprctl -i $E2E_SIG repl 'return hyprslots.api.state()' | jq -r .desk) != null ]]" \
    || fail "no desk was made for the monitor"
  expect_eq "a first run: no slots" 0 "$(state | jq '.slots | length')"

  # Workspace 2, arranged by hand.
  show 2
  spawn_titled alpha
  spawn_titled beta
  hc dispatch "hl.dsp.focus({ window = 'address:$(address_of beta)' })" >/dev/null
  spawn_titled gamma
  settle
  hc dispatch "hl.dsp.window.resize({ x = 320, y = 0, relative = true, window = 'address:$(address_of alpha)' })" >/dev/null
  settle
  log "workspace 2 by hand: alpha $(geometry alpha), beta $(geometry beta), gamma $(geometry gamma)"
  expect_eq "alpha takes two thirds" "2 0 1280" "$(across alpha)"

  # Workspace 4, scrolling.
  show 4
  spawn_titled delta
  spawn_titled epsilon
  settle
  expect_eq "workspace 4 scrolls" scrolling "$(hc workspaces -j | jq -r '.[] | select(.id == 4) | .tiledLayout')"

  # Workspace 2's preview, then for all workspaces.
  local reply
  reply=$(api capture '{"workspace": 2}')
  log "preview: $(jq -c '{new_slots, trees, applied}' <<<"$reply")"
  expect_eq "the preview names the slots it would make" "foot f, foot-2 o, foot-3 t" \
    "$(jq -r '[.new_slots[] | "\(.slot) \(.key)"] | join(", ")' <<<"$reply")"
  expect_eq "and the tree" "h[foot:2, v[foot-2, foot-3]]" "$(jq -r '.trees["1"].tree' <<<"$reply")"
  expect_eq "changing nothing" 0 "$(state | jq '.slots | length')"
  reply=$(api capture '{"workspace": 2, "scope": "all", "apply": true}')
  expect_eq "workspace 2 captured" true "$(jq -r .applied <<<"$reply")"
  local s
  s=$(state)
  expect_eq "the shared tree" "h[foot:2, v[foot-2, foot-3]]" "$(jq -r --arg l "$(jq -r .layout <<<"$s")" '.layouts[$l].default["1"].tree' <<<"$s")"
  expect_eq "workspace 2's specs" "foot=foot/alpha foot-2=foot/beta foot-3=foot/gamma" \
    "$(jq -r '.specs["2"] | to_entries | sort_by(.key) | map("\(.key)=\(.value)") | join(" ")' <<<"$s")"
  expect_eq "each window in its slot" "foot foot-2 foot-3" \
    "$(for t in alpha beta gamma; do jq -r --arg a "$(address_of "$t")" '.assignments[$a].slot' <<<"$s"; done | paste -sd ' ')"
  expect_eq "an unsaved edit" true "$(jq -r .dirty <<<"$s")"
  settle
  expect_eq "alpha keeps its place" "2 0 1280" "$(across alpha)"

  # Workspace 4, for itself: foot and foot-2 are free there.
  reply=$(api capture '{"workspace": 4, "scope": "workspace", "apply": true}')
  log "workspace 4: $(jq -c '{new_slots, trees, applied, error}' <<<"$reply")"
  s=$(state)
  local layout
  layout=$(jq -r .layout <<<"$s")
  expect_eq "workspace 4's own tree" "scroll:0.5[foot, foot-2, foot-3]" \
    "$(jq -r --arg l "$layout" '.layouts[$l].workspaces["4"]["1"].tree' <<<"$s")"
  expect_eq "no slot made for it" "foot foot-2 foot-3" "$(jq -r '[.slots[].name] | join(" ")' <<<"$s")"
  expect_eq "workspace 4's specs" "foot=foot/delta foot-2=foot/epsilon" \
    "$(jq -r '.specs["4"] | to_entries | sort_by(.key) | map("\(.key)=\(.value)") | join(" ")' <<<"$s")"

  # Saved, and Hyprland's config reloaded.
  expect_eq "saved" true "$(api save | jq -r .ok)"
  hc reload >/dev/null
  eventually 5 bash -c "[[ \$(hyprctl -i $E2E_SIG repl 'return hyprslots and hyprslots.api.state()' | jq -r .ok) == true ]]"
  settle
  s=$(state)
  expect_eq "after a reload, clean" false "$(jq -r .dirty <<<"$s")"
  expect_eq "the shared tree" "h[foot:2, v[foot-2, foot-3]]" "$(jq -r --arg l "$layout" '.layouts[$l].default["1"].tree' <<<"$s")"
  expect_eq "workspace 4's tree" "scroll:0.5[foot, foot-2, foot-3]" \
    "$(jq -r --arg l "$layout" '.layouts[$l].workspaces["4"]["1"].tree' <<<"$s")"
  expect_eq "the windows in their slots again" "2/foot 2/foot-2 2/foot-3 4/foot 4/foot-2" \
    "$(for t in alpha beta gamma delta epsilon; do jq -r --arg a "$(address_of "$t")" '"\(.assignments[$a].workspace)/\(.assignments[$a].slot)"' <<<"$s"; done | paste -sd ' ')"
  expect_eq "alpha where it was" "2 0 1280" "$(across alpha)"
  expect_eq "no config errors" "" "$(hc configerrors -j | jq -r '.[] | select(. != "")')"
}
