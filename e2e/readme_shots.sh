# The README's screenshots (opt-in: not a *_test.sh, so `make e2e` skips
# it, and no gate runs it; `make readme-shots` or `e2e/run.sh
# e2e/readme_shots.sh`). Needs qs, grim, magick (ImageMagick), nvim, bat,
# glow and Omarchy's shell modules, as e2e/editor_smoke.sh does; oxipng or
# optipng, where installed, shrinks the pictures.
#
# It stages a demo, not a test: Omarchy's default theme (tokyo-night, or
# SMOKE_THEME), its wallpaper, gaps and borders, and foot windows that read
# like real apps (an editor in nvim, a terminal, docs, team chat, notes).
# Each picture is cropped to what matters (the editor's card, or the
# screens) and goes to $README_SHOTS (default docs/screenshots):
#
#   capture-preview.png  a fresh install on one screen: c, a, the preview
#                        and its y/n line (Quick start A)
#   assignment-tab.png   workspace 1's slots and windows, the editor's
#                        window dragged onto main ("Assign to main")
#   layout-tab.png       All workspaces: the shared layout on both screens,
#                        the slot list beside it (also preview.png)
#   scroll-layout.png    screen 1 turned into scrolling columns (not applied)
#   desk-tab.png         desks home (both screens, layout two-screen) and
#                        laptop (not plugged, layout scrolling)
#   desk-docked.png      both screens with workspace 1's windows in their slots
#   desk-laptop.png      the same workspace undocked, on the laptop's screen
#                        alone: its slots as full-width scrolling columns,
#                        the editor's in view, the edges of the columns
#                        beside it (each as the screen shows it scrolled
#                        there) dimmed to either side
#
# README_SHOTS_LIGHT=<an Omarchy theme dir> also takes layout-tab-light.png
# with the editor in that (light) theme.
#
# Screens: DP-1 ("27-inch"), 2560x1440 at 0,0 (screen 1, Omarchy
# block 0); HDMI-A-1 ("24-inch"), 1920x1080 at 2560,360 (screen 2, block
# 1), plugged in after the capture; eDP-1 ("Laptop"), 1920x1200, plugged
# in alone at the end (desk laptop).

SMOKE_THEME=${SMOKE_THEME:-${OMARCHY_PATH:-/usr/share/omarchy}/themes/tokyo-night}
README_SHOTS=${README_SHOTS:-$E2E_ROOT/docs/screenshots}

