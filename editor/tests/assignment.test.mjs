// The Assignment view's model (Assignment.js): which rows a desk shows, in
// what order, and which slots `a` offers, from an api `state` reply.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const A = load("Assignment.js");
const P = load("Prompts.js");

// Plain copies, so deepEqual does not trip over the vm context's prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value));

function window(address, cls, workspace, extra) {
  return { address, class: cls, title: cls + " title", workspace, floating: false, ...extra };
}

// dual: big = h[main:2, right:1], side = left; desk 4 has one slot on big.
function fixture() {
  return {
    ok: true,
    arrangement: "dual",
    desks: [3, 4],
    slots: [{ name: "left" }, { name: "mail" }, { name: "main" }, { name: "right" }],
    specs: { 3: { left: "t-left", main: "t-main", right: "t-right" }, 4: { mail: "thunderbird" } },
    arrangements: {
      dual: {
        roles: ["big", "side"],
        active: true,
        desks: {
          3: { big: { tree: "h[main:2, right]", slots: ["main", "right"] }, side: { tree: "left", slots: ["left"] } },
          4: { big: { tree: "mail", slots: ["mail"] } },
        },
      },
    },
    workspaces: { 3: { desk: 3, role: "big" }, 13: { desk: 3, role: "side" }, 4: { desk: 4, role: "big" } },
    assignments: { "0xa": { desk: 3, slot: "main" }, "0xe": { desk: 3, slot: "right", manual: true } },
    overflow: { "0xb": { desk: 3, slot: "main" } },
    unassigned: ["0xd"],
    windows: [
      window("0xa", "t-main", 3, { desk: 3, slot: "main" }),
      window("0xb", "t-main", 3, { overflow: { desk: 3, slot: "main" } }),
      window("0xc", "firefox", 1),
      window("0xd", "foot", 13, { unassigned: true }),
      window("0xe", "t-right", 3, { desk: 3, slot: "right" }),
    ],
  };
}

const summary = (rows) => plain(rows).map((r) => [r.status, r.slot || "", r.address]);

test("pages are every window, then each desk", () => {
  assert.deepEqual(plain(A.pages(fixture())), [
    { desk: null, label: "All windows" },
    { desk: 3, label: "Desk 3" },
    { desk: 4, label: "Desk 4" },
  ]);
});

test("a desk lists its slots in tree order, screen by screen, a missing window as a placeholder, then overflow and strays", () => {
  assert.deepEqual(summary(A.rows(fixture(), 3)), [
    ["slot", "main", "0xa"],
    ["manual", "right", "0xe"],
    ["missing", "left", null],
    ["overflow", "main", "0xb"],
    ["unassigned", "", "0xd"],
  ]);
});

test("rows say which screen each slot or window is on", () => {
  const roles = plain(A.rows(fixture(), 3)).map((r) => r.role);
  assert.deepEqual(roles, ["big", "big", "side", "big", "side"]);
});

test("every window lists slotted ones by desk and tree order, then overflow, then the rest by workspace", () => {
  assert.deepEqual(summary(A.rows(fixture(), null)), [
    ["slot", "main", "0xa"],
    ["manual", "right", "0xe"],
    ["overflow", "main", "0xb"],
    ["none", "", "0xc"],
    ["unassigned", "", "0xd"],
  ]);
});

test("the slot column reads like the TUI's", () => {
  const text = plain(A.rows(fixture(), 3)).map((r) => A.slotText(r));
  assert.deepEqual(text, ["main", "right (by hand)", "left", "overflow (main)", "unassigned"]);
  assert.equal(A.slotText({ status: "none" }), "—");
});

test("a slot the desk has a spec for but no tree of the active arrangement shows is still listed, after the shown ones", () => {
  const state = fixture();
  state.slots.push({ name: "spare" });
  state.specs[3].spare = "t-spare";
  assert.deepEqual(summary(A.rows(state, 3)).map((r) => r[1]), ["main", "right", "left", "spare", "main", ""]);
});

test("a slot a tree places but the desk has no spec for is Missing with no spec: only a by-hand window fills it", () => {
  const state = fixture();
  state.arrangements.dual.desks[4].big = { tree: "h[mail, main]", slots: ["mail", "main"] };
  const rows = plain(A.rows(state, 4));
  assert.deepEqual(rows.map((r) => [r.status, r.slot, r.spec]), [
    ["missing", "mail", "thunderbird"],
    ["missing", "main", ""],
  ]);
  assert.equal(A.specText(rows[1]), "(no spec)");
  assert.equal(A.specText(rows[0]), "thunderbird");
});

