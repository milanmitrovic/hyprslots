# Editor smoke (opt-in: not a *_test.sh, so `make e2e` skips it; run it with
# `make e2e-editor` or `e2e/run.sh e2e/editor_smoke.sh`). Needs qs
# (Quickshell), grim, and Omarchy's shell modules under $OMARCHY_PATH/shell.
#
# The editor plugin (editor/) runs in Quickshell on the TEST instance, never
# in the live shell: e2e/editor/shell.qml loads the plugin's Engine.qml and
# Panel.qml standalone, with WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE
# of the nested Hyprland and the harness's private XDG_RUNTIME_DIR. The panel
# opens with its header naming the desk and the layout it shares, and a help
# row whose trigger keys are highlighted. A stray window is put into a slot
# with real key presses (wtype, through the panel's keyboard handling), which
# also makes its spec workspace 3's for that slot; u takes it out again with
# that spec (the slot is left empty), and u on a Missing row clears that
# slot's spec, through the panel's press() hook; api state must show each;
# [ ] and the digits page by workspace. Then the Layout tab (one pane per
# screen, titled with the monitor there; its header one strip, its help one
# line, no a, x or f) flips workspace 3's tree, takes a typed ratio, applies
# it (api state and the windows' geometry must follow) and saves it (the
# editor's data must hold it); t cycles tiles, scroll half and scroll full,
# drawn as a filmstrip (r refused on a scroll tree), w applies the scroll
# tree and d reverts it to the saved one; it opens on All workspaces (the
# layout's shared trees, first in the strip, a dot on each workspace with its
# own); ] and 3 switch its workspace, - edits the shared trees (a workspace
# with none of its own then shows them); on such a workspace the first edit
# asks: a applies it to all workspaces, o gives the workspace its own tree,
# which u drops again; its slot list (s) edits the global slots (a refused then
# a good rename, the trees and specs following; a new slot, which every tree
# gets at once and an edited draft follows; Return selects it in the
# picture; delete; describe). The shared layout's warning points to the Desk
# tab, which forks it, applies a layout to the active desk and one to a desk
# row, refuses one of another screen count, renames a desk and a layout, and a
# save must write all of it; then it deletes a used layout moving its desk to
# another, is refused deleting one no other can replace, deletes a desk (no p:
# pinned screens are gone) and makes a new layout. Then the bar widget on a
# stand-in bar strip: its label (the active layout's name), the unsaved dot,
# its menu (Save, Re-apply, Record), left clicks toggling the panel, and the
# error state while the hyprslots global is gone. Last, workspace 8 lists
# every global slot (every tree has them all), and a puts a window into left
# with no question of placing it, which Ctrl+S saves.
# Screenshots of the nested compositor go to .e2e-tmp/editor-smoke-*.png.
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0 (workspace N = workspace id N).
# config.lua sets workspaces = 9: hyprslots manages workspaces 1 to 9.
# Desk solo (HEADLESS-2) uses layout solo, which desk beamer (a projector not
# connected) shares; its shared tree is main (every global slot appended:
# h[main, right, side]); workspace 3: h[main:2, v[right, side]]; t-side never
# opens. Desk away (HEADLESS-2 and a Dell not connected) uses the 2-screen
# layout dual; layout spare is unused.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts, workspaces = 9 }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { main = {}, right = {}, side = {} },
  specs = {
    [3] = { main = "t-main", right = "t-right", side = "t-side" },
  },
  desks = {
    solo = { monitors = { "HEADLESS-2" }, layout = "solo" },
    beamer = { monitors = { "Epson Beamer X1" }, layout = "solo" },
    away = { monitors = { "HEADLESS-2", "Dell U2723QE ABC" }, layout = "dual" },
  },
  layouts = {
    solo = { screens = 1, default = { [1] = "main" }, workspaces = { [3] = { [1] = "h[main:2, v[right, side]]" } } },
    dual = { screens = 2, default = { [1] = "main" } },
    spare = { screens = 1, default = { [1] = "h[main, right]" } },
  },
}
LUA
}

SMOKE_QS_DIR='' SMOKE_QS_PID='' SMOKE_WTYPE_PID=''
SMOKE_SHOTS=$E2E_ROOT/.e2e-tmp

# qs ipc against the smoke's own Quickshell instance (by pid: the instance
# lives in the harness's private XDG_RUNTIME_DIR).
smoke() { qs ipc --pid "$SMOKE_QS_PID" call smoke "$@" 2>&1; }

smoke_ready() { [[ $(smoke ready) == yes ]]; }
smoke_idle() { [[ $(smoke busy) == no ]]; }

# The test instance's api state, as JSON.
api_state() { repl 'return hyprslots.api.state()'; }