test_setup() {
  local colors=$SMOKE_THEME/colors.toml
  color() { sed -n "s/^$1 *= *\"#\\([0-9a-fA-F]*\\)\"/\\1/p" "$colors"; }
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<LUA
hl.monitor({ output = "DP-1", mode = "2560x1440@60", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "2560x360", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x1440", scale = 1 })
-- Omarchy's look: its gaps and borders, the theme's accent.
hl.config({
  general = {
    gaps_in = 5, gaps_out = 10, border_size = 2,
    col = { active_border = "rgb($(color accent))", inactive_border = "rgba(595959aa)" },
  },
  misc = { background_color = "rgb($(color background))" },
  cursor = { invisible = true },
  -- the windows arranged for the capture stand as spawned
  dwindle = { force_split = 2 },
})
LUA
  smoke_theme_look
  seed_workspace_blocks DP-1 HDMI-A-1

  # foot in the theme's colours and Omarchy's font
  cat >"$E2E_DIR/foot.ini" <<INI
[main]
font=JetBrainsMono Nerd Font:size=14
pad=14x14
locked-title=yes
[colors-dark]
foreground=$(color foreground)
background=$(color background)
regular0=$(color background)
regular1=$(color red)
regular2=$(color green)
regular3=$(color yellow)
regular4=$(color blue)
regular5=$(color magenta)
regular6=$(color cyan)
regular7=$(color foreground)
bright0=$(color muted)
bright1=$(color bright_red)
bright2=$(color bright_green)
bright3=$(color bright_yellow)
bright4=$(color bright_blue)
bright5=$(color bright_magenta)
bright6=$(color bright_cyan)
bright7=$(color bright_foreground)
INI
  demo_files

  # A fresh install: no slots yet; the monitors named as a user would.
  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return {
  slots = data.slots, specs = data.specs, desks = data.desks, layouts = data.layouts,
  monitor_names = data.monitor_names, workspaces = 9,
}
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  desks = { home = { monitors = { "DP-1" }, layout = "single" } },
  layouts = { single = { screens = 1 } },
  monitor_names = { ["DP-1"] = "27-inch", ["HDMI-A-1"] = "24-inch", ["eDP-1"] = "Laptop" },
}
LUA
}

# What the demo's windows show.
demo_files() {
  DEMO=$E2E_DIR/demo
  mkdir -p "$DEMO/site/src"
  cat >"$DEMO/site/src/router.js" <<'JS'
import { render } from "./render.js";
import { routes } from "./routes.js";

const cache = new Map();

// Find the route for a path: exact first, then the longest prefix.
export function match(path) {
  if (routes[path]) return { route: routes[path], params: {} };
  const prefixes = Object.keys(routes)
    .filter((key) => key.endsWith("/*") && path.startsWith(key.slice(0, -1)))
    .sort((a, b) => b.length - a.length);
  if (prefixes.length === 0) return null;
  const rest = path.slice(prefixes[0].length - 1);
  return { route: routes[prefixes[0]], params: { rest } };
}

export async function navigate(path, { replace = false } = {}) {
  const found = match(path);
  if (!found) return navigate("/404", { replace: true });
  if (!cache.has(path)) cache.set(path, await found.route.load(found.params));
  const page = cache.get(path);
  if (replace) history.replaceState({ path }, "", path);
  else history.pushState({ path }, "", path);
  document.title = `${page.title} · Site`;
  render(page);
}

window.addEventListener("popstate", (event) => {
  navigate(event.state?.path ?? "/", { replace: true });
});
JS
  cat >"$DEMO/docs.md" <<'MD'
# Routing

Pages live in `src/pages/`; each file is a route.

## Dynamic routes

A route ending in `/*` matches every path below it.
The rest of the path arrives as `params.rest`:

```js
export const routes = {
  "/": home,
  "/blog/*": post,
};
```

## Navigation

Call `navigate(path)` to change pages without a reload.
Pages are cached after their first load.

> Tip: pass `{ replace: true }` for redirects, so the
> back button skips them.

## See also

- Rendering
- Data loading
- Deployment
MD
  cat >"$DEMO/notes.md" <<'MD'
# Today

- [x] Review the docs PR
- [ ] Fix the /blog redirect
- [ ] Release notes for 2.4

# Ideas

- Prefetch on hover
- Dark mode for code blocks
MD
  cat >"$DEMO/terminal.sh" <<'SH'
b=$'\e[1;34m' m=$'\e[1;35m' g=$'\e[1;32m' d=$'\e[2m' c=$'\e[36m' r=$'\e[0m'
printf '%s~/projects/site%s on %s main%s\n%s❯%s git pull\n' "$b" "$r" "$m" "$r" "$g" "$r"
printf 'Already up to date.\n\n'
printf '%s~/projects/site%s on %s main%s\n%s❯%s npm run dev\n\n' "$b" "$r" "$m" "$r" "$g" "$r"
printf '  %sVITE v6.0.3%s  ready in 412 ms\n\n' "$g" "$r"
printf '  %s➜%s  Local:   %shttp://localhost:5173/%s\n' "$g" "$r" "$c" "$r"
printf '  %s➜  Network: use --host to expose%s\n\n' "$d" "$r"
printf '%s9:41:07 AM%s %s[vite]%s hmr update /src/router.js\n' "$d" "$r" "$c" "$r"
printf '%s9:42:15 AM%s %s[vite]%s hmr update /src/router.js\n' "$d" "$r" "$c" "$r"
SH
  cat >"$DEMO/chat.sh" <<'SH'
d=$'\e[2m' b=$'\e[1m' r=$'\e[0m'
say() { printf '%s%-6s%s %s%s%s\n        %s\n\n' "$b$2" "$1" "$r" "$d" "$3" "$r" "$4"; }
printf '%s# web-team%s\n\n' "$b" "$r"
say Ana $'\e[35m' 09:12 "morning! 2.3.1 went out fine overnight"
say Marko $'\e[32m' 09:14 "nice. who's taking the docs PR?"
say you $'\e[34m' 09:15 "me, right after standup"
say Ana $'\e[35m' 09:21 "the /blog redirect is back, see #418"
say Marko $'\e[32m' 09:23 "router.js again? :)"
say you $'\e[34m' 09:24 "on it"
SH
  # Runs a command full screen, again whenever the window changes size
  # (each window is drawn as it stands in its slot), the cursor hidden.
  cat >"$DEMO/show.sh" <<'SH'
draw() { printf '\033[H\033[2J\033[3J'; "$@"; printf '\033[?25l'; }
trap 'draw "$@"' WINCH
trap 'kill $! 2>/dev/null; exit 0' HUP TERM
draw "$@"
while :; do sleep 3600 & wait $!; done
SH
}

# shellcheck source=e2e/editor/lib.sh
source "$E2E_ROOT/e2e/editor/lib.sh"

# A foot window of app id $1, titled $2, running $3 (a shell command), on
# the test instance; it waits for the window to map.
spawn_app() {
  local class=$1 title=$2 cmd=$3
  (cd "$DEMO/site" && WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY foot --config="$E2E_DIR/foot.ini" \
    --app-id="$class" --title="$title" sh -c "$cmd" >>"$E2E_DIR/clients.log" 2>&1) &
  E2E_CLIENT_PIDS+=("$!")
  eventually 10 client_mapped "$class" || harness_fail "client $class never mapped"
}

spawn_editor() {
  spawn_app editor "~/projects/site — nvim" \
    "exec nvim --clean -n -i NONE -c 'set number cursorline' -c 'normal! 22G' src/router.js"
}
spawn_terminal() { spawn_app terminal "~/projects/site" "exec bash '$DEMO/show.sh' bash '$DEMO/terminal.sh'"; }
spawn_browser() {
  spawn_app browser "Docs — Routing" \
    "exec bash '$DEMO/show.sh' bash -c 'glow -s dark -w \$((\$(stty size | cut -d\" \" -f2) - 4)) $DEMO/docs.md'"
}
spawn_chat() { spawn_app chat "Team chat" "exec bash '$DEMO/show.sh' bash '$DEMO/chat.sh'"; }
spawn_notes() {
  spawn_app notes "Notes — today" \
    "exec bash '$DEMO/show.sh' bat --paging=never --style=plain --color=always --theme=ansi '$DEMO/notes.md'"
}

# The wallpaper: the theme's second background (tokyo-night's winding
# road) on every screen, through a Quickshell of its own (the panel's stays
# the smoke's).
start_wallpaper() {
  local image dir=$E2E_DIR/wallpaper
  image=$(find "$SMOKE_THEME/backgrounds" -maxdepth 1 -type f \( -name '*.webp' -o -name '*.jpg' -o -name '*.png' \) |
    sort | sed -n 2p)
  [[ -n $image ]] || return 0
  mkdir -p "$dir"
  cat >"$dir/shell.qml" <<QML
import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "wallpaper"
      color: "black"
      Image { anchors.fill: parent; source: "file://$image"; fillMode: Image.PreserveAspectCrop }
    }
  }
}
QML
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY QT_QPA_PLATFORM=wayland qs --no-color -p "$dir" >"$E2E_DIR/wallpaper.log" 2>&1 &
  E2E_CLIENT_PIDS+=("$!")
}

