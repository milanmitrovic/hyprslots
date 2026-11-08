# Slice 6: the editor's api round trip on one screen.
#
# Screen: HEADLESS-2, 2400x1350 at 0,0, Omarchy block 0 (desk N = workspace N).
# Desk 3, arrangement "solo": h[a:1, b:2, c:1] -> 600 + 1200 + 600 px.
#
# set_ratio changes the tree to 1:1:2 and the screen follows; record reads the
# windows back into that same tree; save writes slots.lua; both an api reload
# and a full Hyprland config reload come back with the same layout. Every
# change reaches socket2 as custom>>hyprslots changed <seq>.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "2400x1350@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2

  mkdir -p "$E2E_CONFIG_HOME/hyprslots"
  cat >"$E2E_CONFIG_HOME/hyprslots/config.lua" <<'LUA'
local data = load_data("slots.lua")
return { slots = data.slots, specs = data.specs, arrangements = data.arrangements, pinned = {} }
LUA
  cat >"$E2E_CONFIG_HOME/hyprslots/slots.lua" <<'LUA'
return {
  slots = { a = {}, b = {}, c = {} },
  specs = {
    [3] = { a = "t-a", b = "t-b", c = "t-c" },
  },
  arrangements = {
    solo = {
      screens = { main = "HEADLESS-2" },
      desks = { [3] = { main = "h[a:1, b:2, c:1]" } },
    },
  },
}
LUA
}

# hyprslots.api.call(name, json) -> its JSON reply.
api() {
  local args=${2:-'{}'}
  args=${args//\\/\\\\}
  args=${args//\"/\\\"}
  repl "return hyprslots.api.call(\"$1\", \"$args\")"
}

# A field of a JSON reply (jq path).
field() { jq -r "$1 | if . == null then \"\" else tostring end" 2>/dev/null; }

main_tree() { api state | field '.arrangements.solo.desks["3"].main.tree'; }

tree_is() { [[ $(main_tree) == "$1" ]]; }

on_workspace() {
  [[ $(hc clients -j | jq -r --arg c "$1" 'first(.[] | select(.class == $c)) | .workspace.id') == "$2" ]]
}

# Socket2 lines, collected by a reader started in test_body.
SOCKET2_LOG=''

start_socket2_reader() {
  local socket=$XDG_RUNTIME_DIR/hypr/$E2E_SIG/.socket2.sock
  [[ -S $socket ]] || harness_fail "no socket2 at $socket"
  SOCKET2_LOG=$E2E_DIR/socket2.log
  socat -u "UNIX-CONNECT:$socket" "OPEN:$SOCKET2_LOG,creat,append" 2>>"$E2E_DIR/socat.log" &
  E2E_CLIENT_PIDS+=("$!")
}

saw_event() { grep -q "^custom>>hyprslots changed $1\$" "$SOCKET2_LOG"; }

test_body() {
  output_create HEADLESS-2
  expect_eq "hyprslots loaded" "" "$(hyprslots_load_error | head -n1)"
  start_socket2_reader

  for class in t-c t-a t-b; do
    spawn_and_wait "$class"
    eventually 5 on_workspace "$class" 3 || true
  done
  log "desk 3 -> $(api desk '{"desk": 3}')"
  settle
  expect_client t-a 3 0 0 600 1350
  expect_client t-b 3 600 0 1200 1350
  expect_client t-c 3 1800 0 600 1350

  # Given the tree h[a:1, b:2, c:1], when set_ratio makes it 1:1:2,
  # then the screen follows without anything else happening.
  local reply seq
  reply=$(api set_ratio '{"desk": 3, "role": "main", "ratio": "1:1:2"}')
  log "set_ratio -> $reply"
  expect_eq "set_ratio ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "set_ratio tree" "h[a, b, c:2]" "$(field .tree <<<"$reply")"
  seq=$(field .seq <<<"$reply")
  settle
  expect_client t-a 3 0 0 600 1350
  expect_client t-b 3 600 0 600 1350
  expect_client t-c 3 1200 0 1200 1350
  eventually 5 saw_event "$seq" || true
  if saw_event "$seq"; then pass "socket2 saw custom>>hyprslots changed $seq"; else fail "socket2 never saw custom>>hyprslots changed $seq"; fi

  # When the workspace is recorded, then it reads back as the same tree.
  reply=$(api record)
  log "record -> $reply"
  expect_eq "record ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "recorded tree" "h[a, b, c:2]" "$(field .tree <<<"$reply")"
  expect_eq "record applied" "true" "$(field .applied <<<"$reply")"
  expect_eq "unsaved" "true" "$(api state | field .dirty)"

  # When saved, then slots.lua holds the tree, under the editor's header.
  local slots_file=$E2E_CONFIG_HOME/hyprslots/slots.lua
  reply=$(api save)
  log "save -> $reply"
  expect_eq "save ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "save path" "$slots_file" "$(field .path <<<"$reply")"
  if grep -q 'main = "h\[a, b, c:2\]"' "$slots_file" && grep -q 'editor' "$slots_file"; then
    pass "slots.lua holds the saved tree"
  else
    fail "slots.lua does not hold the saved tree:"
    sed 's/^/    /' "$slots_file"
  fi
  expect_eq "saved" "false" "$(api state | field .dirty)"
  if ls "$E2E_CONFIG_HOME/hyprslots" | grep -q tmp; then fail "a temp file was left behind"; else pass "no temp file left"; fi

  # When the config is reloaded in place, then the layout is the same.
  reply=$(api reload)
  log "reload -> $reply"
  expect_eq "reload ok" "true" "$(field .ok <<<"$reply")"
  expect_eq "tree after api reload" "h[a, b, c:2]" "$(main_tree)"
  settle
  expect_client t-a 3 0 0 600 1350
  expect_client t-b 3 600 0 600 1350
  expect_client t-c 3 1200 0 1200 1350

  # When Hyprland reloads its whole config (Lua state discarded), then the
  # saved slots.lua gives the same layout again.
  log "hyprctl reload -> $(hc reload)"
  eventually 5 tree_is "h[a, b, c:2]" || true
  expect_eq "tree after Hyprland reload" "h[a, b, c:2]" "$(main_tree)"
  settle
  expect_client t-a 3 0 0 600 1350
  expect_client t-b 3 600 0 600 1350
  expect_client t-c 3 1200 0 1200 1350

  # Errors come back as JSON, never as an empty reply.
  reply=$(api set_ratio '{"desk": 3, "role": "main", "ratio": "1:1"}')
  expect_eq "a bad ratio is an error reply" "false" "$(field .ok <<<"$reply")"
  log "bad ratio -> $(field .error <<<"$reply")"

  log "events on socket2:"
  grep '^custom>>' "$SOCKET2_LOG" | sed 's/^/    /'
  log "windows at the end:"
  client_table | sed 's/^/    /'
}
