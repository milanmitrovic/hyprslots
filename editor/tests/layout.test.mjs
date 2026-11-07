// The Layout view's tree editing (Layout.js): tree text and the ratio grammar
// as the engine reads them (tree.lua, ratio.lua), and the edits the view's
// keys make, after aerolayout's tree_visualizer.py.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const L = load("Layout.js");

const plain = (value) => JSON.parse(JSON.stringify(value));
const tree = (text) => {
  const parsed = L.parse(text);
  assert.equal(parsed.error, undefined, parsed.error);
  return parsed.node;
};
// Text in, text out: parse, edit, format.
const edited = (text, fn) => {
  const result = fn(tree(text));
  assert.equal(result.error, undefined, result.error);
  return L.format(result.node);
};
const refused = (text, fn) => {
  const result = fn(tree(text));
  assert.equal(typeof result.error, "string", "expected a refusal, got " + JSON.stringify(plain(result)));
  return result.error;
};

// --- tree text --------------------------------------------------------------

test("tree text reads back as the engine writes it: weights of 1 left out", () => {
  for (const text of ["main", "*", "h[a, b:2, c]", "v[top, h[a:3, b:5]:2]", "a[x, y, z]", "h[main:2, v[right, *]]",
    "h[a, a[b, c]:2]", "h", "a"]) {
    assert.equal(L.format(tree(text)), text);
  }
  assert.equal(L.format(tree(" h[ a:1 ,b ] ")), "h[a, b]");
});

test("tree text the engine would refuse is refused, with its message", () => {
  const error = (text) => L.parse(text).error;
  assert.match(error("h[a, a]"), /slot 'a' appears twice/);
  assert.match(error("h[a, *, *]"), /more than one overflow leaf/);
  assert.match(error("a[x, v[y, z]]"), /an accordion holds slots only, found 'v\[' inside it/);
  assert.match(error("a[x, *]"), /an accordion holds slots only, found '\*' inside it/);
  assert.match(error("a[x:2, y]"), /accordion members take no weight/);
  assert.match(error("h[a:0, b]"), /a weight must be a positive integer, got '0'/);
  assert.match(error("h[a, b]:2"), /the root of a tree takes no weight/);
  assert.match(error("h[a, b"), /expected '\]', found end of text/);
  assert.match(error(""), /expected a slot name/);
});

test("the leaves of a tree in reading order, the overflow leaf as *", () => {
  assert.deepEqual(plain(L.leaves(tree("h[main:2, v[right, *], a[x, y]]"))), ["main", "right", "*", "x", "y"]);
});

// --- the ratio grammar (ratio.lua) -----------------------------------------

test("the ratio of a tree: every split below the root, reduced, accordion panes as *", () => {
  assert.equal(L.ratio(tree("h[a, b, c]")), "1:1:1");
  assert.equal(L.ratio(tree("h[v[a, h[b, c]], d]")), "1[1:1[1:1]]:1");
  assert.equal(L.ratio(tree("h[v[a, b]:2, c]")), "2[1:1]:1");
  assert.equal(L.ratio(tree("h[a:2, b:4, c:2]")), "1:2:1");
  assert.equal(L.ratio(tree("h[a[x, y, z]:2, c]")), "2[*:*:*]:1");
  assert.equal(L.ratio(tree("main")), "");
});

test("a ratio sets both levels of a nested tree", () => {
  assert.equal(edited("h[v[left, main], right]", (n) => L.applyRatio(n, "2[1:2]:1")), "h[v[left, main:2]:2, right]");
  assert.equal(edited("h[v[a, b], v[c, d]]", (n) => L.applyRatio(n, "3[1:3]:1[3:1]")), "h[v[a, b:3]:3, v[c:3, d]]");
  assert.equal(edited("h[v[left, main:2]:2, right]", (n) => L.applyRatio(n, "5:1")), "h[v[left, main:2]:5, right]");
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, " 3 1 ")), "h[a:3, b]");
});