# The PNG $1, as small as it gets without losing a pixel.
optimize() {
  if command -v oxipng >/dev/null; then oxipng -q -o 4 --strip safe "$1"
  elif command -v optipng >/dev/null; then optipng -quiet -o5 -strip all "$1"
  fi
}

# Screen DP-1 as it stands, the panel closed: what card_shot tells the
# card from.
backdrop() {
  hc dismissnotify >/dev/null 2>&1
  sleep 0.4
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o DP-1 "$E2E_DIR/backdrop.png" 2>>"$E2E_DIR/grim.log" ||
    harness_fail "grim could not take the backdrop"
}

# The panel's card from screen DP-1, into $README_SHOTS/$1.png. Around the
# card the panel's scrim (the theme's background at half opacity, as
# Omarchy's menus have it) dims the backdrop; the card is what differs from
# the backdrop so dimmed (the windows behind stand still), centred on the
# screen. PANEL_THEME is the theme the panel is in.
PANEL_THEME=$SMOKE_THEME
card_shot() {
  local raw=$E2E_DIR/$1-raw.png out=$README_SHOTS/$1.png box w h x y sw sh
  mkdir -p "$README_SHOTS"
  hc dismissnotify >/dev/null 2>&1
  sleep 0.4
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o DP-1 "$raw" 2>>"$E2E_DIR/grim.log" ||
    { fail "grim could not take $raw"; return; }
  local scrim
  scrim=#$(sed -n 's/^background *= *"#\([0-9a-fA-F]*\)"/\1/p' "$PANEL_THEME/colors.toml")
  box=$(magick \( "$E2E_DIR/backdrop.png" -fill "$scrim" -colorize 50% \) "$raw" -compose difference -composite \
    -colorspace gray -threshold 8% -format '%@' info:)
  read -r sw sh <<<"$(magick identify -format '%w %h' "$raw")"
  if [[ ! $box =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then fail "$1: no card in $raw ($box)"; return; fi
  w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} x=${BASH_REMATCH[3]} y=${BASH_REMATCH[4]}
  if (((2 * x + w - sw) ** 2 > 16 || (2 * y + h - sh) ** 2 > 16)); then
    fail "$1: the change ($box) is not a card centred on the ${sw}x$sh screen"
    return
  fi
  magick "$raw" -crop "$box" +repage -strip -define png:compression-level=9 "$out" ||
    { fail "could not crop $raw"; return; }
  optimize "$out"
  log "screenshot: $out (${w}x$h)"
}

# The desk pictures stand on a neutral dark fill (above the shorter screen,
# between screens, a margin around), which reads the same on a light page
# and a dark one.
DESK_FILL='#1e1f22' DESK_MARGIN=16

# Both screens side by side, bottoms aligned as they stand, at half size,
# in 256 colours (a third of the size; the eye sees no difference).
desktop_shot() {
  local a=$E2E_DIR/screen1.png b=$E2E_DIR/screen2.png out=$README_SHOTS/$1.png
  mkdir -p "$README_SHOTS"
  hc dismissnotify >/dev/null 2>&1
  sleep 0.4
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o DP-1 "$a" 2>>"$E2E_DIR/grim.log" &&
    WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o HDMI-A-1 "$b" 2>>"$E2E_DIR/grim.log" ||
    { fail "grim could not take the screens"; return; }
  magick \( "$a" -resize 50% \) \( -size 24x1 xc:"$DESK_FILL" \) \( "$b" -resize 50% \) \
    -background "$DESK_FILL" -gravity South +append -bordercolor "$DESK_FILL" -border "$DESK_MARGIN" \
    -dither None -colors 256 -strip -define png:compression-level=9 "$out" ||
    { fail "could not compose $out"; return; }
  optimize "$out"
  log "screenshot: $out ($(magick identify -format '%wx%h' "$out"))"
}

# Screen $1 with the window of class $2 focused (the scrolling layout
# scrolls it into view), into $3.
scrolled_to() {
  hc dispatch "hl.dsp.focus({ window = 'class:$2' })" >/dev/null
  settle
  sleep 0.6
  local x
  x=$(hc clients -j | jq -r --arg c "$2" 'first(.[] | select(.class == $c)) | .at[0]')
  log "$2 in view at x=$x"
  WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY grim -o "$1" "$3" 2>>"$E2E_DIR/grim.log" ||
    { fail "grim could not take $3"; return 1; }
}

# The laptop's screen $1 scrolled to the column of class $3, at half size,
# with the columns beside it on the tape: the right edge of class $2's
# (as the screen shows it scrolled there) to the left, the left edge of
# class $4's to the right, each dimmed and fading into the fill. As tall as
# the picture $6 (the docked one, so the two stand side by side), bottoms
# aligned; into $README_SHOTS/$5.png.
laptop_shot() {
  local screen=$1 out=$README_SHOTS/$5.png prev=$E2E_DIR/laptop-prev.png cur=$E2E_DIR/laptop-cur.png
  local next=$E2E_DIR/laptop-next.png w h sw height
  mkdir -p "$README_SHOTS"
  hc dismissnotify >/dev/null 2>&1
  scrolled_to "$screen" "$2" "$prev" && scrolled_to "$screen" "$4" "$next" &&
    scrolled_to "$screen" "$3" "$cur" || return
  read -r w h <<<"$(magick identify -format '%w %h' "$cur")"
  w=$((w / 2)) h=$((h / 2)) sw=$((w * 7 / 20))
  height=$(($(magick identify -format '%h' "$6") - 2 * DESK_MARGIN))
  # Each edge: a slice sw wide, blended into the fill through a gradient
  # (15% of it at the outer side, 60% at the inner).
  magick \( -size "${sw}x$h" xc:"$DESK_FILL" \) \
    \( "$prev" -resize 50% -gravity East -crop "${sw}x$h+0+0" +repage \) \
    \( -size "${h}x$sw" gradient:'gray(15%)'-'gray(60%)' -rotate -90 \) \
    -compose over -composite "$E2E_DIR/laptop-left.png" &&
    magick \( -size "${sw}x$h" xc:"$DESK_FILL" \) \
      \( "$next" -resize 50% -gravity West -crop "${sw}x$h+0+0" +repage \) \
      \( -size "${h}x$sw" gradient:'gray(15%)'-'gray(60%)' -rotate 90 \) \
      -compose over -composite "$E2E_DIR/laptop-right.png" ||
    { fail "could not cut the neighbouring columns"; return; }
  magick "$E2E_DIR/laptop-left.png" \( -size 12x1 xc:"$DESK_FILL" \) \( "$cur" -resize 50% \) \
    \( -size 12x1 xc:"$DESK_FILL" \) "$E2E_DIR/laptop-right.png" \
    -background "$DESK_FILL" -gravity South +append -extent "$((2 * sw + 24 + w))x$height" \
    -bordercolor "$DESK_FILL" -border "$DESK_MARGIN" \
    -dither None -colors 256 -strip -define png:compression-level=9 "$out" ||
    { fail "could not compose $out"; return; }
  optimize "$out"
  log "screenshot: $out ($(magick identify -format '%wx%h' "$out"))"
}

row_index() { smoke rows | awk -v RS='; ' -v want="$1" '$0 ~ want { print NR - 1; exit }'; }

# A different theme's panel: Quickshell again, with a home whose current
# theme is $1 (start_editor's SMOKE_THEME home, made again).
restart_panel_in() {
  local home=$E2E_DIR/home-$(basename "$1") omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
  kill "$SMOKE_QS_PID" 2>/dev/null
  wait "$SMOKE_QS_PID" 2>/dev/null
  mkdir -p "$home/.local/state/omarchy/current" "$home/.config"
  ln -sfn "$1" "$home/.local/state/omarchy/current/theme"
  if [[ -d $HOME/.config/fontconfig ]]; then ln -sfn "$HOME/.config/fontconfig" "$home/.config/fontconfig"; fi
  HOME=$home WAYLAND_DISPLAY=$E2E_WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE=$E2E_SIG QT_QPA_PLATFORM=wayland \
    OMARCHY_PATH=$omarchy qs --no-color -p "$SMOKE_QS_DIR" >"$E2E_DIR/qs-light.log" 2>&1 &
  SMOKE_QS_PID=$!
  E2E_CLIENT_PIDS+=("$SMOKE_QS_PID")
  eventually 15 qs ipc --pid "$SMOKE_QS_PID" show || harness_fail "Quickshell in $1 never answered ipc"
}

open_panel() {
  hc dispatch "hl.dsp.focus({ monitor = 'DP-1' })" >/dev/null
  expect_eq "panel opens" "ok" "$(smoke open)"
  eventually 10 smoke_ready || fail "the panel never read state: $(smoke errors)"
  sleep 0.6
}

test_body() {
  for tool in qs grim magick nvim bat glow; do
    command -v "$tool" >/dev/null || harness_fail "the README shots need $tool"
  done
  local watch data=$E2E_CONFIG_HOME/hyprslots/slots.lua
  output_create DP-1
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  start_wallpaper

  # 1. A fresh install on one screen: windows tiled by hand, captured.
  hc dispatch "hl.dsp.focus({ workspace = '1' })" >/dev/null
  spawn_editor
  spawn_terminal
  settle
  hc dispatch 'hl.dsp.focus({ window = "class:editor" })' >/dev/null
  hc dispatch 'hl.dsp.window.resize({ x = 427, y = 0, relative = true })' >/dev/null
  settle
  log "windows:"
  client_table | sed 's/^/    /'

  backdrop
  start_editor
  watch="qs ipc --pid $SMOKE_QS_PID call smoke"
  open_panel
  eventually 5 tab_is Layout || fail "a fresh install opens on: $(smoke tabs)"
  expect_eq "c" "ok" "$(smoke press c)"
  expect_eq "a" "ok" "$(smoke press a)"
  eventually 5 bash -c "[[ -n \$($watch capturePreview) ]]" || fail "no preview: $(smoke message)"
  log "preview: $(smoke capturePreview) | $(smoke message)"
  card_shot capture-preview
  expect_eq "n" "ok" "$(smoke press n)"
  expect_eq "Escape" "ok" "$(smoke press Escape)"

  # 2. Set up: five slots on a two-screen desk; the editor's window not
  # yet in one (main waits for it on workspace 1).
  cat >"$data" <<'LUA'
return {
  slots = {
    left = { key = "l" }, main = { key = "m" }, right = { key = "r" },
    chat = { key = "c" }, notes = { key = "n" },
  },
  specs = {
    [1] = { left = "terminal", right = "browser", chat = "chat", notes = "notes" },
  },
  desks = {
    home = { monitors = { "DP-1", "HDMI-A-1" }, layout = "two-screen" },
    laptop = {
      monitors = { "eDP-1" }, layout = "scrolling",
      geometry = { ["eDP-1"] = { x = 0, y = 0, w = 1920, h = 1200 } },
    },
  },
  layouts = {
    ["two-screen"] = { screens = 2, default = { [1] = "h[left, main:2, right]", [2] = "v[chat:3, notes:2]" } },
    scrolling = { screens = 1, default = { [1] = "scroll[left, main, right, chat, notes]" } },
  },
  monitor_names = { ["DP-1"] = "27-inch", ["HDMI-A-1"] = "24-inch", ["eDP-1"] = "Laptop" },
}
LUA
  output_create HDMI-A-1
  hc reload >/dev/null
  eventually 10 state_is .desk home || fail "desk: $(api_state | jq -r .desk) ($(hyprslots_load_error))"
  expect_eq "five slots" "5" "$(api_state | jq -r '.slots | length')"
  hc dispatch "hl.dsp.focus({ monitor = 'DP-1' })" >/dev/null
  spawn_browser
  spawn_chat
  spawn_notes
  settle
  log "windows:"
  client_table | sed 's/^/    /'

  # 3. The Assignment tab: the editor's window dragged onto main.
  backdrop
  open_panel
  local i
  for ((i = 0; i < 3; i++)); do tab_is Assignment || smoke press Tab >/dev/null; done
  expect_eq "workspace 1's page" "Workspace 1" "$(smoke assignmentPage)"
  log "rows: $(smoke rows)"
  local x y
  read -r x y <<<"$(smoke point "row:$(row_index '^main[|]')")"
  smoke_drag "row:$(row_index '[|]editor[|]')" "$x" "$y" 4000
  if eventually 3 bash -c "[[ \$($watch assignmentDrag) == *'Assign to main' ]]"; then pass "held over main"
  else fail "mid-drag: '$(smoke assignmentDrag)'"; fi
  sleep 0.5
  card_shot assignment-tab
  wait "$SMOKE_DRAG_PID" 2>/dev/null
  eventually 5 bash -c "[[ \$($watch message) == Assigned* ]]" || fail "after the drop: $(smoke message)"
  eventually 5 smoke_idle || true
  expect_eq "Ctrl+S" "ok" "$(smoke press Ctrl+s)"
  eventually 5 state_is .dirty false || fail "unsaved after Ctrl+S: $(smoke message)"
  # the editor's window went into main: the backdrop again
  smoke press Escape >/dev/null
  settle
  backdrop
  open_panel

  # 4. The Layout tab: the shared layout on both screens, the slot list.
  for ((i = 0; i < 3; i++)); do tab_is Layout || smoke press Tab >/dev/null; done
  eventually 3 tab_is Layout || fail "tabs: $(smoke tabs)"
  log "layout strip: $(smoke layoutStrip); trees: $(smoke layout)"
  card_shot layout-tab

  # 5. Scrolling columns on screen 1, shown, not applied.
  smoke press t >/dev/null
  log "t: $(smoke layoutMode)"
  card_shot scroll-layout
  smoke press d >/dev/null
  if [[ $(smoke message) == *"?"* ]]; then smoke press y >/dev/null; fi
  log "after d: $(smoke layoutMode); $(smoke message)"

  # 6. The Desk tab: home and laptop.
  smoke press Tab >/dev/null
  eventually 3 tab_is Desk || fail "tabs: $(smoke tabs)"
  log "desks: $(smoke deskMonitors) | maps: $(smoke deskMaps)"
  card_shot desk-tab

  # 7. The desktop: the panel closed, workspace 1 on both screens.
  smoke press Escape >/dev/null
  hc dispatch 'hl.dsp.focus({ window = "class:editor" })' >/dev/null
  settle
  log "windows:"
  client_table | sed 's/^/    /'
  desktop_shot desk-docked

  # The hero picture of the plugin (Omarchy's plugin list shows it).
  cp "$README_SHOTS/layout-tab.png" "$E2E_ROOT/preview.png"

  # 8. Optionally the Layout tab in a light theme.
  if [[ -n ${README_SHOTS_LIGHT:-} ]]; then
    restart_panel_in "$README_SHOTS_LIGHT"
    PANEL_THEME=$README_SHOTS_LIGHT
    open_panel
    for ((i = 0; i < 3; i++)); do tab_is Layout || smoke press Tab >/dev/null; done
    card_shot layout-tab-light
    smoke press Escape >/dev/null
  fi

  # 9. Undocked: the laptop's screen alone, desk laptop, workspace 1's
  # windows as full-width scrolling columns in slot order. The laptop is
  # plugged in first and the desk's screens pulled right after, faster
  # than a new monitor setup gets a desk of its own.
  output_create eDP-1
  output_remove HDMI-A-1
  output_remove DP-1
  eventually 10 state_is .desk laptop || fail "undocked desk: $(api_state | jq -r .desk)"
  local columns='[.[] | select(.workspace.id == 1 and (.floating | not))] | sort_by(.at[0]) | map(.class) | join(" ")'
  eventually 10 bash -c "[[ \$(hyprctl -i $E2E_SIG clients -j | jq -r '$columns') == 'terminal editor browser chat notes' ]]" ||
    fail "laptop columns: $(hc clients -j | jq -r "$columns")"
  expect_eq "workspace 1 scrolls" "scrolling" \
    "$(hc workspaces -j | jq -r 'first(.[] | select(.id == 1)) | .tiledLayout')"
  settle
  log "windows:"
  client_table | sed 's/^/    /'
  laptop_shot eDP-1 terminal editor browser desk-laptop "$README_SHOTS/desk-docked.png"
  expect_eq "nothing left unsaved" "false" "$(api_state | jq -r .dirty)"
}