address_of() { hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .address'; }

assignment_of() {
  api_state | jq -cS --arg a "$1" '.assignments[$a] // null'
}

assigned_to_side() { [[ $(assignment_of "$1") == '{"slot":"side","workspace":3}' ]]; }
# Workspace 3's tree in force on screen 1 of the active layout, and whether all is saved.
tree_in_force() { api_state | jq -r '.layouts[.layout].workspaces["3"]["1"].tree'; }
tree_in_force_is() { [[ $(tree_in_force) == "$1" ]]; }
saved() { [[ $(api_state | jq -r .dirty) == false ]]; }

unassigned() { api_state | jq -e --arg a "$1" '(.assignments[$a] == null) and (.unassigned | index($a) != null)' >/dev/null; }

# Real key presses into the nested compositor (the panel holds the keyboard).
# Each wtype is a new virtual keyboard: the first key of the first one is
# lost while its keymap lands, and a second wtype's keys were not delivered
# at all, so the whole sequence is one wtype, started with a key the panel
# ignores (F13), run in the background while the smoke watches the panel.
keys_in_background() {
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY wtype -d 60 -k F13 -s 300 "$@" >>"$E2E_DIR/wtype.log" 2>&1 &
  SMOKE_WTYPE_PID=$!
  E2E_CLIENT_PIDS+=("$SMOKE_WTYPE_PID")
}

shot() {
  local file=$SMOKE_SHOTS/editor-smoke-$1.png
  rm -f "$file"
  if WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HEADLESS-2 "$file" 2>>"$E2E_DIR/grim.log"; then
    log "screenshot: $file"
  else
    fail "grim could not take $file (see $E2E_DIR/grim.log)"
  fi
}

# Milliseconds one repl round trip takes.
time_ms() {
  local start end
  start=$(date +%s%N)
  "$@" >/dev/null
  end=$(date +%s%N)
  printf '%d' $(((end - start) / 1000000))
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

# Type text into the panel, one press() per character.
press_text() {
  local text=$1 i
  for ((i = 0; i < ${#text}; i++)); do
    [[ $(smoke press "${text:i:1}") == ok ]] || fail "press '${text:i:1}' was ignored"
  done
}

press_keys() {
  local k
  for k in "$@"; do
    [[ $(smoke press "$k") == ok ]] || fail "press $k was ignored"
  done
}

state_is() { [[ $(api_state | jq -r "$1") == "$2" ]]; }

# The panel's header line without its unsaved-edits marker.
header() { smoke header | sed 's/   ● unsaved edits (Ctrl+S)$//'; }

slot_names() { api_state | jq -r '[.slots[].name] | join(" ")'; }

# Whether every tree of every layout (shared and workspaces' own) has slot $1.
in_every_tree() {
  api_state | jq -e --arg s "$1" '[.layouts[] | (.default // {}), (.workspaces // {} | .[]) | .[] | .slots | index($s) != null] | all' >/dev/null
}
in_no_tree() {
  api_state | jq -e --arg s "$1" '[.layouts[] | (.default // {}), (.workspaces // {} | .[]) | .[] | .slots | index($s) == null] | all' >/dev/null
}

# The Layout tab's slot list (s): the global slots, name and description
# only. A rename to a taken name is refused in its prompt, then right
# becomes aside (every tree and workspace 3's spec follow); a makes notes,
# which every tree gets at once (no question of placing it), and the edited
# draft follows; Return on it selects it in the picture; d asks naming what a
# slot goes from, deletes notes; e describes main. Layout spare's default
# trees follow the rename too.
layout_slots() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "three tabs, no Slots tab" "Assignment Layout Desk | Layout" "$(smoke tabs)"
  expect_eq "the global slots" "main right side" "$(slot_names)"
  expect_eq "s moves the keys to the slot list" "ok" "$(smoke press s)"
  expect_eq "by name, the first selected" "slots main" "$(smoke selection)"
  expect_eq "the slot list's help is one line" "1" "$(smoke helpLines)"
  sleep 0.3
  shot 9-layout-slots
  press_keys Down r
  expect_eq "r prompts for the new name" \
    "Rename 'right' to (every tree and workspace follows) [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text main
  press_keys Return
  eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == *\"there is a slot 'main' already\"* ]]" ||
    fail "the taken name was not refused in its prompt: $(smoke message)"
  log "refusal: $(smoke message)"
  sleep 0.3
  shot 10-layout-slots-refused
  press_keys Backspace Backspace Backspace Backspace
  press_text aside
  press_keys Return
  if eventually 5 state_is '.specs["3"].aside' t-right; then
    pass "r renamed right to aside, workspace 3's spec along"
  else
    fail "right was not renamed: $(api_state | jq -c '{slots, specs}'); $(smoke message); errors: $(smoke errors)"
  fi
  expect_eq "the global slots" "aside main side" "$(slot_names)"
  expect_eq "the tree is rewritten" "h[main:2, v[aside, side:3]]" "$(tree_in_force)"
  expect_eq "and another layout's default trees" "h[main, aside, side]" "$(api_state | jq -r '.layouts.spare.default["1"].tree')"
  eventually 5 bash -c "[[ \$($watch layout) == '1: h[main:2, v[aside, side:3]]' ]]" || true
  expect_eq "and so is the picture" "1: h[main:2, v[aside, side:3]]" "$(smoke layout)"
  expect_eq "the edit is unsaved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  log "message: $(smoke message)"

  # An edited draft (/ flips it), then a makes notes (name, description):
  # every tree has it at once, the draft follows, nothing asks where it goes.
  press_keys Escape /
  expect_eq "an edited draft" "1: v[main:2, h[aside, side:3]] *" "$(smoke layout)"
  press_keys s a
  expect_eq "a asks for the name, saying every tree gets it" \
    "New slot name (every tree gets it; an empty slot takes no room) [Enter] next  [Esc] cancel: ▏" "$(smoke message)"
  press_text notes
  press_keys Return
  press_text scratch
  press_keys Return
  if eventually 5 state_is '.slots[] | select(.name == "notes") | .description' scratch; then
    pass "a added the global slot notes with its description"
  else
    fail "notes was not added: $(api_state | jq -c .slots); $(smoke message)"
  fi
  if eventually 5 in_every_tree notes; then
    pass "every tree of every layout has notes"
  else
    fail "trees without notes: $(api_state | jq -c '[.layouts | to_entries[] | {l: .key, d: .value.default, w: .value.workspaces}]')"
  fi
  eventually 5 smoke_idle || true
  expect_eq "it says so, and asks nothing" "Added slot 'notes' to every tree. Ctrl+S saves." "$(smoke message)"
  expect_eq "the tree in force has notes" "h[main:2, v[aside, side:3], notes]" "$(tree_in_force)"
  eventually 5 bash -c "[[ \$($watch layout) == *notes* ]]" || true
  expect_eq "the edited draft follows" "1: v[main:2, h[aside, side:3], notes] *" "$(smoke layout)"
  sleep 0.3
  shot 11-layout-new-slot

  # Return on notes selects it in the picture; / flips the draft back.
  press_keys Return
  expect_eq "Return on a slot selects it in the picture" "1 notes" "$(smoke selection)"
  expect_eq "and says where" "notes is on screen 1: hjkl move it." "$(smoke message)"
  press_keys /
  expect_eq "/ flips the draft back to the tree in force" "1: h[main:2, v[aside, side:3], notes]" "$(smoke layout)"

  # d on side names the trees it goes from (n keeps it); d on notes deletes it
  # from every tree.
  press_keys s Up Up Up Up Down Down Down d
  if [[ $(smoke message) == "Delete slot 'side'? It goes from the trees "*"solo/3/1"*" (y/n)" ]]; then
    pass "d names what side goes from: $(smoke message)"
  else
    fail "d on side: $(smoke message)"
  fi
  press_keys n
  press_keys Up d
  if [[ $(smoke message) == "Delete slot 'notes'? It goes from the trees "*"(y/n)" ]]; then
    pass "d on notes names the trees: $(smoke message)"
  else
    fail "d on notes: $(smoke message)"
  fi
  press_keys y
  if eventually 5 state_is '.slots | length' 3; then
    pass "d, y deleted notes"
  else
    fail "notes is still there: $(slot_names); $(smoke message)"
  fi
  if eventually 5 in_no_tree notes; then
    pass "and no tree has it"
  else
    fail "trees: $(api_state | jq -c '.layouts')"
  fi
  eventually 5 smoke_idle || true
  expect_eq "the picture loses it" "1: h[main:2, v[aside, side:3]]" "$(smoke layout)"
  press_keys Up Up Up Up Down e
  expect_eq "e describes main" "Description for 'main' (empty removes it) [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text "the editor"
  press_keys Return
  if eventually 5 state_is '.slots[] | select(.name == "main") | .description' "the editor"; then
    pass "e described main"
  else
    fail "main's description: $(api_state | jq -c '.slots'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  sleep 0.3
  shot 12-layout-slots-edited
  expect_eq "Escape goes back to the picture" "ok" "$(smoke press Escape)"
  expect_eq "the panel stays open" "yes" "$(smoke ready)"
  if [[ $(smoke selection) == "1 "* ]]; then
    pass "the picture's keys again: $(smoke selection)"
  else
    fail "selection: $(smoke selection)"
  fi
}

# On workspace 4, which uses the shared tree, the first edit asks whom it
# is for: a (all workspaces) edits the shared tree, so w changes it for every
# workspace without its own. On workspace 5, o (only workspace 5) makes w give
# it its own tree (dotted in the strip), here a scroll half one; u, y drops it
# again.
layout_scope() {
  press_keys /
  expect_eq "/ first asks whom the edit is for" "Apply to (a)ll workspaces or (o)nly workspace 4? [Esc] cancel" "$(smoke message)"
  press_keys a
  expect_eq "the flip in the draft" "1: h[main, right, side] *" "$(smoke layout)"
  if [[ $(smoke layoutHeader) == *"(uses the shared tree: editing it for all workspaces)"* ]]; then
    pass "the header says the edit is the shared tree's: $(smoke layoutHeader)"
  else
    fail "header: $(smoke layoutHeader)"
  fi
  press_keys w
  if eventually 5 state_is '.layouts.solo.default["1"].tree' 'h[main, right, side]'; then
    pass "/, a, then w, applied the shared tree"
  else
    fail "solo's shared trees: $(api_state | jq -c '.layouts.solo.default'): $(smoke message)"
  fi
  expect_eq "workspace 4 still has no trees of its own" "[3]" "$(api_state | jq -c '.layouts.solo.own')"
  expect_eq "workspace 6 shows the new shared tree" "h[main, right, side]" \
    "$(api_state | jq -r '.layouts.solo.workspaces["6"]["1"].tree')"
  eventually 5 smoke_idle || true
  press_keys 5
  expect_eq "workspace 5 shows the shared tree" "1: h[main, right, side]" "$(smoke layout)"
  press_keys t
  expect_eq "t asks again on another workspace" "Apply to (a)ll workspaces or (o)nly workspace 5? [Esc] cancel" "$(smoke message)"
  press_keys o
  expect_eq "o: workspace 5's draft scrolls, half-width columns" "1: scroll:0.5[main, right, side] *" "$(smoke layout)"
  press_keys w
  if eventually 5 state_is '.layouts.solo.own | tostring' '[3,5]'; then
    pass "o, then w, gave workspace 5 its own tree"
  else
    fail "own: $(api_state | jq -c '.layouts.solo.own'): $(smoke message)"
  fi
  expect_eq "its tree" "scroll:0.5[main, right, side]" "$(api_state | jq -r '.layouts.solo.workspaces["5"]["1"].tree')"
  expect_eq "the shared tree is untouched" "h[main, right, side]" "$(api_state | jq -r '.layouts.solo.default["1"].tree')"
  eventually 5 smoke_idle || true
  expect_eq "the strip dots workspace 5" "All workspaces · 1 2 3• 4 [5•] 6 7 8 9" "$(smoke layoutStrip)"
  sleep 0.3
  shot 8g-layout-own-tree
  press_keys u
  expect_eq "u asks first" "Drop workspace 5's own trees and use the shared tree? (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.layouts.solo.own | tostring' '[3]'; then
    pass "u, y dropped workspace 5's own tree"
  else
    fail "own: $(api_state | jq -c '.layouts.solo.own'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "it shows the shared tree again" "1: h[main, right, side]" "$(smoke layout)"
  expect_eq "and says so" "Workspace 5 uses the shared tree of solo again. Ctrl+S saves." "$(smoke message)"
  expect_eq "no dot on 5" "All workspaces · 1 2 3• 4 [5] 6 7 8 9" "$(smoke layoutStrip)"
}

# Layout solo is shared with desk beamer: the Layout tab warns that an edit
# changes it there too and sends a fork to the Desk tab; f is no key here.
layout_shared() {
  expect_eq "the header says beamer shares the layout" "Desk: solo · Layout: solo (also used by: beamer)" "$(header)"
  expect_eq "the warning points to the Desk tab" \
    "Shared with desk beamer: edits here change it there too — fork it in the Desk tab." "$(smoke sharedNote)"
  local before
  before=$(smoke layout)
  expect_eq "f is no key of the Layout tab" "ignored" "$(smoke press f)"
  expect_eq "nothing forked" "solo" "$(api_state | jq -r .layout)"
  expect_eq "a is no key of the picture" "ignored" "$(smoke press a)"
  expect_eq "x is no key of the picture" "ignored" "$(smoke press x)"
  expect_eq "no tree changed" "$before" "$(smoke layout)"
}

# The Desk tab, saved at the end: f forks the desk's layout (the Layout
# tab's warning sends forks here), a applies a layout to the active desk (on a
# layout row) and to a desk (on its row, picked), a refuses a layout of
# another screen count, r renames a desk and a layout; no p.
desks_layouts() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "Tab to Desk" "ok" "$(smoke press Tab)"
  expect_eq "it opens on the active desk" "desk:solo" "$(smoke selection)"
  local help
  help=$(smoke help)
  if [[ $help == *'">a</font></b>pply a layout'* && $help == *'">f</font></b>ork its layout'* && $help != *pin* ]]; then
    pass "the help row highlights each key in its label, no pinning"
  else
    fail "help row: $help"
  fi
  expect_eq "p is no key" "ignored" "$(smoke press p)"
  if [[ $(smoke deskColumns) != *Pinned* ]]; then
    pass "no Pinned column: $(smoke deskColumns)"
  else
    fail "columns: $(smoke deskColumns)"
  fi
  sleep 0.3
  shot 14-desks-layouts

  # f on the desk row forks its layout (solo), suggesting solo-2; the drafts
  # of the Layout tab carry over to the copy.
  press_keys f
  expect_eq "f on a desk forks its layout" "Fork layout 'solo' as [Enter] fork  [Esc] cancel: solo-2▏" "$(smoke message)"
  press_keys Return
  if eventually 5 state_is .layout solo-2; then
    pass "f forked solo as solo-2 for desk solo"
  else
    fail "the active layout is $(api_state | jq -r .layout): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "desk solo points at the copy" "solo-2" "$(api_state | jq -r '.desks.solo.layout')"
  expect_eq "beamer keeps solo" "solo" "$(api_state | jq -r '.desks.beamer.layout')"
  expect_eq "the reply says so" "Forked 'solo' as 'solo-2'; desk 'solo' uses it now. Ctrl+S saves." "$(smoke message)"
  expect_eq "the header follows" "Desk: solo · Layout: solo-2" "$(header)"
  expect_eq "the copy is selected" "layout:solo-2" "$(smoke selection)"

  # a on a layout row applies it to the active desk.
  press_keys Down
  expect_eq "Down selects spare" "layout:spare" "$(smoke selection)"
  press_keys a
  if eventually 5 state_is .layout spare; then
    pass "a applied spare to the active desk"
  else
    fail "the active layout is $(api_state | jq -r .layout): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "it says so" "Desk 'solo' uses layout 'spare' now. Ctrl+S saves." "$(smoke message)"

  # a on a desk row picks among the layouts with its screen count.
  press_keys Up Up Up Up
  expect_eq "Up x4 selects desk solo" "desk:solo" "$(smoke selection)"
  press_keys a
  expect_eq "a offers the 1-screen layouts" \
    "Layout for desk 'solo': (s)olo, (1) solo-2, (2) spare (in use)? [Esc] cancel   → solo" "$(smoke message)"
  press_keys 1
  if eventually 5 state_is .layout solo-2; then
    pass "a, 1 put desk solo on solo-2"
  else
    fail "the active layout is $(api_state | jq -r .layout): $(smoke message)"
  fi
  eventually 5 smoke_idle || true

  # a on a layout of another screen count is refused.
  press_keys Down a
  expect_eq "dual has 2 screens" "Layout 'dual' has 2 screens; desk 'solo' has 1 monitor." "$(smoke message)"
  expect_eq "nothing changed" "solo-2" "$(api_state | jq -r .layout)"

  # r renames desk beamer and layout spare.
  press_keys Up Up r
  expect_eq "r on a desk" "Rename desk 'beamer' to [Enter] save  [Esc] cancel: ▏" "$(smoke message)"
  press_text projector
  press_keys Return
  if eventually 5 state_is '.desks.projector.layout' solo; then
    pass "r renamed desk beamer to projector"
  else
    fail "desks: $(api_state | jq -c '.desks | keys'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "the selection follows" "desk:projector" "$(smoke selection)"
  press_keys Down Down Down Down Down
  expect_eq "Down x5 selects spare" "layout:spare" "$(smoke selection)"
  press_keys r
  press_text extra
  press_keys Return
  if eventually 5 state_is '.layouts.extra.screens' 1; then
    pass "r renamed layout spare to extra"
  else
    fail "layouts: $(api_state | jq -c '.layouts | keys'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "spare is gone" "null" "$(api_state | jq -r '.layouts.spare')"
  sleep 0.3
  shot 15-desks-layouts-edited
}

save_and_check() {
  local file=$E2E_CONFIG_HOME/hyprslots/slots.lua
  expect_eq "w does nothing here" "ignored" "$(smoke press w)"
  press_keys Ctrl+s
  if eventually 5 state_is .dirty false; then
    pass "Ctrl+S saved"
  else
    fail "still unsaved: $(smoke message)"
  fi
  local saved
  saved=$(cat "$file")
  for want in 'aside = {},' 'description = "the editor",' 'aside = "t-right",' 'main = "t-main",' \
    '"h[main:2, v[aside, side:3]]"' '["solo-2"] = {' 'extra = {' 'projector = {' \
    'layout = "solo-2"' '"h[main, aside, side]"'; do
    if grep -qF "$want" <<<"$saved"; then
      pass "slots.lua holds $want"
    else
      fail "slots.lua lacks $want:"$'\n'"$saved"
    fi
  done
  for unwanted in 'spare = {' 'beamer = {' 'pinned' 'notes'; do
    if grep -qF "$unwanted" <<<"$saved"; then
      fail "slots.lua still holds $unwanted:"$'\n'"$saved"
    else
      pass "slots.lua does not hold $unwanted"
    fi
  done
}

# More of the Desk tab, unsaved: x on layout solo (desk projector
# uses it) moves projector to solo-2 first; x on dual (desk away uses it, no
# other 2-screen layout) is refused by the engine; x deletes desk away; n
# makes the layout wide.
SMOKE_REFUSAL=''
desks_layouts_edits() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  press_keys Down
  expect_eq "Down selects solo" "layout:solo" "$(smoke selection)"
  press_keys x
  expect_eq "x on a used layout asks where its desk goes" \
    "Layout 'solo' is used by desk projector: move it to: (e)xtra, (s)olo-2? [Esc] cancel   → extra" \
    "$(smoke message)"
  press_keys s
  if eventually 5 state_is '.layouts.solo' null; then
    pass "x, s deleted solo"
  else
    fail "solo is still there: $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "projector uses solo-2 now" "solo-2" "$(api_state | jq -r '.desks.projector.layout')"
  expect_eq "the header names the desk sharing it" "Desk: solo · Layout: solo-2 (also used by: projector)" "$(header)"
  expect_eq "the selection falls back to the active desk" "desk:solo" "$(smoke selection)"

  press_keys Down
  expect_eq "Down selects dual" "layout:dual" "$(smoke selection)"
  press_keys x
  expect_eq "x on dual asks" "Delete layout 'dual'? Desk away uses it. (y/n)" "$(smoke message)"
  press_keys y
  eventually 5 bash -c "[[ -n \$($watch message) ]]" || true
  eventually 5 smoke_idle || true
  SMOKE_REFUSAL=$(smoke message)
  if [[ $(api_state | jq -r '.layouts.dual.screens') == 2 && -n $SMOKE_REFUSAL ]]; then
    pass "the engine refused deleting dual while away uses it: $SMOKE_REFUSAL"
  else
    fail "dual: $(api_state | jq -c '.layouts.dual'): $SMOKE_REFUSAL"
  fi
  sleep 0.3
  shot 16-desks-layouts-refused

  press_keys Up Up Up
  expect_eq "Up x3 selects desk away" "desk:away" "$(smoke selection)"
  press_keys x
  expect_eq "x on a desk asks" "Delete desk 'away'? Its layout 'dual' stays. (y/n)" "$(smoke message)"
  press_keys y
  if eventually 5 state_is '.desks.away' null; then
    pass "x, y deleted desk away"
  else
    fail "away is still there: $(smoke message)"
  fi
  eventually 5 smoke_idle || true

  expect_eq "the selection is the active desk" "desk:solo" "$(smoke selection)"

  # n makes a layout: a name, a screen count (the desk's suggested; 0 is
  # refused in place), then the default trees or none.
  press_keys n
  expect_eq "n asks for a name" "Name the new layout [Enter] next  [Esc] cancel: ▏" "$(smoke message)"
  press_text wide
  press_keys Return
  expect_eq "then the screen count, the desk's suggested" "Screens of 'wide' [Enter] next  [Esc] cancel: 1▏" "$(smoke message)"
  press_keys BackSpace 0 Return
  expect_eq "0 screens is refused in its prompt" \
    "Screens of 'wide' [Enter] next  [Esc] cancel: 0▏ | The screen count is a whole number from 1." "$(smoke message)"
  press_keys BackSpace 2 Return
  expect_eq "then how it starts" "Start 'wide': (d)efault trees, (e)mpty? [Esc] cancel   → default trees" "$(smoke message)"
  press_keys d
  if eventually 5 state_is '.layouts.wide.screens' 2; then
    pass "n made the 2-screen layout wide"
  else
    fail "layouts: $(api_state | jq -c '.layouts | keys'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "selected" "layout:wide" "$(smoke selection)"
  expect_eq "with the default trees" "true" "$(api_state | jq '.layouts.wide.default | length > 0')"
  expect_eq "no desk uses it" "0" "$(api_state | jq '.layouts.wide.used_by | length')"
  log "message: $(smoke message)"
  expect_eq "unsaved" "true" "$(api_state | jq -r .dirty)"
}

# The bar widget (the plugin's bar-widget entry point) on the smoke's
# stand-in bar: its label follows the engine's state through the shared
# service (no poller of its own), a dot while edits are unsaved; a left
# click opens and closes the panel; the right-click menu's Save saves and
# Re-apply lays the workspace out again; with the hyprslots global gone the
# widget turns red and says why, and comes back with it.
bar_widget() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  expect_eq "the widget loads" "ok" "$(smoke bar)"
  eventually 5 bash -c "[[ \$($watch barLabel) == 'dirty 󰕰 solo-2 •' ]]" || true
  expect_eq "it shows the active layout, a dot for the unsaved edits" \
    "dirty 󰕰 solo-2 •" "$(smoke barLabel)"
  expect_eq "its tooltip says so, and names the layout and the desk sharing it" \
    $'Hyprslots: desk solo, workspace 3 · unsaved edits\nLayout: solo-2 (also used by: projector)\nClick: editor · Right-click: menu' \
    "$(smoke barTooltip)"
  sleep 0.3
  shot 19-bar-widget

  expect_eq "right click" "ok" "$(smoke barClick right)"
  expect_eq "opens the menu, Save on with unsaved edits" "open: arrange on, record on, save on, reload on" \
    "$(smoke barMenu)"
  sleep 0.5
  shot 20-bar-menu
  expect_eq "Save" "ok" "$(smoke barChoose save)"
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'normal 󰕰 solo-2' ]]"; then
    pass "the menu's Save saved: the dot is gone"
  else
    fail "after Save the widget shows $(smoke barLabel); dirty $(api_state | jq -r .dirty)"
  fi
  expect_eq "the menu closed" "closed: arrange on, record on, save off, reload on" "$(smoke barMenu)"
  eventually 5 bash -c "[[ \$($watch barRun) == *Saved* ]]" || true
  expect_eq "and the outcome is a notification" \
    "notify-send -a Hyprslots Hyprslots 'Saved.'" "$(smoke barRun)"
  eventually 5 smoke_idle || true

  expect_eq "Re-apply layout" "ok" "$(smoke barChoose arrange)"
  if eventually 5 bash -c "[[ \$($watch barRun) == *'Workspace 3 laid out again.'* ]]"; then
    pass "Re-apply ran workspace 3, then arrange"
  else
    fail "Re-apply: $(smoke barRun); errors: $(smoke errors)"
  fi
  eventually 5 smoke_idle || true

  expect_eq "the panel is closed" "no" "$(smoke ready)"
  expect_eq "left click" "ok" "$(smoke barClick left)"
  if eventually 5 smoke_ready; then
    pass "a left click opened the panel"
  else
    fail "the panel did not open: $(smoke errors)"
  fi
  sleep 0.5
  shot 21-bar-panel
  expect_eq "left click again" "ok" "$(smoke barClick left)"
  expect_eq "closed it" "no" "$(smoke ready)"

  # Record opens the panel on the Layout tab's record flow (R): the preview
  # asks before applying anything; n keeps the tree.
  expect_eq "Record workspace" "ok" "$(smoke barChoose record)"
  if eventually 5 bash -c "[[ \$($watch message) == Recorded*'Apply it?'* ]]"; then
    pass "Record opened the panel on the record preview"
  else
    fail "Record: ready $(smoke ready), message $(smoke message)"
  fi
  log "record: $(smoke message)"
  sleep 0.3
  shot 22-bar-record
  press_keys n Escape
  expect_eq "nothing applied" "false" "$(api_state | jq -r .dirty)"
  expect_eq "the panel closed" "no" "$(smoke ready)"

  # hyprslots not loaded: the next state read fails, the widget turns red.
  repl 'hyprslots_smoke = hyprslots; hyprslots = nil; return "gone"' >/dev/null
  repl 'hl.dispatch(hl.dsp.event("hyprslots changed 900")); return "ok"' >/dev/null
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'error '* ]]"; then
    pass "with hyprslots gone the widget is an error"
  else
    fail "the widget shows $(smoke barLabel)"
  fi
  local tooltip
  tooltip=$(smoke barTooltip)
  if [[ $tooltip == "Hyprslots: "*"attempt to index a nil value (global 'hyprslots')"* ]]; then
    pass "its tooltip names the error"
  else
    fail "tooltip: $tooltip"
  fi
  expect_eq "only Reload is offered" "closed: arrange off, record off, save off, reload on" "$(smoke barMenu)"
  sleep 0.3
  shot 23-bar-error
  repl 'hyprslots = hyprslots_smoke; hyprslots_smoke = nil; return "back"' >/dev/null
  repl 'hl.dispatch(hl.dsp.event("hyprslots changed 901")); return "ok"' >/dev/null
  if eventually 5 bash -c "[[ \$($watch barLabel) == 'normal 󰕰 solo-2' ]]"; then
    pass "with hyprslots back the widget is too"
  else
    fail "the widget shows $(smoke barLabel)"
  fi
}

