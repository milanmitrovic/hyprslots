// Drag and drop in the Assignment view (Assignment.js): a window's row
// dragged onto a slot row is `a` with that slot; onto the other windows
// (or the list's empty space below the rows) it is `u`; anything else
// cancels.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const A = load("Assignment.js");

const plain = (value) => JSON.parse(JSON.stringify(value));

function window(address, cls, workspaceId, extra) {
  return { address, class: cls, title: cls + " title", workspace_id: workspaceId, floating: false, ...extra };
}

// Workspace 3 lists: main (0xa), right (0xe, by hand), left (Missing),
// mail (empty), then 0xb overflowing main and the unassigned foot 0xd.
function fixture() {
  return {
    ok: true,
    layout: "dual",
    screens: ["HEADLESS-2", "HEADLESS-3"],
    slots: [{ name: "left", key: "l" }, { name: "mail", key: "a" }, { name: "main", key: "m" }, { name: "right", key: "r" }],
    specs: { 3: { left: "t-left", main: "t-main", right: "t-right" } },
    layouts: {
      dual: {
        screens: 2,
        workspaces: {
          3: { 1: { tree: "h[main:2, right]", slots: ["main", "right"] }, 2: { tree: "left", slots: ["left"] } },
        },
      },
    },
    workspaces: { 3: { workspace: 3, screen: 1, monitor: "HEADLESS-2" }, 13: { workspace: 3, screen: 2, monitor: "HEADLESS-3" } },
    assignments: { "0xa": { workspace: 3, slot: "main" }, "0xe": { workspace: 3, slot: "right", manual: true } },
    unassigned: ["0xd"],
    windows: [
      window("0xa", "t-main", 3, { workspace: 3, slot: "main" }),
      window("0xb", "t-main", 3, { overflow: { workspace: 3, slot: "main" } }),
      window("0xd", "foot", 13, { unassigned: true }),
      window("0xe", "t-right", 3, { workspace: 3, slot: "right" }),
    ],
  };
}

const page = (state) => {
  const rows = A.rows(state, 3);
  const by = (slotOrAddress) => rows.find((r) => r.address === slotOrAddress || (!r.address && r.slot === slotOrAddress));
  return { rows, by };
};

test("an unassigned window dropped on an empty slot is a with that slot: the same option a's prompt answers with", () => {
  const state = fixture();
  const { by } = page(state);
  const action = plain(A.dropAction(state, 3, by("0xd"), { row: by("mail") }));
  assert.deepEqual(action, { kind: "assign", label: "Assign to mail",
    option: { key: "a", workspace: 3, slot: "mail", spec: "", holder: null } });
});

test("a window dropped on the slot it is already in does nothing", () => {
  const state = fixture();
  const { by } = page(state);
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), { row: by("0xa") })), { kind: "none" });
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xe"), { row: by("0xe") })), { kind: "none" }, "by hand, too");
});

test("a window in a slot dropped on another slot's window moves there, the holder named for a to displace", () => {
  const state = fixture();
  const { by } = page(state);
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xe"), { row: by("0xa") })), { kind: "assign", label: "Assign to main",
    option: { key: "m", workspace: 3, slot: "main", spec: "t-main", holder: "0xa" } });
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), { row: by("left") })), { kind: "assign", label: "Assign to left",
    option: { key: "l", workspace: 3, slot: "left", spec: "t-left", holder: null } }, "onto a Missing slot");
});

test("a window in a slot dropped on the other windows, or the empty space below the rows, is u: out, and the workspace's spec with it", () => {
  const state = fixture();
  const { by } = page(state);
  const want = { kind: "unassign", label: "Unassign",
    plan: { address: "0xa", clearSpec: true, question: "Unassign t-main from main on workspace 3? The slot is left empty." } };
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), { others: true })), want, "the empty space");
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), { row: by("0xd") })), want, "a stray's row");
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), { row: by("0xb") })), want, "an overflowing window's row");
  delete state.specs[3].right;
  assert.equal(plain(A.dropAction(state, 3, by("0xe"), { others: true })).plan.clearSpec, false,
    "a slot the workspace has no spec for: only the window out, as u");
});

test("a window in no slot dropped on the other windows does nothing: it is one of them already", () => {
  const state = fixture();
  const { by } = page(state);
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xd"), { others: true })), { kind: "none" }, "unassigned");
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xb"), { row: by("0xd") })), { kind: "none" }, "overflowing");
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xd"), { row: by("0xd") })), { kind: "none" }, "onto itself");
});

test("let go anywhere else, or with no window dragged, nothing happens", () => {
  const state = fixture();
  const { by } = page(state);
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xd"), null)), { kind: "none" }, "outside the list");
  assert.deepEqual(plain(A.dropAction(state, 3, by("0xa"), null)), { kind: "none" }, "outside the list, from a slot");
  assert.deepEqual(plain(A.dropAction(state, 3, by("left"), { row: by("mail") })), { kind: "none" }, "a Missing row is no window");
  assert.deepEqual(plain(A.dropAction(state, 3, by("mail"), { others: true })), { kind: "none" }, "nor an empty one");
  assert.deepEqual(plain(A.dropAction(state, 3, null, { row: by("mail") })), { kind: "none" }, "no source");
});

test("only a row with a window drags", () => {
  const { rows, by } = page(fixture());
  assert.deepEqual(plain(rows.map((r) => A.canDrag(r))), [true, true, false, false, true, true]);
  assert.equal(A.canDrag(null), false);
  assert.equal(A.canDrag(by("0xd")), true, "a stray");
});

test("a press becomes a drag once the pointer has moved 6 px from it, in any direction; a click's jitter does not", () => {
  assert.equal(A.dragBegins(100, 100, 103, 102), false, "3, 2 px: still a click");
  assert.equal(A.dragBegins(100, 100, 105, 100), false, "5 px");
  assert.equal(A.dragBegins(100, 100, 106, 100), true, "6 px across");
  assert.equal(A.dragBegins(100, 100, 100, 94), true, "6 px up");
  assert.equal(A.dragBegins(100, 100, 105, 105), true, "7 px on the diagonal");
});