test("a global slot neither placed nor filled on the desk is no row of it", () => {
  assert.deepEqual(summary(A.rows(fixture(), 4)).map((r) => r[1]), ["mail"]);
});

test("assign offers every global slot on the desk: its own in tree order first, then the rest by name", () => {
  const options = plain(A.slotOptions(fixture(), 3, null));
  assert.deepEqual(options.map((o) => [o.key, o.desk, o.slot, o.spec, o.holder]), [
    ["m", 3, "main", "t-main", "0xa"],
    ["r", 3, "right", "t-right", "0xe"],
    ["l", 3, "left", "t-left", null],
    ["1", 3, "mail", "", null],
  ]);
});

test("a first letter already taken falls back to the first free digit", () => {
  const state = fixture();
  state.slots = [{ name: "main" }, { name: "menu" }, { name: "mail" }];
  state.specs[3] = { main: "a", menu: "b", mail: "c" };
  state.arrangements.dual.desks[3] = { big: { slots: ["main", "menu", "mail"] } };
  assert.deepEqual(plain(A.slotOptions(state, 3, null)).map((o) => o.key), ["m", "1", "2"]);
});

test("on the every-window page, assign offers the window's desk, else the focused desk, else nothing", () => {
  const state = fixture();
  const rows = A.rows(state, null);
  const onDesk = rows.find((r) => r.address === "0xd");
  const stray = rows.find((r) => r.address === "0xc");
  assert.deepEqual(plain(A.slotOptions(state, null, onDesk)).map((o) => o.desk + "/" + o.slot),
    ["3/main", "3/right", "3/left", "3/mail"]);
  assert.deepEqual(plain(A.slotOptions(state, null, stray, 4)).map((o) => o.desk + "/" + o.slot),
    ["4/mail", "4/left", "4/main", "4/right"]);
  assert.deepEqual(plain(A.slotOptions(state, null, stray, null)), []);
  assert.equal(A.assignDesk(state, null, stray, 4), 4);
  assert.equal(A.assignDesk(state, null, stray, null), null);
  assert.equal(A.assignDesk(state, 3, stray, 4), 3, "a desk page is that desk");
});

test("the prompt names the desk and each option the way aerolayout's does", () => {
  const ask = (state, desk, row) =>
    P.display(P.choice(A.assignTitle(A.assignDesk(state, desk, row, null)), A.promptOptions(A.slotOptions(state, desk, row))));
  assert.equal(ask(fixture(), 3, null), "Assign to desk 3 slot (takes its spec): (m)ain, (r)ight, (l)eft, (1) mail? [Esc] cancel   → main");
  const picked = A.promptOptions(A.slotOptions(fixture(), 3, null))[1].value;
  assert.deepEqual([picked.desk, picked.slot], [3, "right"], "an option's value is the slot option itself");
});

test("clearing a spec takes the selected row's slot on its desk, when the desk has a spec for it", () => {
  const state = fixture();
  const rows = A.rows(state, 3);
  assert.deepEqual(plain(A.clearTarget(state, 3, rows[0])), { desk: 3, slot: "main", spec: "t-main" });
  assert.deepEqual(plain(A.clearTarget(state, 3, rows[2])), { desk: 3, slot: "left", spec: "t-left" }, "a Missing row");
  assert.deepEqual(plain(A.clearTarget(state, 3, rows[3])), { desk: 3, slot: "main", spec: "t-main" }, "an overflow row");
  assert.match(A.clearTarget(state, 3, rows[4]).error, /in no slot/);
  state.arrangements.dual.desks[4].big = { tree: "h[mail, main]", slots: ["mail", "main"] };
  assert.equal(A.clearTarget(state, 4, A.rows(state, 4)[1]).error, "Desk 4 has no spec for main.");
});

test("the first page shown is the focused workspace's desk, else every window", () => {
  const state = fixture();
  assert.equal(A.initialPage(state, 13), 1);
  assert.equal(A.initialPage(state, 4), 2);
  assert.equal(A.initialPage(state, 1), 0);
  assert.equal(A.initialPage(state, null), 0);
});

test("a desk's page, for the digit keys; -1 for a desk with no page", () => {
  const state = fixture();
  assert.equal(A.pageOfDesk(state, 3), 1);
  assert.equal(A.pageOfDesk(state, 4), 2);
  assert.equal(A.pageOfDesk(state, 7), -1);
});

test("no state yet means no pages but the every-window one, and no rows", () => {
  assert.deepEqual(plain(A.pages(null)), [{ desk: null, label: "All windows" }]);
  assert.deepEqual(plain(A.rows(null, null)), []);
});
