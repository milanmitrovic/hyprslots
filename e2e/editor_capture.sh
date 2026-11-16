# Editor capture and launch (opt-in, like e2e/editor_smoke.sh: run it with
# `make e2e-editor` or `e2e/run.sh e2e/editor_capture.sh`). Needs qs, grim
# and Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# A fresh config (zero slots) and three foot windows arranged by hand:
# workspace 1 on Hyprland's own tiling (no tree yet), notes (class foot)
# two thirds and t-term one third; workspace 2 on Hyprland's scrolling
# layout (Super+L's saved choice), t-scroll. The panel opens on the Layout
# tab's first run; its c asks whom the capture is for, o (only workspace 1)
# previews the windows as they stand (h[foot:2, t-term]) and asks y/n; y
# makes the slots foot and t-term, workspace 1's own tree, each window's
# app assigned there and the windows in their slots, unsaved until Ctrl+S.
# The Assignment page of workspace 2's c captures it in the Layout tab, a
# (all workspaces) makes the shared tree scroll[t-scroll]; Ctrl+S, then a
# Hyprland reload keeps it all. On the Assignment page, m sets workspace 1
# to launch on demand: a line says so and each slot shows what its app
# launches with (from config.lua for foot/notes, t-term's desktop entry);
# with t-term closed, L launches it again (inside the nested Hyprland);
# workspace 2's t-scroll can't launch (no command), in the urgent colour.
# Screenshots go to .e2e-tmp/editor-capture[-<theme>]-*.png
# (SMOKE_THEME=<an Omarchy theme dir> runs it in that theme, as the smoke).
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  smoke_theme_look
  seed_workspace_blocks HEADLESS-2
  # Workspace 2 scrolls: Super+L's choice, saved, which hyprslots leaves alone.
  printf 'o.workspace_mode({ workspace = "2", mode = "scrolling" })\n' >"${E2E_LOADER%/*}/2.lua"
  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return {
  slots = data.slots,
  specs = data.specs,
  desks = data.desks,
  layouts = data.layouts,
  monitor_names = data.monitor_names,
  workspaces = data.workspaces,
  -- foot's notes window launches with a command of the config's own.
  launch_commands = { ["foot/notes"] = "foot --app-id=foot --title=notes sleep 3600" },
}
LUA
  printf 'return {}\n' >"$E2E_CONFIG_HOME/hyprslots/slots.lua"
  # The apps' desktop entries: t-term's alone (no one else's is read).
  export XDG_DATA_HOME=$E2E_DIR/data
  mkdir -p "$XDG_DATA_HOME/applications"
  cat >"$XDG_DATA_HOME/applications/t-term.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=t-term
Exec=foot --app-id=t-term --title=t-term sleep 3600
DESKTOP
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp
SHOT_TAG=${SMOKE_THEME:+-$(basename "$SMOKE_THEME")}

api_state() { repl 'return hyprslots.api.state()'; }
state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }
smoke_tab() { smoke tabs | sed 's/.* | //'; }
tab_is() { [[ $(smoke_tab) == "$1" ]]; }
layout_name() { api_state | jq -r .layout; }
tree_of() { api_state | jq -r --arg l "$(layout_name)" "$1"; }

# A foot window of class $1 titled $2 on the test instance.
spawn_as() {
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY foot --config=/dev/null --app-id="$1" --title="$2" \
    sleep 3600 >>"$E2E_DIR/clients.log" 2>&1 &
  E2E_CLIENT_PIDS+=("$!")
  eventually 10 client_mapped "$1" || harness_fail "client $1 never mapped"
}

