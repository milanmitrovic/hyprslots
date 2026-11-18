# Installing and removing the engine from the command line: a fresh install
# as `omarchy plugin add` leaves it (the plugin folder a copy of the repo, no
# loader in Omarchy's workspace-layouts folder) runs no engine;
# tools/install-engine.sh puts the loader there, reloads Hyprland and finds
# the engine running, Super+1 bound by hyprslots; tools/uninstall-engine.sh
# takes the loader away again and the engine with it. With the plugin removed
# the loader removes itself; with no plugin installed install-engine.sh
# refuses and writes nothing. With --keys the loader binds the editor's keys
# where they are free (Super+Ctrl+Y is bound already here, so only
# Super+Ctrl+Shift+C is), with --menu the Omarchy menu file gets hyprslots'
# three entries (which Omarchy's own parser reads); uninstalling, or the
# loader going with the plugin, takes both away.
#
# Screen: HEADLESS-2, 1920x1080, Omarchy block 0.

test_setup() {
  cat >"$E2E_CONFIG_HOME/hypr/test-extra.lua" <<'LUA'
hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x0", scale = 1 })
-- The user's own key there already.
hl.bind("SUPER + CTRL + Y", hl.dsp.exec_cmd("true"), { description = "Mine" })
LUA
  mkdir -p "$E2E_CONFIG_HOME/omarchy/extensions"
  printf '{\n  // mine\n  "mine": {"label":"Mine","action":"true"}\n}\n' >"$E2E_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
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

# The editor's keys the loader bound: "<modmask> <key> <description>" lines.
editor_keys() {
  hc binds -j | jq -r '.[] | select((.description // "") | startswith("Hyprslots:")) | "\(.modmask) \(.key | ascii_downcase) \(.description)"' | sort
}

MENU_FILE=$E2E_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc

# The labels of the menu rows Omarchy's own parser reads from the user's menu
# file, sorted, one per line (MenuModel.js under node).
menu_labels() {
  node --input-type=module -e '
    import fs from "node:fs"; import vm from "node:vm";
    const src = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma.*$/m, "");
    const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);
    const rows = ctx.parseMenuJsonc(fs.readFileSync(process.argv[2], "utf8")) || [];
    console.log(rows.map(r => r.label).sort().join("\n"));' \
    /usr/share/omarchy/shell/plugins/menu/MenuModel.js "$MENU_FILE"
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

  # With the editor's keys and the Omarchy menu.
  out=$("$E2E_PLUGIN_DIR/tools/install-engine.sh" --keys --menu 2>&1)
  status=$?
  log "install-engine.sh --keys --menu: $out"
  expect_eq "install-engine.sh --keys --menu succeeds" 0 "$status"
  expect_eq "the engine runs with them" running "$(engine)"
  expect_eq "the capture key is bound, the user's Super+Ctrl+Y left alone" \
    "69 c Hyprslots: capture this workspace" "$(editor_keys)"
  if [[ $out == *"Super+Ctrl+Y is bound already (Mine): left as it is."* && $out == *"Super+Ctrl+Shift+C: capture this workspace."* ]]; then
    pass "it says which key it bound and which it left"
  else
    fail "install-engine.sh --keys said: $out"
  fi
  if command -v node >/dev/null && [[ -f /usr/share/omarchy/shell/plugins/menu/MenuModel.js ]]; then
    expect_eq "Omarchy's menu reads the user's entry and hyprslots' three" \
      "Mine|hyprslots: Capture this workspace|hyprslots: Launch missing apps|hyprslots: Open editor" \
      "$(menu_labels | paste -sd '|')"
  else
    log "no node or no Omarchy menu here: the menu file is not parsed"
  fi
  expect_eq "menu-entries.sh says so" installed "$("$E2E_PLUGIN_DIR/tools/menu-entries.sh" status)"

  # Installed again without saying: the keys stay.
  "$E2E_PLUGIN_DIR/tools/install-engine.sh" >/dev/null 2>&1
  expect_eq "a plain install keeps the keys" "69 c Hyprslots: capture this workspace" "$(editor_keys)"
  "$E2E_PLUGIN_DIR/tools/install-engine.sh" --no-keys >/dev/null 2>&1
  expect_eq "--no-keys takes them away" "" "$(editor_keys)"
  "$E2E_PLUGIN_DIR/tools/install-engine.sh" --keys >/dev/null 2>&1

  # When it is uninstalled.
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1)
  status=$?
  log "uninstall-engine.sh: $out"
  expect_eq "uninstall-engine.sh succeeds" 0 "$status"
  if [[ -e $E2E_LOADER ]]; then fail "the loader is still there"; else pass "the loader is gone"; fi
  expect_eq "the engine is gone" "absent nil" "$(engine)"
  expect_eq "Super+1 is not hyprslots' any more" "not hyprslots" "$(super_1)"
  expect_eq "nor are the editor's keys" "" "$(editor_keys)"
  expect_eq "and the menu entries are gone, the user's kept" \
    $'{\n  // mine\n  "mine": {"label":"Mine","action":"true"},\n}' "$(cat "$MENU_FILE")"
  out=$("$E2E_PLUGIN_DIR/tools/uninstall-engine.sh" 2>&1)
  expect_eq "uninstalling again succeeds" 0 "$?"

  # The plugin removed with the loader in place: the loader goes with it.
  "$E2E_PLUGIN_DIR/tools/install-engine.sh" --menu >/dev/null 2>&1
  expect_eq "installed again" running "$(engine)"
  rm -rf "$E2E_PLUGIN_DIR"
  hc reload >/dev/null
  eventually 5 bash -c "[[ ! -e '$E2E_LOADER' ]]"
  if [[ -e $E2E_LOADER ]]; then fail "the loader outlived the plugin"; else pass "the loader removed itself with the plugin"; fi
  expect_eq "and the menu entries with it" missing "$(grep -q 'hyprslots' "$MENU_FILE" && echo present || echo missing)"
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