test("decimals become the smallest integer ratio, and common factors go", () => {
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, "1.5:1")), "h[a:3, b:2]");
  assert.equal(edited("h[a, b, c]", (n) => L.applyRatio(n, "0.25:0.25:0.5")), "h[a, b, c:2]");
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, "1.37:1")), "h[a:137, b:100]");
  assert.equal(edited("h[a, b, c]", (n) => L.applyRatio(n, "2:4:2")), "h[a, b:2, c]");
});

test("accordion panes take * or 1 and keep their place; numbers on them are refused", () => {
  assert.equal(edited("h[a[x, y, z], c]", (n) => L.applyRatio(n, "2[*:1:*]:1")), "h[a[x, y, z]:2, c]");
  assert.match(refused("a[x, y]", (n) => L.applyRatio(n, "2:1")),
    /ratios don't apply to the outer container — it's an accordion/);
  assert.match(refused("h[a, b]", (n) => L.applyRatio(n, "*:1")),
    /\* is an accordion pane with no share of its own, and the outer container is tiled/);
});

test("a ratio that does not fit the tree says where, as the engine does", () => {
  const H_WITH_V = "h[v[left, main], right]";
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "1:2:3")), /expected 2 values for the outer container, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2[1:2:3]:1")), /expected 2 values for cell 1, got 3/);
  assert.match(refused("h[v[a, h[b, c]], d]", (n) => L.applyRatio(n, "1[1:1[1:1:1]]:1")),
    /expected 2 values for cell 1 > cell 2, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2:1[1:1]")), /right is a window, so it has nothing to split/);
  assert.match(refused("h[a, *]", (n) => L.applyRatio(n, "1:1[1:1]")), /the overflow is a window/);
  assert.match(refused("main", (n) => L.applyRatio(n, "1:1")), /the outer container is a window, not a split/);
  assert.match(refused("h[v[a], b]", (n) => L.applyRatio(n, "1[1:1]:1")), /expected 1 value for cell 1, got 2/);
});

test("ratio syntax errors, as ratio.lua words them", () => {
  const error = (text) => L.applyRatio(tree("h[a, b]"), text).error;
  assert.match(error("a:1"), /"a" is not a number/);
  assert.match(error("2[1:2"), /unclosed "\["/);
  assert.match(error("1:"), /stray ":"/);
  assert.match(error("1:2]"), /unexpected "\]"/);
  assert.match(error("1[]:2"), /expected a number, found "\]"/);
  assert.match(error("[1:2]:1"), /expected a number, found "\["/);
  assert.match(error(""), /the ratio is empty/);
  assert.match(error("0:1"), /ratios must be greater than zero/);
  assert.match(error("-1:1"), /ratios must be greater than zero/);
});

test("the ratio shown is one that can be typed back and changes nothing", () => {
  for (const [text, entry] of [["h[a, b, c]", null], ["h[a, b, c]", "1:2:1"], ["h[v[left, main], right]", "2[1:2]:1"],
    ["h[v[a, h[b, c]], d]", "2[1:3[1:2]]:1"], ["h[a, b, c]", "1:1.37:2.5"], ["v[top, h[a:3, b:5]:2]", null],
    ["h[a[x, y]:2, *]", null]]) {
    let node = tree(text);
    if (entry) node = L.applyRatio(node, entry).node;
    const shown = L.ratio(node);
    const again = L.applyRatio(node, shown);
    assert.equal(again.error, undefined, again.error);
    assert.equal(L.ratio(again.node), shown);
    assert.equal(L.format(again.node), L.format(node), text + " at " + shown);
  }
});

test("clearing the ratios gives every split equal shares", () => {
  assert.equal(L.format(L.clearRatios(tree("h[v[a:3, b]:2, c:5]"))), "h[v[a, b], c]");
});

test("an edit never changes the tree it was given", () => {
  const node = tree("h[v[left, main], right]");
  L.applyRatio(node, "2[1:2]:1");
  assert.equal(L.format(node), "h[v[left, main], right]");
});

// --- selecting and moving (aerolayout's navigate_spatial, move_node,
// force_move_node, flip_tree, toggle_layout_mode) ----------------------------