# Workspace 8: its tree is set to scroll[main, aside] and only main has a
# spec; the engine gives every tree every global slot, so left (added after)
# is in it too. The Assignment page lists them all in tree order: main
# Missing, the others empty. a on a window there, l, puts it in left: it
# assigns, nothing more (no question of placing, the tree as it was); Ctrl+S
# writes the spec.
assignment_assign() {
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke" layout tree
  layout=$(api_state | jq -r .layout)
  log "set_tree: $(repl 'return hyprslots.api.call("set_tree", "{\"workspace\": 8, \"screen\": 1, \"tree\": \"scroll[main, aside]\"}")')"
  repl 'return hyprslots.api.call("add_slot", "{\"slot\": \"left\"}")' >/dev/null
  log "set_spec: $(repl 'return hyprslots.api.call("set_spec", "{\"workspace\": 8, \"slot\": \"main\", \"spec\": \"[Research]\"}")')"
  repl 'return hyprslots.api.call("workspace", "{\"workspace\": 8}")' >/dev/null
  spawn_and_wait t-left
  settle
  local left
  left=$(address_of t-left)
  tree=$(api_state | jq -r --arg l "$layout" '.layouts[$l].workspaces["8"]["1"].tree')
  log "workspace 8's tree: $tree"
  if [[ $tree == "scroll[main, "*left* ]]; then
    pass "workspace 8's tree has every global slot, left too: $tree"
  else
    fail "workspace 8's tree: $tree"
  fi

  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  local i
  for ((i = 0; i < 3; i++)); do
    [[ $(smoke tabs) == *"| Assignment" ]] && break
    press_keys Tab
  done
  press_keys 8
  local rows want_slots
  rows=$(smoke rows)
  log "workspace 8 rows: $rows"
  if [[ $rows == "main|[Research]|Missing — waiting for it to open; "* && $rows == *"; left|—|—"* ]]; then
    pass "workspace 8 lists main Missing [Research] first, left empty among the others"
  else
    fail "rows: $rows"
  fi
  want_slots=$(api_state | jq -r '.slots | length')
  expect_eq "every global slot is a row" "$want_slots" "$(grep -o '|—|\|Missing' <<<"$rows" | wc -l | tr -d ' ')"
  sleep 0.3
  shot 24-assignment-workspace-8

  local n
  for ((n = 0; n < 12; n++)); do
    [[ $(smoke selection) == "none - t-left" ]] && break
    press_keys Down
  done
  expect_eq "the t-left window selected" "none - t-left" "$(smoke selection)"
  press_keys a
  if [[ $(smoke message) == "Assign t-left to a slot on workspace 8: (m)ain, "*"(l)eft"* ]]; then
    pass "a offers workspace 8's slots, the tree's order: $(smoke message)"
  else
    fail "a prompt: $(smoke message)"
  fi
  press_keys l
  if eventually 5 bash -c "[[ \$(qs ipc --pid $SMOKE_QS_PID call smoke message) == Assigned* ]]"; then
    pass "a, l assigned"
  else
    fail "message: $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "t-left is in left" '{"slot":"left","workspace":8}' "$(assignment_of "$left")"
  expect_eq "the message says only that" "Assigned t-left to left on workspace 8. Ctrl+S saves." "$(smoke message)"
  expect_eq "the tree is as it was" "$tree" "$(api_state | jq -r --arg l "$layout" '.layouts[$l].workspaces["8"]["1"].tree')"
  expect_eq "the spec is workspace 8's" "t-left" "$(api_state | jq -r '.specs["8"].left')"
  sleep 0.3
  shot 25-assignment-assigned
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  if eventually 5 saved; then
    pass "Ctrl+S saved"
  else
    fail "still dirty after Ctrl+S: $(smoke message) $(smoke errors)"
  fi
  if grep -qF 'left = "t-left"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "the editor's data holds workspace 8's spec for left"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi
  expect_eq "Escape" "ok" "$(smoke press Escape)"
}

