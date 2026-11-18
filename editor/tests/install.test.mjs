// Enabling the engine from the editor (Install.js): what the panel asks
// while no engine runs, the script its Enable runs, and what that run says.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const I = load("Install.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("an engine that runs asks nothing", () => {
  assert.equal(I.prompt({ absent: false, loadError: "", stale: false, enabling: false, error: "" }), null);
});

test("no engine and nothing read yet: the whole page asks to enable it, saying what that writes and what it leaves alone", () => {
  const p = plain(I.prompt({ absent: true, loadError: "", stale: false, enabling: false, error: "" }));
  assert.equal(p.mode, "card");
  assert.equal(p.title, "Enable the hyprslots engine?");
  assert.deepEqual(p.lines, [
    "hyprslots puts your windows into their slots from inside Hyprland. Enabling it adds one file, zz-hyprslots.lua, to Omarchy's workspace-layouts folder (~/.local/state/omarchy/workspace-layouts), which Omarchy loads with its own saved layouts, and reloads Hyprland.",
    "It doesn't edit your Hyprland config. Super+1..9 then switch every screen at once. To undo, run ~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/uninstall-engine.sh.",
  ]);
  assert.deepEqual(p.action, { key: "e", label: "Enable" });
  assert.equal(p.busy, false);
  assert.equal(p.error, "");
});

test("no engine over a state read before: a banner over the stale views", () => {
  const p = plain(I.prompt({ absent: true, loadError: "", stale: true, enabling: false, error: "" }));
  assert.equal(p.mode, "banner");
  assert.equal(p.title, "The hyprslots engine is not running: what shows here is from before.");
  assert.deepEqual(p.lines, ["Enable it? That adds one file to Omarchy's workspace-layouts folder and reloads Hyprland; your Hyprland config is not edited."]);
  assert.deepEqual(p.action, { key: "e", label: "Enable" });
});

test("an engine that failed to load says why and offers to try again", () => {
  const p = plain(I.prompt({ absent: true, loadError: "no engine in /p", stale: false, enabling: false, error: "" }));
  assert.equal(p.mode, "card");
  assert.equal(p.title, "The hyprslots engine failed to load");
  assert.deepEqual(p.lines, ["no engine in /p", "Fix that, then try again: it reloads Hyprland."]);
  assert.deepEqual(p.action, { key: "e", label: "Try again" });
});

test("while it enables, the action waits; a failed run's error shows", () => {
  const busy = plain(I.prompt({ absent: true, loadError: "", stale: false, enabling: true, error: "" }));
  assert.equal(busy.busy, true);
  assert.deepEqual(busy.action, { key: "e", label: "Enabling…" });
  const failed = plain(I.prompt({ absent: true, loadError: "", stale: false, enabling: false, error: "the plugin is not installed" }));
  assert.equal(failed.error, "the plugin is not installed");
});

test("Enable runs the plugin's own tools/install-engine.sh, a path from the editor's file URL", () => {
  assert.deepEqual(Array.from(I.enableCommand("file:///home/u/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/install-engine.sh")),
    ["bash", "/home/u/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/install-engine.sh"]);
  assert.deepEqual(Array.from(I.enableCommand("file:///tmp/with%20space/tools/install-engine.sh")),
    ["bash", "/tmp/with space/tools/install-engine.sh"]);
});

test("a run's outcome: its last line when it worked, its error output when not", () => {
  assert.deepEqual(plain(I.outcome(0, "Installed the hyprslots loader: /x\nReloaded Hyprland: the hyprslots engine is running.\n", "")),
    { ok: true, message: "Reloaded Hyprland: the hyprslots engine is running." });
  assert.deepEqual(plain(I.outcome(1, "Installed the hyprslots loader: /x\n",
    "install-engine.sh: the loader is in place, but the engine did not start: boom\n")),
  { ok: false, message: "the loader is in place, but the engine did not start: boom" });
  assert.deepEqual(plain(I.outcome(127, "", "")), { ok: false, message: "tools/install-engine.sh failed (exit 127)" });
});

test("the help row while it asks: enable, the two choices, the tabs, close", () => {
  assert.deepEqual(plain(I.helpGroups()), [
    [{ key: "e", label: "enable" }],
    [{ key: "k", label: "keys" }, { key: "m", label: "menu" }],
    [{ key: "Tab", label: "view" }, { key: "q", label: "close" }],
  ]);
});

test("it offers two choices: the editor's keys (off unless asked) and Omarchy's menu (on)", () => {
  const p = plain(I.prompt({ absent: true, loadError: "", stale: false, enabling: false, error: "", options: I.defaults() }));
  assert.deepEqual(p.options, [
    { id: "keys", key: "k", label: "Also bind Super+Ctrl+Y to open the editor and Super+Ctrl+Shift+C to capture", checked: false },
    { id: "menu", key: "m", label: "Add hyprslots to the Omarchy menu (Open editor, Capture this workspace, Launch missing apps)", checked: true },
  ]);
  const banner = plain(I.prompt({ absent: true, loadError: "", stale: true, enabling: false, error: "", options: { keys: true, menu: false } }));
  assert.deepEqual(banner.options.map((o) => o.checked), [true, false], "the banner offers them too, as chosen");
  const missing = plain(I.prompt({ absent: true, loadError: "", stale: false, enabling: false, error: "" }));
  assert.deepEqual(missing.options.map((o) => o.checked), [false, true], "the defaults when none are given");
});

test("k and m toggle the choices; any other key changes nothing", () => {
  assert.deepEqual(plain(I.toggle({ keys: false, menu: true }, "k")), { keys: true, menu: true });
  assert.deepEqual(plain(I.toggle({ keys: true, menu: true }, "m")), { keys: true, menu: false });
  assert.deepEqual(plain(I.toggle({ keys: true, menu: false }, "x")), { keys: true, menu: false });
  assert.equal(I.toggles("k"), true);
  assert.equal(I.toggles("m"), true);
  assert.equal(I.toggles("e"), false);
});

test("Enable passes the choices on to the script: --keys and --menu where chosen", () => {
  const url = "file:///p/tools/install-engine.sh";
  assert.deepEqual(Array.from(I.enableCommand(url, { keys: false, menu: true })), ["bash", "/p/tools/install-engine.sh", "--menu"]);
  assert.deepEqual(Array.from(I.enableCommand(url, { keys: true, menu: true })), ["bash", "/p/tools/install-engine.sh", "--keys", "--menu"]);
  assert.deepEqual(Array.from(I.enableCommand(url, { keys: true, menu: false })), ["bash", "/p/tools/install-engine.sh", "--keys"]);
  assert.deepEqual(Array.from(I.enableCommand(url, { keys: false, menu: false })), ["bash", "/p/tools/install-engine.sh"]);
});

test("success says what the script did about the keys and the menu, then its last line", () => {
  const out = "Installed the hyprslots loader: /x\n"
    + "Super+Ctrl+Y is bound already (Hyprslots): left as it is\n"
    + "Bound Super+Ctrl+Shift+C: capture this workspace\n"
    + "Added 3 entries to the Omarchy menu\n"
    + "Reloaded Hyprland: the hyprslots engine is running.\n";
  assert.deepEqual(plain(I.outcome(0, out, "")), { ok: true, message:
    "Super+Ctrl+Y is bound already (Hyprslots): left as it is. Bound Super+Ctrl+Shift+C: capture this workspace."
    + " Added 3 entries to the Omarchy menu. Reloaded Hyprland: the hyprslots engine is running." });
});