test("arrows select the leaf that way, entering a container at its first leaf", () => {
  const t = tree("h[a, v[b, c], d]");
  assert.equal(L.navigate(t, "a", "right"), "b");
  assert.equal(L.navigate(t, "b", "down"), "c");
  assert.equal(L.navigate(t, "c", "up"), "b");
  assert.equal(L.navigate(t, "c", "right"), "d");
  assert.equal(L.navigate(t, "d", "left"), "b");
  assert.equal(L.navigate(t, "a", "left"), null);
  assert.equal(L.navigate(t, "a", "up"), null);
  // an accordion's members sit side by side, like its tabs
  const acc = tree("h[x, a[p, q]]");
  assert.equal(L.navigate(acc, "x", "right"), "p");
  assert.equal(L.navigate(acc, "p", "right"), "q");
  assert.equal(L.navigate(tree("main"), "main", "right"), null);
});

test("h j k l swap a node with its neighbour along its container", () => {
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "left")), "h[b:2, a, c]");
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "right")), "h[a, c, b:2]");
  assert.equal(edited("v[a, b]", (n) => L.move(n, "a", "down")), "v[b, a]");
  assert.equal(edited("a[x, y]", (n) => L.move(n, "x", "right")), "a[y, x]");
  assert.equal(edited("h[v[a, b], c]", (n) => L.move(n, "a", "right")), "h[v[a, b], c]", "across its container is no swap");
  assert.equal(L.move(tree("h[a, b]"), "a", "left").changed, false);
  assert.equal(L.move(tree("h[a, b]"), "a", "right").changed, true);
});

test("H J K L along the container pair a node with its neighbour across it", () => {
  assert.equal(edited("h[a, b, c]", (n) => L.forceMove(n, "b", "right")), "h[a, v[b, c]:2]");
  assert.equal(edited("h[a, b, c]", (n) => L.forceMove(n, "b", "left")), "h[v[a, b]:2, c]");
  // pairing c with the h above it merges into one row
  assert.equal(edited("v[h[a, b], c]", (n) => L.forceMove(n, "c", "up")), "h[a, b, c:2]");
  assert.equal(L.forceMove(tree("h[a, b]"), "b", "right").changed, false);
});

test("H J K L across the container move a node out of it, beside it", () => {
  assert.equal(edited("h[a, v[b, c]]", (n) => L.forceMove(n, "b", "left")), "h[a, b, c]");
  assert.equal(edited("h[a, v[b, c]:2]", (n) => L.forceMove(n, "c", "right")), "h[a, b:2, c]");
  assert.equal(edited("h[a, b]", (n) => L.forceMove(n, "a", "down")), "v[b, a]");
  assert.equal(edited("h[a, b]", (n) => L.forceMove(n, "a", "up")), "v[a, b]");
  assert.equal(edited("h[a[x, y], z]", (n) => L.forceMove(n, "x", "down")), "h[y, x, z]");
});

test("nothing pairs up inside an accordion: it holds slots only", () => {
  assert.match(refused("h[a[x, y], z]", (n) => L.forceMove(n, "x", "right")), /an accordion holds slots only/);
});

test("/ flips every split of the tree", () => {
  assert.equal(L.format(L.flip(tree("h[m, v[b, c:2], a[x, y]]"))), "v[m, h[b, c:2], a[x, y]]");
});

test("t stacks a leaf's container as an accordion and back, its shares kept", () => {
  const stacked = L.toggleAccordion(tree("h[a, v[b:2, c]:3]"), "b");
  assert.equal(L.format(stacked.node), "h[a, a[b, c]:3]");
  assert.equal(L.format(L.toggleAccordion(stacked.node, "c").node), "h[a, v[b:2, c]:3]");
  // one parsed as text has no split to go back to: side by side
  assert.equal(edited("a[x, y]", (n) => L.toggleAccordion(n, "x")), "h[x, y]");
});

test("t refuses a container holding more than slots, with the engine's message", () => {
  assert.match(refused("h[a, v[b, c]]", (n) => L.toggleAccordion(n, "a")),
    /an accordion holds slots only, found 'v\[' inside it/);
  assert.match(refused("h[a, *]", (n) => L.toggleAccordion(n, "a")), /an accordion holds slots only, found '\*' inside it/);
  assert.match(refused("main", (n) => L.toggleAccordion(n, "main")), /one window/);
});

