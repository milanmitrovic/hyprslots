// The bar widget's model (BarStatus.js): what the widget shows for the
// engine's state and the workspace its bar's monitor shows, and what its
// right-click menu offers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const B = load("BarStatus.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Desk laptop uses layout solo (2 screens), which office shares; workspace 3
// has a tree on screen 1 only.
function state(extra) {
  return {
    ok: true,
    desk: "laptop",
    layout: "solo",
    dirty: false,
    desks: { laptop: { layout: "solo", active: true }, office: { layout: "solo", active: false } },
    layouts: { solo: { screens: 2, used_by: ["laptop", "office"], workspaces: { 3: { 1: { tree: "main" } } } } },
    workspaces: { 3: { workspace: 3, screen: 1, monitor: "HEADLESS-2" }, 13: { workspace: 3, screen: 2, monitor: "DP-1" } },
    ...extra,
  };
}

const running = (extra, workspaceId = 3) => ({ engine: true, error: "", state: state(extra), workspaceId });
const HINT = "Click: editor · Right-click: menu";

test("the label is the grid glyph and the active layout's name", () => {
  const view = B.view(running());
  assert.equal(view.label, "󰕰 solo");
  assert.equal(view.status, "normal");
  assert.equal(view.workspace, 3);
  assert.equal(view.desk, "laptop");
});

test("the label names no desk or workspace, whatever the bar's screen shows", () => {
  assert.equal(B.view(running({}, 7)).label, "󰕰 solo", "a workspace id the desk does not manage");
  assert.equal(B.view(running({}, 7)).workspace, null);
  const side = B.view(running({}, 13));
  assert.equal(side.label, "󰕰 solo", "workspace 3 has no tree on screen 2");
  assert.equal(side.workspace, 3, "it is still workspace 3, to re-apply");
});

test("monitors with no desk (no layout) say none", () => {
  const view = B.view(running({ desk: null, layout: null, workspaces: {} }));
  assert.equal(view.label, "󰕰 none");
  assert.equal(view.desk, "");
});

test("unsaved edits add a subtle dot and say so in the tooltip", () => {
  const view = B.view(running({ dirty: true }));
  assert.equal(view.label, "󰕰 solo •");
  assert.equal(view.status, "dirty");
  assert.equal(view.tooltip, "Hyprslots: desk laptop, workspace 3 · unsaved edits\nLayout: solo (also used by: office)\n" + HINT);
});

test("the tooltip names the desk, the workspace and the layout, and the desks sharing it", () => {
  assert.equal(B.view(running()).tooltip, "Hyprslots: desk laptop, workspace 3\nLayout: solo (also used by: office)\n" + HINT);
  const alone = running();
  alone.state.layouts.solo.used_by = ["laptop"];
  assert.equal(B.view(alone).tooltip, "Hyprslots: desk laptop, workspace 3\nLayout: solo\n" + HINT);
  assert.equal(B.view(running({ desk: null, layout: null }, 7)).tooltip, "Hyprslots: no desk for these monitors\n" + HINT);
  assert.equal(B.view(running({}, 7)).tooltip, "Hyprslots: desk laptop, workspace 7 has no tree\nLayout: solo (also used by: office)\n" + HINT);
  assert.equal(B.view(running({}, 13)).tooltip,
    "Hyprslots: desk laptop, workspace 3 has no tree on this screen\nLayout: solo (also used by: office)\n" + HINT);
});

test("no editor service: an error that says so", () => {
  const view = B.view({ engine: false, error: "", state: null, workspaceId: 3 });
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 hyprslots");
  assert.equal(view.error, "the io.github.milanmitrovic.hyprslots service is not running");
  assert.equal(view.tooltip, "Hyprslots: the io.github.milanmitrovic.hyprslots service is not running\nClick: editor · Right-click: menu");
});