shot() {
  local file=$SMOKE_SHOTS/editor-capture$SHOT_TAG-$1.png
  rm -f "$file"
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

test_body() {
  for tool in qs grim wtype; do
    command -v "$tool" >/dev/null || harness_fail "the capture scenario needs $tool"
  done
  local dir=$E2E_CONFIG_HOME/hyprslots watch
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  expect_eq "zero slots" "0" "$(api_state | jq -r '.slots | length')"

  # Workspace 2, scrolling: t-scroll.
  hc dispatch "hl.dsp.focus({ workspace = '2' })" >/dev/null
  spawn_as t-scroll t-scroll
  settle
  # Workspace 1, Hyprland's own tiling: notes two thirds, t-term one third,
  # resized by hand.
  hc dispatch "hl.dsp.focus({ workspace = '1' })" >/dev/null
  spawn_as foot notes
  spawn_as t-term t-term
  settle
  hc dispatch 'hl.dsp.focus({ window = "class:foot" })' >/dev/null
  hc dispatch 'hl.dsp.window.resize({ x = 320, y = 0, relative = true })' >/dev/null
  settle
  expect_client foot 1 0 0 1280 1080
  expect_client t-term 1 1280 0 640 1080
  expect_eq "workspace 2 scrolls" "scrolling" "$(repl 'return hl.get_workspace(2).tiled_layout')"

  start_editor
  watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "open" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  eventually 5 tab_is Layout || true
  expect_eq "zero slots: the Layout tab" "Layout" "$(smoke_tab)"
  if [[ $(smoke empty) == *"[c] Capture my windows | [a] Create your first slot" ]]; then
    pass "the first run offers Capture my windows first"
  else
    fail "empty: $(smoke empty)"
  fi
  sleep 0.5
  shot 1-first-run

  # c: whom it is for; o: workspace 1's own; the preview; y.
  expect_eq "c" "ok" "$(smoke press c)"
  expect_eq "c asks whom the capture of the focused workspace is for" \
    "Capture workspace 1: apply to (a)ll workspaces or (o)nly workspace 1? [Esc] cancel" "$(smoke message)"
  expect_eq "o" "ok" "$(smoke press o)"
  eventually 5 bash -c "[[ -n \$($watch capturePreview) ]]" || true
  expect_eq "the preview: the windows as they stand, 2:1" "1: h[foot:2, t-term]" "$(smoke capturePreview)"
  local said
  said=$(smoke message)
  if [[ $said == "Capture workspace 1 for workspace 1 only: makes slots foot (f) and t-term ("?"), puts 2 windows into their slots. Apply it? (y/n)" ]]; then
    pass "it asks y/n, naming the new slots with their keys: $said"
  else
    fail "preview: $said"
  fi
  expect_eq "on workspace 1" "All workspaces · [1] 2 3 4 5 6 7 8 9" "$(smoke layoutStrip)"
  expect_eq "nothing made yet" "0" "$(api_state | jq -r '.slots | length')"
  if [[ $(smoke help) != *'<font'* ]]; then pass "the help row is the prompt's"; else fail "help: $(smoke help)"; fi
  sleep 0.5
  shot 2-preview
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 state_is '.specs["1"]["t-term"]' t-term; then
    pass "y captured workspace 1"
  else
    fail "not captured: $(api_state | jq -c .specs); $(smoke message); errors: $(smoke errors)"
  fi
  expect_eq "the slots" "foot t-term" "$(api_state | jq -r '[.slots[].name] | sort | join(" ")')"
  expect_eq "workspace 1's own tree" "h[foot:2, t-term]" "$(tree_of '.layouts[$l].workspaces["1"]["1"].tree')"
  expect_eq "no shared tree yet" "null" "$(tree_of '.layouts[$l].default["1"].tree')"
  expect_eq "notes is foot's app on workspace 1" "foot/notes" "$(api_state | jq -r '.specs["1"].foot')"
  expect_eq "the windows in their slots" "foot:foot t-term:t-term" \
    "$(api_state | jq -r '[.windows[] | select(.workspace == 1) | "\(.class):\(.slot)"] | sort | join(" ")')"
  expect_eq "unsaved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  said=$(smoke message)
  if [[ $said == "Captured workspace 1 for workspace 1 only: made slots foot (f) and t-term ("?"); 2 windows are in their slots. Ctrl+S saves." ]]; then
    pass "it says what it made: $said"
  else
    fail "message: $said"
  fi
  if [[ $(smoke header) == *"unsaved"* ]]; then pass "the header says unsaved"; else fail "header: $(smoke header)"; fi
  eventually 5 bash -c "[[ \$($watch layout) == '1: h[foot:2, t-term]' ]]" || true
  expect_eq "the picture shows the tree in force" "1: h[foot:2, t-term]" "$(smoke layout)"
  expect_eq "the preview is gone" "" "$(smoke capturePreview)"
  settle
  expect_client foot 1 0 0 1280 1080
  expect_client t-term 1 1280 0 640 1080
  sleep 0.5
  shot 3-captured
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  if eventually 5 state_is .dirty false; then pass "Ctrl+S saved"; else fail "unsaved after Ctrl+S: $(smoke message)"; fi
  grep -q 't-term' "$dir/slots.lua" || fail "slots.lua lacks t-term: $(cat "$dir/slots.lua")"

  # The Assignment page of workspace 2: c captures it in the Layout tab; a
  # (all workspaces) makes the shared tree.
  expect_eq "Backtab" "ok" "$(smoke press Backtab)"
  eventually 5 tab_is Assignment || fail "not on Assignment: $(smoke tabs)"
  expect_eq "2" "ok" "$(smoke press 2)"
  expect_eq "workspace 2's page" "Workspace 2" "$(smoke assignmentPage)"
  if [[ $(smoke help) == *'">c</font></b>apture'* ]]; then pass "the page's help row offers c capture"; else fail "help: $(smoke help)"; fi
  expect_eq "c" "ok" "$(smoke press c)"
  expect_eq "c goes to the Layout tab" "Layout" "$(smoke_tab)"
  expect_eq "and asks for the page's workspace" \
    "Capture workspace 2: apply to (a)ll workspaces or (o)nly workspace 2? [Esc] cancel" "$(smoke message)"
  expect_eq "a" "ok" "$(smoke press a)"
  eventually 5 bash -c "[[ -n \$($watch capturePreview) ]]" || true
  local scrolled
  scrolled=$(smoke capturePreview)
  if [[ $scrolled == "1: scroll"*"[t-scroll]" ]]; then pass "the preview: a filmstrip of t-scroll: $scrolled"; else fail "preview: $scrolled"; fi
  expect_eq "shown on workspace 2" "All workspaces · 1• [2] 3 4 5 6 7 8 9" "$(smoke layoutStrip)"
  sleep 0.5
  shot 4-preview-scroll
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 state_is '.specs["2"]["t-scroll"]' t-scroll; then
    pass "y captured workspace 2"
  else
    fail "not captured: $(api_state | jq -c .specs); $(smoke message)"
  fi
  local shared
  shared=$(tree_of '.layouts[$l].default["1"].tree')
  if [[ $shared == "scroll"*"[t-scroll]" ]]; then pass "the shared tree: $shared"; else fail "shared tree: $shared"; fi
  expect_eq "workspace 2 has none of its own" "null" "$(tree_of '.layouts[$l].workspaces["2"]')"
  expect_eq "workspace 1 keeps its own" "h[foot:2, t-term]" "$(tree_of '.layouts[$l].workspaces["1"]["1"].tree')"
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  if eventually 5 state_is .dirty false; then pass "Ctrl+S saved"; else fail "unsaved after Ctrl+S: $(smoke message)"; fi

  # A Hyprland reload keeps it all.
  hc reload >/dev/null
  sleep 1
  eventually 10 state_is '.slots | length' 3 || true
  expect_eq "after a reload: the slots" "foot t-scroll t-term" "$(api_state | jq -r '[.slots[].name] | sort | join(" ")')"
  expect_eq "workspace 1's tree" "h[foot:2, t-term]" "$(tree_of '.layouts[$l].workspaces["1"]["1"].tree')"
  shared=$(tree_of '.layouts[$l].default["1"].tree')
  if [[ $shared == "scroll"*"[t-scroll]" ]]; then pass "the shared tree after a reload: $shared"; else fail "shared tree: $shared"; fi
  expect_eq "workspace 1's apps" "foot/notes t-term" "$(api_state | jq -r '[.specs["1"][]] | sort | join(" ")')"
  expect_eq "nothing unsaved" "false" "$(api_state | jq -r .dirty)"
  settle
  expect_client foot 1 0 0 1280 1080
  expect_client t-term 1 1280 0 640 1080

  # Launch: workspace 1's page, never by default; m makes it on demand.
  expect_eq "Backtab" "ok" "$(smoke press Backtab)"
  eventually 5 tab_is Assignment || fail "not on Assignment: $(smoke tabs)"
  expect_eq "1" "ok" "$(smoke press 1)"
  eventually 5 bash -c "[[ \$($watch launch) == 'Launch apps: never' ]]" || true
  expect_eq "workspace 1 launches nothing" "Launch apps: never" "$(smoke launch)"
  if [[ $(smoke help) == *'launch <b><font color="#'*'">m</font></b>ode'*'">L</font></b>aunch missing'* ]]; then
    pass "the help row offers m launch mode and L launch missing"
  else
    fail "help: $(smoke help)"
  fi
  expect_eq "L while never" "ok" "$(smoke press L)"
  expect_eq "L says why not" "Workspace 1 launches no apps: press m to launch them on demand or at login." "$(smoke message)"
  expect_eq "m" "ok" "$(smoke press m)"
  if eventually 5 state_is '.launch["1"]' on_demand; then pass "m: on demand"; else fail "launch: $(api_state | jq -c .launch); $(smoke message)"; fi
  eventually 5 smoke_idle || true
  expect_eq "it says so" "Workspace 1 launches its missing apps when you press L. Ctrl+S saves." "$(smoke message)"
  eventually 5 bash -c "[[ \$($watch launch) == 'Launch apps: on demand |'* ]]" || true
  expect_eq "the line and each slot's command" \
    "Launch apps: on demand | foot: foot --app-id=foot --title=notes sleep 3600 (from your config); t-term: foot --app-id=t-term --title=t-term sleep 3600" \
    "$(smoke launch)"
  sleep 0.5
  shot 5-launch-status

  # t-term closed: L launches it again, inside the nested Hyprland.
  kill "$(hc clients -j | jq -r 'first(.[] | select(.class == "t-term")) | .pid')" 2>/dev/null
  eventually 5 bash -c "! hyprctl -i $E2E_SIG clients -j | jq -e 'any(.[]; .class == \"t-term\")' >/dev/null" ||
    fail "t-term did not close"
  eventually 5 bash -c "[[ \$($watch rows) == *'Missing'* ]]" || true
  expect_eq "L" "ok" "$(smoke press L)"
  eventually 5 bash -c "[[ \$($watch message) == Launched* ]]" || true
  expect_eq "it launched t-term's app" "Launched foot for t-term." "$(smoke message)"
  if eventually 10 client_mapped t-term; then pass "t-term is back"; else fail "t-term never came back"; fi
  settle
  expect_client t-term 1 1280 0 640 1080

  # Workspace 2: on demand, t-scroll has no command: said in the urgent colour.
  expect_eq "2" "ok" "$(smoke press 2)"
  expect_eq "m" "ok" "$(smoke press m)"
  eventually 5 state_is '.launch["2"]' on_demand || fail "launch: $(api_state | jq -c .launch)"
  eventually 5 bash -c "[[ \$($watch launch) == *t-scroll* ]]" || true
  expect_eq "t-scroll can't launch" "Launch apps: on demand | t-scroll: ! can't launch: set a command" "$(smoke launch)"
  sleep 0.5
  shot 6-launch-cannot
  expect_eq "L" "ok" "$(smoke press L)"
  eventually 5 bash -c "[[ \$($watch message) == Nothing* ]]" || true
  expect_eq "nothing to launch: its app is open" "Nothing to launch on workspace 2: its apps are open." "$(smoke message)"
  [[ $(smoke press Ctrl+s) == ok ]] || fail "Ctrl+S"
  eventually 5 state_is .dirty false || fail "unsaved after Ctrl+S"
  grep -q 'on_demand' "$dir/slots.lua" || fail "slots.lua lacks the launch settings: $(cat "$dir/slots.lua")"
  [[ $(smoke press Escape) == ok ]] || fail "Escape"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