// --- the overflow leaf (aerolayout's [o]: hide and show the overflow slot) --

test("o parks the overflow leaf and puts it back where it was", () => {
  const parked = L.toggleOverflow(tree("h[main:2, v[right, *]]"), null);
  assert.equal(parked.parked, true);
  assert.equal(L.format(parked.node), "h[main:2, right]");
  const back = L.toggleOverflow(parked.node, parked.memory);
  assert.equal(back.parked, false);
  assert.equal(L.format(back.node), "h[main:2, v[right, *]]");
});

test("o puts it back beside the leaf it was next to after the tree changed", () => {
  const parked = L.toggleOverflow(tree("h[main:2, v[right, *]]"), null);
  const flipped = L.flip(parked.node);
  assert.equal(L.format(L.toggleOverflow(flipped, parked.memory).node), "v[main:2, right, *]");
});

test("o with nothing remembered puts it where the engine puts a tree without one", () => {
  // tree.with_overflow: h[tree:3, *:1]
  assert.equal(L.format(L.toggleOverflow(tree("v[a, b]"), null).node), "h[v[a, b]:3, *]");
  assert.equal(L.format(L.toggleOverflow(tree("h[a, b]"), null).node), "h[a:3, b:3, *:2]");
  assert.equal(L.format(L.toggleOverflow(tree("main"), null).node), "h[main:3, *]");
});

test("o refuses to park the overflow leaf when it is the whole tree", () => {
  assert.match(L.toggleOverflow(tree("*"), null).error, /whole tree/);
});

// --- moving a leaf to another screen of the desk ----------------------------

test("a leaf moved off the edge of its screen joins the next screen's tree there", () => {
  let moved = L.crossMove(tree("h[a, b]"), tree("c"), "b", "right");
  assert.equal(L.format(moved.source), "a");
  assert.equal(L.format(moved.target), "h[b, c]");
  moved = L.crossMove(tree("v[c, d]"), tree("h[a, b]"), "c", "left");
  assert.equal(L.format(moved.source), "d");
  assert.equal(L.format(moved.target), "h[a, b, c]");
  moved = L.crossMove(tree("h[a, b]"), null, "a", "left");
  assert.equal(L.format(moved.target), "a");
});

test("a screen keeps at least one leaf, and one overflow leaf at most", () => {
  assert.match(L.crossMove(tree("c"), tree("h[a, b]"), "c", "left").error, /only window/);
  assert.match(L.crossMove(tree("h[a, *]"), tree("h[b, *]"), "*", "right").error, /overflow leaf already/);
});

// --- the mirror holds: the engine's own modules give the same answers -------

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const LUA = ["lua5.4", "lua5.5", "lua"].find((bin) => spawnSync(bin, ["-v"]).status === 0);