test("a failed state read (hyprslots not loaded) is an error, even over an older state", () => {
  const missing = "hyprslots did not answer: [string \"return hyprslots.api.state()\"]:1: attempt to index a nil value (global 'hyprslots')";
  const fresh = B.view({ engine: true, error: missing, state: null, workspaceId: 3 });
  assert.equal(fresh.status, "error");
  assert.equal(fresh.label, "󰕰 hyprslots");
  assert.equal(fresh.error, missing);
  const stale = B.view({ engine: true, error: "hyprctl exited 1: no", state: state(), workspaceId: 3 });
  assert.equal(stale.status, "error");
  assert.equal(stale.label, "󰕰 solo");
  assert.equal(stale.tooltip, "Hyprslots: hyprctl exited 1: no\nClick: editor · Right-click: menu");
});

test("an engine not enabled yet asks to be, as a quiet set-up nudge, not an error", () => {
  const absent = { engine: true, error: "the hyprslots engine is not running", absent: true, loadError: "", workspaceId: 3 };
  for (const view of [B.view({ ...absent, state: null }), B.view({ ...absent, state: state() })]) {
    assert.equal(view.status, "setup");
    assert.equal(view.setup, true);
    assert.equal(view.label, "󰕰 enable");
    assert.equal(view.error, "");
    assert.equal(view.tooltip, "Hyprslots: the engine is not enabled\nClick to enable it");
  }
  assert.deepEqual(menuOf({ ...absent, state: state() }).map((line) => line.split(" ").slice(0, 2).join(" ")),
    ["arrange off", "record off", "capture off", "save off", "reload off"]);
});

test("an engine that failed to load is an error that says why", () => {
  const view = B.view({ engine: true, error: "the hyprslots engine failed to load: boom", absent: true, loadError: "boom",
    state: null, workspaceId: 3 });
  assert.equal(view.status, "error");
  assert.equal(view.setup, false);
  assert.equal(view.error, "the hyprslots engine failed to load: boom");
});

test("an engine that refused to run is an error", () => {
  const view = B.view(running({ refused: "hyprmoncfg's workspace planner is on", desk: null, layout: null, workspaces: {} }));
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 off");
  assert.equal(view.error, "hyprslots is off: hyprmoncfg's workspace planner is on");
});

test("a config error is an error; the running config still shows", () => {
  const view = B.view(running({ config_error: "slots.lua:3: unexpected symbol", dirty: true }));
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 solo •");
  assert.equal(view.error, "config error: slots.lua:3: unexpected symbol");
  assert.equal(view.tooltip, "Hyprslots: config error: slots.lua:3: unexpected symbol\ndesk laptop, workspace 3 · unsaved edits\nLayout: solo (also used by: office)\n" + HINT);
});

const menuOf = (input) => plain(B.menu(input)).map((item) => `${item.id} ${item.enabled ? "on" : "off"} ${item.label}`);

test("the right-click menu: re-apply and record name the workspace, save only with unsaved edits", () => {
  assert.deepEqual(menuOf(running()), [
    "arrange on Re-apply layout (workspace 3)",
    "record on Record workspace 3…",
    "capture on Capture this workspace…",
    "save off Save",
    "reload on Reload config",
  ]);
  assert.deepEqual(menuOf(running({ dirty: true })).slice(3, 4), ["save on Save"]);
});

test("without a workspace, re-apply and record are off", () => {
  assert.deepEqual(menuOf(running({}, 7)), [
    "arrange off Re-apply layout",
    "record off Record workspace…",
    "capture off Capture this workspace…",
    "save off Save",
    "reload on Reload config",
  ]);
});

test("a config error still lets the running config be used and the files reloaded", () => {
  assert.deepEqual(menuOf(running({ config_error: "bad", dirty: true })).map((l) => l.split(" ").slice(0, 2).join(" ")), [
    "arrange on",
    "record on",
    "capture on",
    "save on",
    "reload on",
  ]);
});

test("an engine that is off or unreachable offers only a reload", () => {
  const states = [
    running({ refused: "planner on", dirty: true }),
    { engine: true, error: "hyprslots did not answer", state: state({ dirty: true }), workspaceId: 3 },
  ];
  for (const input of states) {
    assert.deepEqual(menuOf(input).map((l) => l.split(" ").slice(0, 2).join(" ")), ["arrange off", "record off", "capture off", "save off", "reload on"]);
  }
  assert.deepEqual(menuOf({ engine: false, error: "", state: null, workspaceId: 3 }).map((l) => l.split(" ")[1]), ["off", "off", "off", "off", "off"]);
});