test_body() {
  for tool in qs grim wtype; do
    command -v "$tool" >/dev/null || harness_fail "the editor smoke needs $tool"
  done
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"

  # Given t-main and t-right in their slots on workspace 3 and a stray window there.
  spawn_and_wait t-main
  spawn_and_wait t-right
  log "workspace 3 -> $(repl 'return hyprslots.api.call("workspace", "{\"workspace\": 3}")')"
  spawn_and_wait t-stray
  settle
  local stray
  stray=$(address_of t-stray)
  expect_eq "the stray has no slot" "null" "$(assignment_of "$stray")"
  log "state read takes $(time_ms api_state) ms (budget 250 ms inside Hyprland)"

  # When the editor opens on the test instance.
  start_editor
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.5 # let the overlay reveal itself (it waits for the output's scale)
  shot 1-open
  expect_eq "the header names the desk, its layout and the desk sharing it" \
    "Desk: solo · Layout: solo (also used by: beamer)" "$(header)"
  local help
  help=$(smoke help)
  if [[ $help == *'<b><font color="#'*'">a</font></b>ssign  '* && $help == *'">u</font></b>nassign  '* && $help != *spec* \
    && $help == *'">Ctrl+S</font></b> save'* && $help == *'">q</font></b> close'* ]]; then
    pass "the help row highlights each trigger key in the accent colour"
  else
    fail "help row: $help"
  fi

  # Then `a` on the stray puts it into slot side and makes its spec workspace 3's
  # for side, as real key presses: Down x3 (main, right, the side
  # placeholder, stray), a, then s for side.
  expect_eq "the panel opens on workspace 3, main selected" "slot main t-main" "$(smoke selection)"
  keys_in_background -k Down -k Down -k Down -s 1000 -k a -s 1500 -k s
  local watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  eventually 5 bash -c "[[ \$($watch selection) == 'none - t-stray' ]]"
  expect_eq "Down x3 selects the stray" "none - t-stray" "$(smoke selection)"
  eventually 3 bash -c "[[ \$($watch message) == 'Assign t-stray to a slot on workspace 3'* ]]" || fail "a opened no prompt: $(smoke message)"
  expect_eq "a prompts with the global slots on workspace 3" \
    "Assign t-stray to a slot on workspace 3: (m)ain, (r)ight, (s)ide? [Esc] cancel   → main" "$(smoke message)"
  wait "$SMOKE_WTYPE_PID" 2>/dev/null
  if eventually 5 assigned_to_side "$stray"; then
    pass "keys a, s put the stray in side"
  else
    fail "the stray is not in side: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  expect_eq "and made its spec workspace 3's for side" "t-stray" "$(api_state | jq -r '.specs["3"].side')"
  expect_eq "in memory until saved" "true" "$(api_state | jq -r .dirty)"
  eventually 5 smoke_idle || true
  settle
  sleep 0.3
  shot 2-assigned
  expect_client t-stray 3 1280 540 640 540
  expect_eq "the row says so" "slot side t-stray" "$(smoke selection)"
  log "message: $(smoke message)"

  # And u, y (through the panel's press() hook) takes it out again, the
  # spec a took from it with it: side is left empty, not Missing t-stray.
  expect_eq "u" "ok" "$(smoke press u)"
  expect_eq "u asks, saying the slot is left empty" \
    "Unassign t-stray from side on workspace 3? The slot is left empty. (y/n)" "$(smoke message)"
  expect_eq "y" "ok" "$(smoke press y)"
  if eventually 5 unassigned "$stray"; then
    pass "u, y unassigned the stray"
  else
    fail "the stray is still assigned: $(assignment_of "$stray"); editor errors: $(smoke errors)"
  fi
  if eventually 5 state_is '.specs["3"].side' null; then
    pass "and cleared workspace 3's spec for side"
  else
    fail "side's spec is $(api_state | jq -r '.specs["3"].side'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  press_keys Up
  expect_eq "side's row is empty: no spec, nothing Missing" "empty side -" "$(smoke selection)"
  expect_eq "side stays a slot" "main right side" "$(slot_names)"
  sleep 0.3
  shot 3-unassigned

  # u on a Missing row (a spec whose window is not open) clears that spec;
  # side waits for t-side again (set through the api), u, y clears it. c is
  # no key any more.
  repl 'return hyprslots.api.call("set_spec", "{\"workspace\": 3, \"slot\": \"side\", \"spec\": \"t-side\"}")' >/dev/null
  eventually 5 bash -c "[[ \$($watch selection) == 'missing side t-side' ]]" || true
  expect_eq "side is Missing t-side" "missing side t-side" "$(smoke selection)"
  expect_eq "c is no key" "ignored" "$(smoke press c)"
  if [[ $(smoke help) == *'">u</font></b>nassign  '* ]]; then
    pass "the help row's u is unassign on a Missing row too"
  else
    fail "help row: $(smoke help)"
  fi
  press_keys u
  expect_eq "u on a Missing row asks first" "Unassign t-side from side on workspace 3? It is not open; the slot is left empty. (y/n)" \
    "$(smoke message)"
  sleep 0.3
  shot 3b-unassign-missing
  press_keys y
  if eventually 5 state_is '.specs["3"].side' null; then
    pass "u, y cleared workspace 3's spec for side"
  else
    fail "side's spec is $(api_state | jq -r '.specs["3"].side'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "it says so" "Unassigned t-side from side on workspace 3: the slot is empty. Ctrl+S saves." "$(smoke message)"
  expect_eq "side's row is empty again" "empty side -" "$(smoke selection)"

  # [ pages back to workspace 2 (no every-window page), 7 has a page too,
  # 3 jumps back to workspace 3's page.
  press_keys [
  expect_eq "[ pages to workspace 2" "Workspace 2" "$(smoke assignmentPage)"
  press_keys 7
  expect_eq "7 jumps to workspace 7's page" "Workspace 7" "$(smoke assignmentPage)"
  press_keys 3
  expect_eq "3 jumps to workspace 3's page" "slot main t-main" "$(smoke selection)"
  # workspaces = 9 in config.lua: 0 is no key, the help says 1–9.
  expect_eq "the engine manages nine workspaces" "9" "$(api_state | jq -r .workspace_count)"
  expect_eq "0 is no key" "ignored" "$(smoke press 0)"
  if [[ $(smoke help) == *'">1–9</font></b> jump'* ]]; then
    pass "the help's jump keys are 1–9"
  else
    fail "help row: $(smoke help)"
  fi

  # The Layout tab edits workspace 3's tree as a draft: / flips it, r takes a
  # typed ratio, w applies, Ctrl+S saves (s is no key of the view any more).
  expect_eq "Tab" "ok" "$(smoke press Tab)"
  sleep 0.3
  shot 4-layout-tab
  # It opens on All workspaces, the shared trees (main, every global slot
  # appended); the header is one strip, a dot marking workspace 3, the one
  # with trees of its own.
  expect_eq "the Layout view opens on All workspaces, its header one strip" \
    "[All workspaces] · 1 2 3• 4 5 6 7 8 9" "$(smoke layoutHeader)"
  expect_eq "the shared tree has every global slot" "1: h[main, right, side]" "$(smoke layout)"
  expect_eq "3" "ok" "$(smoke press 3)"
  expect_eq "3 edits workspace 3, which has its own tree" "Editing workspace 3 of solo." "$(smoke message)"
  expect_eq "the strip follows" "All workspaces · 1 2 [3•] 4 5 6 7 8 9" "$(smoke layoutStrip)"
  expect_eq "on screen 1, main selected" "1 main" "$(smoke selection)"
  expect_eq "its draft is the tree in force" "1: h[main:2, v[right, side]]" "$(smoke layout)"
  local title
  title=$(smoke panes)
  if [[ $title == "Screen 1 · HEADLESS-2"* && $title != *" | "* ]]; then
    pass "one pane, titled with the monitor at screen 1: $title"
  else
    fail "pane titles: $title"
  fi
  help=$(smoke help)
  if [[ $help == *'">[ ] 1–9 -</font></b> workspace'* && $help == *'">u</font></b>se shared'* &&
    $help == *'">r</font></b>atios'* && $help == *'">d</font></b> revert'* && $help == *'">t</font></b> scroll half'* &&
    $help != *'>f</font></b>ork'* && $help != *dd* && $help != *'take out'* && $help != *.lua* ]]; then
    pass "the Layout help row: workspace keys, u (workspace 3 has its own tree), r, d revert, t; no a, x or f"
  else
    fail "help row: $help"
  fi
  expect_eq "the help row is one line" "1" "$(smoke helpLines)"
  expect_eq "/" "ok" "$(smoke press /)"
  expect_eq "/ flips every split, in the draft" "1: v[main:2, h[right, side]] *" "$(smoke layout)"
  expect_eq "r" "ok" "$(smoke press r)"
  expect_eq "r prompts with the current ratio" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: ▏" "$(smoke message)"
  # A ratio the grammar refuses opens the prompt again, the entry kept.
  press_text 2:1:1
  press_keys Return
  expect_eq "a refused ratio reopens its prompt with the refusal" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: 2:1:1▏ | expected 2 values for the outer container, got 3" \
    "$(smoke message)"
  press_keys Backspace Backspace
  local c ratio_entry='[1:3]'
  for ((i = 0; i < ${#ratio_entry}; i++)); do
    c=${ratio_entry:i:1}
    [[ $(smoke press "$c") == ok ]] || fail "typing $c into the ratio prompt"
  done
  expect_eq "the prompt shows what was typed" \
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: 2:1[1:3]▏" "$(smoke message)"
  expect_eq "Return" "ok" "$(smoke press Return)"
  expect_eq "the ratio lands in the draft" "1: v[main:2, h[right, side:3]] *" "$(smoke layout)"
  expect_eq "nothing is applied yet" "h[main:2, v[right, side]]" "$(tree_in_force)"
  sleep 0.3
  shot 5-layout-draft

  expect_eq "w" "ok" "$(smoke press w)"
  if eventually 5 tree_in_force_is 'v[main:2, h[right, side:3]]'; then
    pass "w applied the draft (set_trees)"
  else
    fail "the tree in force is $(tree_in_force); editor: $(smoke message) $(smoke errors)"
  fi
  expect_eq "applied, not saved" "true" "$(api_state | jq -r '.dirty')"
  eventually 5 smoke_idle || true
  settle
  # h[v[main:2, h[right, side:3]]:3, *:1] with side absent: the tree takes
  # 1440 px, the overflow column (the unassigned stray) 480.
  expect_client t-main 3 0 0 1440 720
  expect_client t-right 3 0 720 1440 360
  expect_client t-stray 3 1440 0 480 1080
  expect_eq "the draft is clean again" "1: v[main:2, h[right, side:3]]" "$(smoke layout)"
  sleep 0.3
  shot 6-layout-applied

  expect_eq "S does not save" "ignored" "$(smoke press S)"
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  if eventually 5 saved; then
    pass "Ctrl+S saved"
  else
    fail "still dirty after Ctrl+S: $(smoke message) $(smoke errors)"
  fi
  if grep -qF '[1] = "v[main:2, h[right, side:3]]"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "slots.lua holds the edited tree"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi
  if grep -qE 'side = "t-' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    fail "slots.lua still has a spec for side: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  else
    pass "slots.lua has no spec for side after u"
  fi
  log "message: $(smoke message)"
  sleep 0.3
  shot 7-layout-saved

  # o shows where other windows (windows assigned to no slot) go, the column
  # at the right the engine gives them, selected; it changes no tree, and o
  # hides it again.
  smoke press o >/dev/null
  expect_eq "o shows other windows' place, selected" "1 *" "$(smoke selection)"
  expect_eq "o changes no tree" "1: v[main:2, h[right, side:3]]" "$(smoke layout)"
  sleep 0.3
  shot 7b-layout-other-windows
  smoke press o >/dev/null
  expect_eq "o hides it again, a slot selected" "1 main" "$(smoke selection)"
  expect_eq "still no tree changed" "1: v[main:2, h[right, side:3]]" "$(smoke layout)"

  # t cycles the tree: tiles, scroll half, scroll full, back to tiles. A
  # scroll tree is drawn as a filmstrip (its columns half or full screen
  # width in slot order, the screen a viewport over them); l moves right a
  # column on; r is refused on it before any prompt. w applies the scroll
  # tree, and d, y reverts it to the saved one (api reset).
  sleep 0.3
  shot 8a-layout-tiles
  smoke press Down >/dev/null
  expect_eq "Down selects right" "1 right" "$(smoke selection)"
  smoke press t >/dev/null
  expect_eq "t makes the tree scroll, half-width columns in slot order" "1: scroll:0.5[main, right, side] *" "$(smoke layout)"
  expect_eq "drawn as scroll · half" "1: scroll · half" "$(smoke layoutMode)"
  smoke press l >/dev/null
  expect_eq "l moves right a column on" "1: scroll:0.5[main, side, right] *" "$(smoke layout)"
  if [[ $(smoke help) == *'">t</font></b> scroll full'* && $(smoke help) != *atios* ]]; then
    pass "the help row: t makes it full width, no r on a scroll tree"
  else
    fail "help row: $(smoke help)"
  fi
  sleep 0.3
  shot 8b-layout-scroll-half
  smoke press r >/dev/null
  expect_eq "r is refused on a scroll tree, no prompt" \
    "Ratios are for tiles: each column of a scroll tree is a set width of the screen (half here). t cycles to tiles." \
    "$(smoke message)"
  smoke press t >/dev/null
  expect_eq "t again: full-width columns" "1: scroll[main, side, right] *" "$(smoke layout)"
  expect_eq "drawn as scroll · full" "1: scroll · full" "$(smoke layoutMode)"
  sleep 0.3
  shot 8c-layout-scroll-full
  smoke press t >/dev/null
  expect_eq "t again: tiles, side by side (the columns moved)" "1: h[main, side, right] *" "$(smoke layout)"
  smoke press t >/dev/null
  smoke press t >/dev/null
  expect_eq "t, t: scroll full again" "1: scroll[main, side, right] *" "$(smoke layout)"
  expect_eq "w" "ok" "$(smoke press w)"
  if eventually 5 tree_in_force_is 'scroll[main, side, right]'; then
    pass "w applied the scroll tree"
  else
    fail "the tree in force is $(tree_in_force): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "applied, not saved" "true" "$(api_state | jq -r .dirty)"
  smoke press d >/dev/null
  expect_eq "d asks first, in words with no file name" \
    "Revert workspace 3's tree on screen 1 to how it was last saved? Its unsaved edits go. (y/n)" "$(smoke message)"
  smoke press y >/dev/null
  local clean='1: v[main:2, h[right, side:3]]'
  if eventually 5 bash -c "[[ \$($watch layout) == '$clean' ]]"; then
    pass "d, y reverted the applied scroll tree to the saved one"
  else
    fail "after d, y the draft is $(smoke layout): $(smoke message) $(smoke errors)"
  fi
  eventually 5 smoke_idle || true
  expect_eq "the tree in force too" "v[main:2, h[right, side:3]]" "$(tree_in_force)"
  expect_eq "nothing unsaved" "false" "$(api_state | jq -r .dirty)"
  expect_eq "it says so" "Reverted workspace 3's tree on screen 1: v[main:2, h[right, side:3]]." "$(smoke message)"
  # t three times from the saved tree comes back to it.
  smoke press t >/dev/null
  smoke press t >/dev/null
  smoke press t >/dev/null
  expect_eq "t, t, t: back to the tree it was made from" "$clean" "$(smoke layout)"

  # Ctrl+S with an edited draft applies it first, then saves.
  expect_eq "/" "ok" "$(smoke press /)"
  expect_eq "/ flips the draft back" "1: h[main:2, v[right, side:3]] *" "$(smoke layout)"
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  if eventually 5 bash -c "[[ \$($watch layout) == '1: h[main:2, v[right, side:3]]' ]]" && eventually 5 saved; then
    pass "Ctrl+S applied the draft and saved it"
  else
    fail "after Ctrl+S: draft $(smoke layout), tree $(tree_in_force), dirty $(api_state | jq -r .dirty): $(smoke message)"
  fi
  expect_eq "the tree in force is the draft" "h[main:2, v[right, side:3]]" "$(tree_in_force)"
  if grep -qF '[1] = "h[main:2, v[right, side:3]]"' "$E2E_CONFIG_HOME/hyprslots/slots.lua"; then
    pass "slots.lua holds it"
  else
    fail "slots.lua: $(cat "$E2E_CONFIG_HOME/hyprslots/slots.lua")"
  fi
  eventually 5 smoke_idle || true

  # ] and the digits switch the workspace (the arrows stay the picture's):
  # workspace 4 has no tree of its own and shows the shared one.
  expect_eq "]" "ok" "$(smoke press ])"
  expect_eq "] edits workspace 4" "Editing workspace 4 of solo. (uses the shared tree)" "$(smoke message)"
  expect_eq "which shows the shared tree" "1: h[main, right, side]" "$(smoke layout)"
  sleep 0.3
  shot 8e-layout-workspace-4

  # - edits the layout's shared trees (All workspaces): / flips them, w
  # applies it; workspace 4, with no trees of its own, then shows them.
  expect_eq "-" "ok" "$(smoke press -)"
  expect_eq "- edits All workspaces" "Editing all workspaces (the shared tree) of solo." "$(smoke message)"
  expect_eq "the header says so" "[All workspaces] · 1 2 3• 4 5 6 7 8 9" "$(smoke layoutHeader)"
  press_keys /
  expect_eq "flipped in the draft" "1: v[main, right, side] *" "$(smoke layout)"
  press_keys w
  if eventually 5 state_is '.layouts.solo.default["1"].tree' 'v[main, right, side]'; then
    pass "w applied the shared trees (set_trees on workspace default)"
  else
    fail "solo's default trees: $(api_state | jq -c '.layouts.solo.default'): $(smoke message)"
  fi
  eventually 5 smoke_idle || true
  sleep 0.3
  shot 8f-layout-default-trees
  press_keys 4
  expect_eq "4: workspace 4 says it uses the shared tree" \
    "Editing workspace 4 of solo. (uses the shared tree)" "$(smoke message)"
  expect_eq "the shared tree" "1: v[main, right, side]" "$(smoke layout)"
  expect_eq "workspace 4 has no trees of its own" "[3]" "$(api_state | jq -c '.layouts.solo.own')"
  layout_scope
  expect_eq "3" "ok" "$(smoke press 3)"
  expect_eq "3 jumps back to workspace 3" "Editing workspace 3 of solo." "$(smoke message)"
  expect_eq "its tree" "1: h[main:2, v[right, side:3]]" "$(smoke layout)"

  layout_slots
  layout_shared
  desks_layouts
  save_and_check
  desks_layouts_edits

  # The Layout tab follows the active desk's layout through all of it.
  press_keys Tab Tab
  expect_eq "the Layout tab follows the active layout" "The active desk uses layout 'solo-2' now; editing it." "$(smoke message)"
  expect_eq "its tree" "1: h[main:2, v[aside, side:3]]" "$(smoke layout)"
  sleep 0.3
  shot 18-layout-follows

  expect_eq "Escape" "ok" "$(smoke press Escape)"
  expect_eq "the panel is closed" "no" "$(smoke ready)"

  # The last failed call is the delete of dual the engine refused on purpose.
  expect_eq "no editor errors but the refused delete" " | $SMOKE_REFUSAL" "$(smoke errors)"
  bar_widget
  assignment_assign

  log "assign round trip takes $(time_ms repl "return hyprslots.api.call(\"assign\", \"{\\\"address\\\":\\\"$stray\\\",\\\"workspace\\\":3,\\\"slot\\\":\\\"side\\\"}\")") ms"

  log "qs log (warnings):"
  grep -iE 'warn|error|fail' "$E2E_DIR/qs.log" | head -n 20 | sed 's/^/    /'
}
