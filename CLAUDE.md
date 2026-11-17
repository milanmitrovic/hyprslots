# hyprslots: notes for AI agents

hyprslots gives Hyprland (0.56.2, Lua config, on Omarchy) deterministic,
named window layouts spanning every screen: a layout is a tree of exact
splits whose leaves are slots, each naming the app that belongs there.
Opening an app routes it into its slot, switching workspaces switches every
screen, plugging a monitor picks the desk and layout for it. The engine is
Lua (`lua/hyprslots/`); the editor is an Omarchy shell plugin in QML/JS
(`editor/`). The design, and the why behind it, lives in `docs/design.md`:
read the relevant section before changing behaviour, and keep it current.

## Commands

- `make test`: everything (busted + node's test runner + Qt 6 qmltestrunner
  where installed); fails without node or Lua.
- `make lua-test`: the busted specs (`spec/`, Lua 5.4) plus a `luac5.5 -p`
  compile check of every engine file, since Hyprland runs Lua 5.5 (e.g. a
  for loop's variables are constants there).
- `make editor-lint`: qmllint over `editor/*.qml` and `editor/ui/*.qml`;
  empty output is clean.
- `make e2e` (one test: `make e2e TESTS=e2e/scroll_test.sh`),
  `make e2e-editor` (`SMOKE_THEME=<an Omarchy theme dir>` for a theme),
  `make e2e-editor-multimon`. Screenshots and logs land in `.e2e-tmp/`.

## e2e safety

- Tests run a nested Hyprland on a headless sway host (needs the `sway`
  package). Drive only that instance: `hyprctl -i <its signature>` or the
  harness helpers (`hc` in `e2e/lib.sh`). Never run `hyprctl` against the
  live session, never touch live outputs/monitors, never kill processes you
  did not start.
- Mouse input goes through ONE long-lived virtual pointer (`vpointer serve`,
  `e2e/shim/vpointer.c`, started in `e2e/editor/lib.sh`). A pointer process
  per click made a new device each time and Hyprland sometimes sent it no
  motion after enter, so clicks were lost; do not reintroduce that.

## The live desktop

The developer's desktop runs a PINNED checkout, `~/Projects/hyprslots/live`
(detached HEAD), via the symlink
`~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots`. Never point it
at a dev worktree. Deploy only when asked:

1. Back up the config: `cp -a ~/.config/hyprslots ~/.config/hyprslots.bak-$(date +%F-%H%M)`.
2. Move the live checkout: `git -C ~/Projects/hyprslots/live fetch` then
   `git -C ~/Projects/hyprslots/live checkout --detach <sha>`.
3. Lua changed: `hyprctl reload`, then check `hyprctl configerrors` is empty
   and the engine answers: `hyprctl repl 'return hyprslots.api.call("state", "{}")'`.
4. QML/JS changed: `omarchy restart shell` (it refuses while the session is
   locked; wait, do not work around it).

## Git

gfl: one worktree per branch (`../develop`, `../f-editor`, ...); merging is
the human's (`/land`). An async autopush hook pushes every commit at once,
so commit final content the first time: never amend, squash, rebase or
force-push. Commits are bisectable, one logical change each.

## Conventions

- Pure logic lives in `lua/hyprslots/*.lua` and `editor/*.js`, each with
  tests (`spec/*_spec.lua` against the hl stub in `spec/helpers/hl_stub.lua`;
  `editor/tests/*.test.mjs`). Write the test first.
- The engine touches Hyprland only through `lua/hyprslots/hl_adapter.lua`;
  the api (`api.lua`) is a protocol layer the engine never requires
  (`spec/module_boundaries_spec.lua`).
- Editor visuals go only through the `editor/ui/` components and
  `editor/ui/Tokens.qml`; no ad hoc colours, sizes or fonts.
- User-facing copy is plain words: no "spec", "overflow", "tree" or other
  internal jargon in what the user reads.
- Every editor action is reachable by key and by mouse, both through the
  same handler.
- Decisions and diagnostics go to the engine log (`engine.log:info/warn/error`,
  `lua/hyprslots/log.lua`); `hyprslots.dump()` prints state and log.
