// Launching apps in the editor (Launch.js): a workspace's launch setting
// on its Assignment page, cycled by key; each slot's command status while
// the workspace launches; Launch missing's reply in a sentence.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const L = load("Launch.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// The api's state (lua/hyprslots/api.lua launch_info): every managed
// workspace's setting, and the slots' commands where it is not never.
function state(extra) {
  return {
    launch: { 1: "never", 2: "on_demand", 3: "at_login" },
    launch_status: {
      2: {
        main: { command: "foot --app-id=t-term", source: "desktop", desktop: "t-term" },
        notes: { reason: "can't launch: set a command" },
        web: { command: "firefox -P work", source: "config" },
      },
      3: {},
    },
    config: { editable: true, read_only: [] },
    ...extra,
  };
}

test("each workspace's setting in plain words, never by default", () => {
  assert.equal(L.mode(state(), 2), "on_demand");
  assert.equal(L.mode(state(), 7), "never", "a workspace the state leaves out");
  assert.equal(L.mode(null, 1), "never");
  assert.equal(L.line(state(), 1), "Launch apps: never");
  assert.equal(L.line(state(), 2), "Launch apps: on demand");
  assert.equal(L.line(state(), 3), "Launch apps: at login");
});

test("m cycles never, on demand, at login", () => {
  assert.equal(L.next("never"), "on_demand");
  assert.equal(L.next("on_demand"), "at_login");
  assert.equal(L.next("at_login"), "never");
  assert.equal(L.next("bogus"), "on_demand");
});

test("a setting config.lua sets in code is read only, and the line says so", () => {
  const all = state({ config: { editable: true, read_only: ["launch"] } });
  assert.equal(L.readOnly(all, 2), true);
  const one = state({ config: { editable: true, read_only: ["launch.3"] } });
  assert.equal(L.readOnly(one, 3), true);
  assert.equal(L.readOnly(one, 2), false);
  assert.equal(L.readOnly(state({ config: { editable: false } }), 2), true, "no editor data at all");
  assert.equal(L.line(one, 3), "Launch apps: at login (set in your config)");
});

test("what setting it says once set", () => {
  assert.equal(L.setText({ workspace: 2, mode: "on_demand" }),
    "Workspace 2 launches its missing apps when you press L. Ctrl+S saves.");
  assert.equal(L.setText({ workspace: 2, mode: "at_login" }),
    "Workspace 2 launches its missing apps at login, and when you press L. Ctrl+S saves.");
  assert.equal(L.setText({ workspace: 2, mode: "never" }), "Workspace 2 launches no apps. Ctrl+S saves.");
});

test("a slot's command status shows only where the workspace launches", () => {
  assert.equal(L.shows(state(), 1), false);
  assert.equal(L.shows(state(), 2), true);
  assert.equal(L.status(state(), 1, "main"), null);
  assert.deepEqual(plain(L.status(state(), 2, "main")), { text: "foot --app-id=t-term", urgent: false });
  assert.deepEqual(plain(L.status(state(), 2, "web")), { text: "firefox -P work (from your config)", urgent: false });
  assert.deepEqual(plain(L.status(state(), 2, "notes")), { text: "can't launch: set a command", urgent: true });
  assert.equal(L.status(state(), 2, "chat"), null, "a slot the workspace has no app for");
});

test("Launch missing is for a workspace that launches", () => {
  assert.equal(L.canLaunch(state(), 1), false);
  assert.equal(L.canLaunch(state(), 2), true);
  assert.equal(L.canLaunch(state(), 3), true);
});

test("Launch missing's reply in a sentence: what launched, what can't", () => {
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [{ slot: "main", command: "/usr/bin/foot --server" }],
    open: [], pending: [], cannot: [{ slot: "notes", reason: "can't launch: set a command" }] })),
  { text: "Launched foot for main; can't launch notes: set a command.", error: false });
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [{ slot: "main", command: "foot" }, { slot: "web", command: "firefox -P work" }],
    open: ["chat"], pending: [], cannot: [] })),
  { text: "Launched foot for main, firefox for web.", error: false });
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [], open: [], pending: ["main"], cannot: [] })),
    { text: "The app for main is on the way already.", error: false });
  // open[]: slots whose app is open elsewhere already (no slot holds its
  // window); a slot its window fills is not listed at all.
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [], open: ["main"], pending: [], cannot: [] })),
    { text: "Nothing to launch on workspace 2: the app for main is open already.", error: false });
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [], open: ["main", "web"], pending: [], cannot: [] })),
    { text: "Nothing to launch on workspace 2: the apps for main, web are open already.", error: false });
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [], open: [], pending: [], cannot: [] })),
    { text: "Nothing to launch on workspace 2: no empty slot there waits for an app.", error: false },
    "every slot with an app filled, or none with one");
  assert.deepEqual(plain(L.missingText({ workspace: 2, launched: [], open: [], pending: [], cannot: [{ slot: "notes", reason: "can't launch: set a command" }] })),
    { text: "Can't launch notes: set a command.", error: true });
});

test("the page's launch keys: m cycles the setting (dim where it is code's), L launches (dim while never)", () => {
  assert.deepEqual(plain(L.helpItems(state(), 2)), [{ key: "m", label: "launch mode" }, { key: "L", label: "launch missing" }]);
  assert.deepEqual(plain(L.helpItems(state(), 1)),
    [{ key: "m", label: "launch mode" }, { key: "L", label: "launch missing", enabled: false }]);
  assert.deepEqual(plain(L.helpItems(state({ config: { editable: true, read_only: ["launch.2"] } }), 2)),
    [{ key: "m", label: "launch mode", enabled: false }, { key: "L", label: "launch missing" }]);
  assert.deepEqual(plain(L.helpItems(null, 2)).map((i) => i.enabled), [false, false], "no state read yet");
});
