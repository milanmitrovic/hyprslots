// The bar widget's model (BarStatus.js): what the widget shows for the
// engine's state and the workspace its bar's monitor shows, and what its
// right-click menu offers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const B = load("BarStatus.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

function state(extra) {
  return {
    ok: true,
    arrangement: "solo",
    dirty: false,
    workspaces: { 3: { desk: 3, role: "main", monitor: "HEADLESS-2" }, 13: { desk: 3, role: "side", monitor: "DP-1" } },
    ...extra,
  };
}

const running = (extra, workspace = 3) => ({ engine: true, error: "", state: state(extra), workspace });

test("the label is the grid glyph, the active arrangement and the desk on the bar's screen", () => {
  const view = B.view(running());
  assert.equal(view.label, "󰕰 solo · 3");
  assert.equal(view.status, "normal");
  assert.equal(view.desk, 3);
});

test("a workspace that is no desk of the arrangement shows a dash for the desk", () => {
  const view = B.view(running({}, 7));
  assert.equal(view.label, "󰕰 solo · –");
  assert.equal(view.desk, null);
});

test("monitors that run no arrangement say so", () => {
  const view = B.view(running({ arrangement: null, workspaces: {} }));
  assert.equal(view.label, "󰕰 none · –");
  assert.equal(view.arrangement, "");
});

test("unsaved edits add a subtle dot and say so in the tooltip", () => {
  const view = B.view(running({ dirty: true }));
  assert.equal(view.label, "󰕰 solo · 3 •");
  assert.equal(view.status, "dirty");
  assert.equal(view.tooltip, "Hyprslots: solo, desk 3 · unsaved edits\nClick: editor · Right-click: menu");
});

test("the tooltip names the arrangement and desk", () => {
  assert.equal(B.view(running()).tooltip, "Hyprslots: solo, desk 3\nClick: editor · Right-click: menu");
  assert.equal(B.view(running({ arrangement: null }, 7)).tooltip, "Hyprslots: no arrangement for these monitors\nClick: editor · Right-click: menu");
  assert.equal(B.view(running({}, 7)).tooltip, "Hyprslots: solo, workspace 7 is no desk\nClick: editor · Right-click: menu");
});

test("no editor service: an error that says so", () => {
  const view = B.view({ engine: false, error: "", state: null, workspace: 3 });
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 hyprslots");
  assert.equal(view.error, "the milan.hyprslots service is not running");
  assert.equal(view.tooltip, "Hyprslots: the milan.hyprslots service is not running\nClick: editor · Right-click: menu");
});

test("a failed state read (hyprslots not loaded) is an error, even over an older state", () => {
  const missing = "hyprslots did not answer: [string \"return hyprslots.api.state()\"]:1: attempt to index a nil value (global 'hyprslots')";
  const fresh = B.view({ engine: true, error: missing, state: null, workspace: 3 });
  assert.equal(fresh.status, "error");
  assert.equal(fresh.label, "󰕰 hyprslots");
  assert.equal(fresh.error, missing);
  const stale = B.view({ engine: true, error: "hyprctl exited 1: no", state: state(), workspace: 3 });
  assert.equal(stale.status, "error");
  assert.equal(stale.label, "󰕰 solo · 3");
  assert.equal(stale.tooltip, "Hyprslots: hyprctl exited 1: no\nClick: editor · Right-click: menu");
});

test("an engine that refused to run is an error", () => {
  const view = B.view(running({ refused: "hyprmoncfg's workspace planner is on", arrangement: null, workspaces: {} }));
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 off");
  assert.equal(view.error, "hyprslots is off: hyprmoncfg's workspace planner is on");
});

test("a config error is an error; the running config still shows", () => {
  const view = B.view(running({ config_error: "slots.lua:3: unexpected symbol", dirty: true }));
  assert.equal(view.status, "error");
  assert.equal(view.label, "󰕰 solo · 3 •");
  assert.equal(view.error, "config error: slots.lua:3: unexpected symbol");
  assert.equal(view.tooltip, "Hyprslots: config error: slots.lua:3: unexpected symbol\nsolo, desk 3 · unsaved edits\nClick: editor · Right-click: menu");
});

const menuOf = (input) => plain(B.menu(input)).map((item) => `${item.id} ${item.enabled ? "on" : "off"} ${item.label}`);

test("the right-click menu: re-apply and record name the desk, save only with unsaved edits", () => {
  assert.deepEqual(menuOf(running()), [
    "arrange on Re-apply layout (desk 3)",
    "record on Record desk 3…",
    "save off Save",
    "reload on Reload config",
  ]);
  assert.deepEqual(menuOf(running({ dirty: true })).slice(2, 3), ["save on Save"]);
});

test("without a desk, re-apply and record are off", () => {
  assert.deepEqual(menuOf(running({}, 7)), [
    "arrange off Re-apply layout",
    "record off Record desk…",
    "save off Save",
    "reload on Reload config",
  ]);
});

test("a config error still lets the running config be used and the files reloaded", () => {
  assert.deepEqual(menuOf(running({ config_error: "bad", dirty: true })).map((l) => l.split(" ").slice(0, 2).join(" ")), [
    "arrange on",
    "record on",
    "save on",
    "reload on",
  ]);
});

test("an engine that is off or unreachable offers only a reload", () => {
  const states = [
    running({ refused: "planner on", dirty: true }),
    { engine: true, error: "hyprslots did not answer", state: state({ dirty: true }), workspace: 3 },
  ];
  for (const input of states) {
    assert.deepEqual(menuOf(input).map((l) => l.split(" ").slice(0, 2).join(" ")), ["arrange off", "record off", "save off", "reload on"]);
  }
  assert.deepEqual(menuOf({ engine: false, error: "", state: null, workspace: 3 }).map((l) => l.split(" ")[1]), ["off", "off", "off", "off"]);
});

test("re-apply shows the desk again on every screen (as Super+N does), then runs the scroll pass", () => {
  assert.deepEqual(plain(B.calls("arrange", 3)), [
    { name: "desk", args: { desk: 3 } },
    { name: "arrange", args: {} },
  ]);
  assert.deepEqual(plain(B.calls("save", 3)), [{ name: "save", args: {} }]);
  assert.deepEqual(plain(B.calls("reload", null)), [{ name: "reload", args: {} }]);
  assert.deepEqual(plain(B.calls("record", 3)), []);
});

test("each call's outcome in a sentence, a failure in the engine's words", () => {
  assert.equal(B.outcome("arrange", 3, { ok: true, swaps: 0, widened: [] }), "Desk 3 laid out again.");
  assert.equal(B.outcome("save", 3, { ok: true, path: "/c/slots.lua" }), "Saved /c/slots.lua.");
  assert.equal(B.outcome("reload", 3, { ok: true, arrangement: "solo" }), "Reloaded the config; these monitors run solo.");
  assert.equal(B.outcome("reload", 3, { ok: true }), "Reloaded the config; these monitors run no arrangement.");
  assert.equal(B.outcome("save", 3, { ok: false, error: "slots.lua: permission denied" }), "slots.lua: permission denied");
});