test("tree text and ratios read as tree.lua, serialize.lua and ratio.lua read them", { skip: !LUA && "no lua" }, () => {
  const cases = [
    ["h[a, b:2, c]", "1:1:1"], ["h[v[left, main], right]", "2[1:2]:1"], ["h[v[a, b], v[c, d]]", "3[1:3]:1[3:1]"],
    ["h[a, b]", "1.5:1"], ["h[a, b, c]", "0.25:0.25:0.5"], ["h[a, b]", "1.37:1"], ["h[a[x, y, z], c]", "2[*:1:*]:1"],
    ["a[x, y]", "2:1"], ["h[a, b]", "*:1"], ["h[v[a, h[b, c]], d]", "1[1:1[1:1:1]]:1"], ["h[a, *]", "1:1[1:1]"],
    ["main", "1:1"], ["h[a, b]", "1:"], ["h[a, b]", "[1:2]:1"], ["h[a, b]", "2[1:2"], ["h[a, b]", "x:1"],
    ["h[a, b]", "0:1"], ["h[a, b]", ""], ["h[a, b]", " 3  1 "], ["v[top, h[a:3, b:5]:2]", "1:1[1:1]"],
    ["h[main:2, v[right, *]]", "1:2[3:1]"], ["h[a, a]", "1:1"], ["a[x, v[y]]", "1"], ["h[a:0, b]", "1"],
    ["h[a, b]:2", "1"], ["h[a, b", "1"], ["", "1"], ["h[a, *, *]", "1"], ["a[x:2, y]", "1"], ["h[a, b]", "1:2]"],
  ];
  const here = dirname(fileURLToPath(import.meta.url));
  const root = join(here, "..", "..");
  const script = `
package.path = "${root}/lua/?.lua;" .. package.path
local tree, ratio, serialize = require("hyprslots.tree"), require("hyprslots.ratio"), require("hyprslots.serialize")
for line in io.lines() do
  local text, entry = line:match("^(.-)\\t(.*)$")
  local node, err = tree.parse(text)
  if not node then
    print("tree error: " .. err)
  else
    local applied, aerr = ratio.apply(node, entry)
    print(serialize.tree(node) .. " | " .. ratio.format(node) .. " | "
      .. (applied and serialize.tree(applied) or ("error: " .. aerr)))
  end
end`;
  const run = spawnSync(LUA, ["-e", script], { input: cases.map((c) => c.join("\t")).join("\n") + "\n", encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const lua = run.stdout.trimEnd().split("\n");
  cases.forEach(([text, entry], i) => {
    const parsed = L.parse(text);
    let js;
    if (parsed.error) {
      js = "tree error: " + parsed.error;
    } else {
      const applied = L.applyRatio(parsed.node, entry);
      js = L.format(parsed.node) + " | " + L.ratio(parsed.node) + " | "
        + (applied.error ? "error: " + applied.error : L.format(applied.node));
    }
    assert.equal(js, lua[i], `${text} at ${JSON.stringify(entry)}`);
  });
});

// --- the view's model: which trees, drawn how --------------------------------

function fixture() {
  return {
    ok: true,
    arrangement: "dual",
    dirty: false,
    desks: [3, 4],
    screens: { big: "HEADLESS-2", side: "HEADLESS-3" },
    workspaces: { 3: { desk: 3, role: "big" }, 13: { desk: 3, role: "side" }, 4: { desk: 4, role: "big" } },
    arrangements: {
      dual: {
        roles: ["big", "side"], screens: { big: "HEADLESS-2", side: "HEADLESS-3" }, active: true, read_only: false,
        desks: {
          3: { big: { tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", slots: ["main", "right"], resized: true },
            side: { tree: "left", ratio: "", slots: ["left"] } },
          4: { big: { tree: "mail", ratio: "", slots: ["mail"] } },
        },
      },
      single: { roles: ["big"], screens: { big: "HEADLESS-2" }, active: false, read_only: true, desks: {} },
    },
    windows: [
      { address: "0xa", class: "t-main", title: "editor", workspace: 3, desk: 3, slot: "main" },
      { address: "0xb", class: "t-left", title: "notes", workspace: 13, desk: 3, slot: "left" },
    ],
    config: { editable: true, read_only: ["arrangements.single"] },
  };
}

test("a desk shows one pane per screen role of the arrangement, with its tree in force", () => {
  assert.deepEqual(plain(L.panes(fixture(), "dual", 3)), [
    { role: "big", tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", resized: true, screen: "HEADLESS-2" },
    { role: "side", tree: "left", ratio: "", resized: false, screen: "HEADLESS-3" },
  ]);
  assert.deepEqual(plain(L.panes(fixture(), "dual", 4))[1], { role: "side", tree: null, ratio: "", resized: false,
    screen: "HEADLESS-3" });
  assert.deepEqual(plain(L.panes(fixture(), "nope", 3)), []);
});

test("the view opens on the active arrangement, at the focused workspace's desk and screen", () => {
  assert.deepEqual(plain(L.initialTarget(fixture(), 13)), { arrangement: "dual", desk: 3, role: "side" });
  assert.deepEqual(plain(L.initialTarget(fixture(), 1)), { arrangement: "dual", desk: 3, role: "big" });
  const none = fixture();
  delete none.arrangement;
  assert.deepEqual(plain(L.initialTarget(none, 3)), { arrangement: "dual", desk: 3, role: "big" });
});

test("what may not be edited says why", () => {
  assert.equal(L.editBlock(fixture(), "dual"), "");
  assert.match(L.editBlock(fixture(), "single"), /set by code in config\.lua/);
  const noData = fixture();
  noData.config.editable = false;
  assert.match(L.editBlock(noData, "dual"), /loads no slots\.lua/);
  const off = fixture();
  off.refused = "hyprmoncfg's workspace planner is on";
  assert.match(L.editBlock(off, "dual"), /hyprslots is off: hyprmoncfg/);
  assert.match(L.editBlock(null, "dual"), /no state/);
});

test("the slot -> window title map for a pane: what sits in each slot on that screen", () => {
  assert.deepEqual(plain(L.titles(fixture(), 3, "big")), { main: "editor" });
  assert.deepEqual(plain(L.titles(fixture(), 3, "side")), { left: "notes" });
});

test("boxes are proportional to the weights, the remainder to the last child", () => {
  const rects = plain(L.rects(tree("h[a:2, b]"), { x: 0, y: 0, w: 301, h: 100 }, { pad: 0 }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key, r.x, r.y, r.w, r.h, r.label]), [
    ["slot", "a", 0, 0, 200, 100, "a ×2"],
    ["slot", "b", 200, 0, 101, 100, "b"],
  ]);
});

test("a nested container is drawn as a titled box, its children inside it", () => {
  const rects = plain(L.rects(tree("h[main:2, v[right, *]]"), { x: 0, y: 0, w: 300, h: 100 }, { pad: 4, title: 10 }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key || "", r.x, r.y, r.w, r.h, r.label, r.depth]), [
    ["slot", "main", 0, 0, 200, 100, "main ×2", 1],
    ["v", "", 200, 0, 100, 100, "v 1:1", 1],
    ["slot", "right", 204, 14, 92, 41, "right", 2],
    ["overflow", "*", 204, 55, 92, 41, "* overflow", 2],
  ]);
});

test("an accordion shows a tab per member, and the open one's box: the selected, else the first", () => {
  const shown = (selected) => plain(L.rects(tree("h[a[x, y], z]"), { x: 0, y: 0, w: 200, h: 100 },
    { pad: 0, title: 0, tab: 20, selected }));
  assert.deepEqual(shown("z").map((r) => [r.kind, r.key || "", r.x, r.y, r.w, r.h, !!r.open]), [
    ["a", "", 0, 0, 100, 100, false],
    ["tab", "x", 0, 0, 50, 20, true],
    ["tab", "y", 50, 0, 50, 20, false],
    ["slot", "x", 0, 20, 100, 80, false],
    ["slot", "z", 100, 0, 100, 100, false],
  ]);
  assert.deepEqual(shown("y").filter((r) => r.kind === "slot").map((r) => r.key), ["y", "z"]);
  assert.equal(shown("y").find((r) => r.key === "y" && r.kind === "slot").selected, true);
});

test("the ratio prompt names the current ratio, and refuses a tree with nothing to divide", () => {
  assert.equal(L.ratioPrompt(tree("h[main:2, v[right, *]]")).text,
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.equal(L.ratioPrompt(tree("h[a, b]")).text,
    "Ratios for the whole tree (current 1:1; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.equal(L.ratioPrompt(tree("h[a, a[x, y]]")).text,
    "Ratios for the whole tree (current 1:1[*:*]; * = an accordion pane, leave it; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.match(L.ratioPrompt(tree("main")).error, /Nothing to divide/);
  assert.match(L.ratioPrompt(tree("a[x, y]")).error, /accordion all the way down/);
});

test("the order strip lists the leaves in order once the tree nests", () => {
  assert.equal(L.order(tree("h[a, b]")), "");
  assert.equal(L.order(tree("h[main, v[right, *]]")), "1.main → 2.right → 3.overflow");
});
