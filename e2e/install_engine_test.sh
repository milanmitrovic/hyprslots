# Installing and removing the engine from the command line: a fresh install
# as `omarchy plugin add` leaves it (the plugin folder a copy of the repo, no
# loader in Omarchy's workspace-layouts folder) runs no engine;
# tools/install-engine.sh puts the loader there, reloads Hyprland and finds
# the engine running, Super+1 bound by hyprslots; tools/uninstall-engine.sh
# takes the loader away again and the engine with it. With the plugin removed
# the loader removes itself; with no plugin installed install-engine.sh
# refuses and writes nothing.
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
LUA
  seed_workspace_blocks HEADLESS-2
  install_plugin_copy
  rm -f "$E2E_LOADER"
}

engine() { repl 'if hyprslots then return "running" end return "absent " .. tostring(hyprslots_load_error)'; }

# Whether hyprslots' Super+1 is bound (`hyprctl binds -j` shows a code:10
# bind's key as "", so it is known by its description).
super_1() {
  hc binds -j | jq -r 'if any(.[]; .modmask == 64 and .description == "Switch to workspace 1 on every screen")
    then "hyprslots" else "not hyprslots" end'
}

test_body() {
  output_create HEADLESS-2

  # Given a plugin just added: no loader, no engine.
  expect_eq "no engine before it is enabled" "absent nil" "$(engine)"

  # When it is installed from the plugin's own tools.
  local out status
  out=$("$E2E_PLUGIN_DIR/tools/install-engine.sh" 2>&1)
  status=$?
  log "install-engine.sh: $out"
  expect_eq "install-engine.sh succeeds" 0 "$status"
  if cmp -s "$E2E_PLUGIN_DIR/tools/loader.lua" "$E2E_LOADER"; then
    pass "the loader is in Omarchy's workspace-layouts folder"
  else
    fail "no loader at $E2E_LOADER: $(ls -la "${E2E_LOADER%/*}" 2>&1)"
  fi
  expect_eq "the engine runs" running "$(engine)"
  expect_eq "its state reads" true "$(repl 'return hyprslots.api.state()' | jq -r .ok)"
  expect_eq "Super+1 is hyprslots'" hyprslots "$(super_1)"
  expect_eq "no config errors" "" "$(hc configerrors -j | jq -r '.[] | select(. != "")')"

  # Installing again changes nothing.
  out=$("$E2E_PLUGIN_DIR/tools/install-engine.sh" 2>&1)
  expect_eq "a second install succeeds" 0 "$?"
  expect_eq "and the engine still runs" running "$(engine)"

  # When it is uninstalled.
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1)
  status=$?
  log "uninstall-engine.sh: $out"
  expect_eq "uninstall-engine.sh succeeds" 0 "$status"
  if [[ -e $E2E_LOADER ]]; then fail "the loader is still there"; else pass "the loader is gone"; fi
  expect_eq "the engine is gone" "absent nil" "$(engine)"
  expect_eq "Super+1 is not hyprslots' any more" "not hyprslots" "$(super_1)"
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1)
  expect_eq "uninstalling again succeeds" 0 "$?"

  # The plugin removed with the loader in place: the loader goes with it.
  "$E2E_PLUGIN_DIR/tools/install-engine.sh" >/dev/null 2>&1
  expect_eq "installed again" running "$(engine)"
  rm -rf "$E2E_PLUGIN_DIR"
  hc reload >/dev/null
  eventually 5 bash -c "[[ ! -e '$E2E_LOADER' ]]"
  if [[ -e $E2E_LOADER ]]; then fail "the loader outlived the plugin"; else pass "the loader removed itself with the plugin"; fi
  expect_eq "no engine without the plugin" "absent nil" "$(engine)"
  expect_eq "and no config errors" "" "$(hc configerrors -j | jq -r '.[] | select(. != "")')"

  # No plugin installed: install-engine.sh refuses, writing nothing.
  out=$("$E2E_ROOT/tools/install-engine.sh" 2>&1)
  status=$?
  log "install-engine.sh with no plugin: $out"
  if ((status != 0)) && [[ $out == *"omarchy plugin add"* ]]; then
    pass "install-engine.sh refuses without the plugin, saying how to add it"
  else
    fail "install-engine.sh without the plugin: exit $status, '$out'"
  fi
  if [[ -e $E2E_LOADER ]]; then fail "it wrote a loader anyway"; else pass "no loader written"; fi
}