test("re-apply shows the workspace again on every screen (as Super+N does), then runs the scroll pass", () => {
  assert.deepEqual(plain(B.calls("arrange", 3)), [
    { name: "workspace", args: { workspace: 3 } },
    { name: "arrange", args: {} },
  ]);
  assert.deepEqual(plain(B.calls("save", 3)), [{ name: "save", args: {} }]);
  assert.deepEqual(plain(B.calls("reload", null)), [{ name: "reload", args: {} }]);
  assert.deepEqual(plain(B.calls("record", 3)), []);
  assert.deepEqual(plain(B.calls("capture", 3)), [], "capture opens the panel's capture flow instead");
});

test("each call's outcome in a sentence, a failure in the engine's words", () => {
  assert.equal(B.outcome("arrange", 3, { ok: true, swaps: 0, widened: [] }), "Workspace 3 laid out again.");
  assert.equal(B.outcome("save", 3, { ok: true, path: "/c/slots.lua" }), "Saved.", "no file names");
  assert.equal(B.outcome("reload", 3, { ok: true, desk: "laptop", layout: "solo" }),
    "Reloaded the config; desk laptop runs layout solo.");
  assert.equal(B.outcome("reload", 3, { ok: true }), "Reloaded the config; these monitors have no desk.");
  assert.equal(B.outcome("save", 3, { ok: false, error: "slots.lua: permission denied" }), "slots.lua: permission denied");
});

test("the tooltip names the monitor the workspace is on by its display name", () => {
  const monitors = [{ name: "HEADLESS-2", display: "Built-in" }, { name: "DP-1", display: "Odyssey G95NC" }];
  assert.equal(B.view(running({ monitors })).tooltip,
    "Hyprslots: desk laptop, workspace 3 on Built-in\nLayout: solo (also used by: office)\n" + HINT);
  assert.equal(B.view(running({ monitors }, 13)).tooltip,
    "Hyprslots: desk laptop, workspace 3 on Odyssey G95NC has no tree on this screen\nLayout: solo (also used by: office)\n" + HINT);
});

test("with zero slots the widget asks to be set up, quietly", () => {
  const view = B.view(running({ slots: [], dirty: true }));
  assert.equal(view.status, "setup");
  assert.equal(view.label, "󰕰 set up", "no unsaved dot: there is nothing of yours to save yet");
  assert.equal(view.setup, true);
  assert.equal(view.tooltip, "Hyprslots: no slots yet\nClick to set up your slots");
});

test("the set-up state goes once a slot exists", () => {
  const view = B.view(running({ slots: [{ name: "main", key: "m" }] }));
  assert.equal(view.status, "normal");
  assert.equal(view.label, "󰕰 solo");
  assert.equal(view.setup, false);
});

test("an error wins over the set-up state", () => {
  const view = B.view(running({ slots: [], config_error: "config.lua:1: oops" }));
  assert.equal(view.status, "error");
  assert.equal(view.setup, false);
  assert.equal(B.view({ engine: true, error: "", state: null, workspaceId: 3 }).setup, false, "nothing read yet");
});

test("with zero slots Capture is offered and Record is not: capture makes the slots, record needs them", () => {
  assert.deepEqual(menuOf(running({ slots: [] })).map((l) => l.split(" ").slice(0, 2).join(" ")),
    ["arrange on", "record off", "capture on", "save off", "reload on"]);
  assert.deepEqual(menuOf(running({ slots: [{ name: "main", key: "m" }] })).map((l) => l.split(" ").slice(0, 2).join(" ")),
    ["arrange on", "record on", "capture on", "save off", "reload on"]);
});

test("Capture opens the panel with { capture: true }, as Record does with { record: true }", () => {
  assert.deepEqual(plain(B.summon("capture")), { capture: true });
  assert.deepEqual(plain(B.summon("record")), { record: true });
  assert.equal(B.summon("save"), null, "the other entries call the engine");
});
