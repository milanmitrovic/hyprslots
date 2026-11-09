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
  for (const text of ["main", "*", "h[a, b:2, c]", "v[top, h[a:3, b:5]:2]", "scroll[x, y, z]", "scroll[main]",
    "h[main:2, v[right, *]]", "h", "a", "scroll"]) {
    assert.equal(L.format(tree(text)), text);
  }
  assert.equal(L.format(tree(" h[ a:1 ,b ] ")), "h[a, b]");
});

test("tree text the engine would refuse is refused, with its message", () => {
  const error = (text) => L.parse(text).error;
  assert.match(error("h[a, a]"), /slot 'a' appears twice/);
  assert.match(error("h[a, *, *]"), /more than one place for other windows/);
  assert.match(error("a[x, y]"),
    /a\[\.\.\.\] \(an accordion, a Hyprland group with tabs\) is gone: write scroll\[x, y\] for full-width scrolling columns at position 1/);
  assert.match(error("scroll[x, v[y, z]]"), /scroll\[\.\.\.\] holds slots only, found 'v\[' inside it/);
  assert.match(error("scroll[x, *, *]"), /more than one place for other windows '\*'/);
  assert.match(error("a[x, *]"), /a\[\.\.\.\] holds slots only, found '\*' inside it/);
  assert.match(error("scroll[x:2, y]"), /columns of scroll\[\.\.\.\] take no weight/);
  assert.match(error("h[scroll[x, y], d]"), /scroll\[\.\.\.\] is a whole screen's tree, found it inside a split at position 3/);
  assert.match(error("h[a:0, b]"), /a weight must be a positive integer, got '0'/);
  assert.match(error("h[a, b]:2"), /the root of a tree takes no weight/);
  assert.match(error("h[a, b"), /expected '\]', found end of text/);
  assert.match(error(""), /expected a slot name/);
});

test("the leaves of a tree in reading order, the overflow leaf as *", () => {
  assert.deepEqual(plain(L.leaves(tree("h[main:2, v[right, *], x]"))), ["main", "right", "*", "x"]);
  assert.deepEqual(plain(L.leaves(tree("scroll[x, y]"))), ["x", "y"]);
  assert.deepEqual(plain(L.leaves(tree("scroll[x, *, y]"))), ["x", "*", "y"]);
});

// --- the ratio grammar (ratio.lua) -----------------------------------------

test("the ratio of a tree: every split below the root, reduced, scroll columns as *", () => {
  assert.equal(L.ratio(tree("h[a, b, c]")), "1:1:1");
  assert.equal(L.ratio(tree("h[v[a, h[b, c]], d]")), "1[1:1[1:1]]:1");
  assert.equal(L.ratio(tree("h[v[a, b]:2, c]")), "2[1:1]:1");
  assert.equal(L.ratio(tree("h[a:2, b:4, c:2]")), "1:2:1");
  assert.equal(L.ratio(tree("scroll[x, y, z]")), "*:*:*");
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

test("scroll columns take * or 1 and change nothing; numbers on them are refused", () => {
  assert.equal(edited("scroll[x, y, z]", (n) => L.applyRatio(n, "*:1:*")), "scroll[x, y, z]");
  assert.match(refused("scroll[x, y]", (n) => L.applyRatio(n, "2:1")),
    /ratios don't apply to the outer container — it's a scroll branch, and each of its columns is full width/);
  assert.match(refused("h[a, b]", (n) => L.applyRatio(n, "*:1")),
    /\* is a scroll column with no share of its own, and the outer container is tiled/);
});

test("a ratio that does not fit the tree says where, as the engine does", () => {
  const H_WITH_V = "h[v[left, main], right]";
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "1:2:3")), /expected 2 values for the outer container, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2[1:2:3]:1")), /expected 2 values for cell 1, got 3/);
  assert.match(refused("h[v[a, h[b, c]], d]", (n) => L.applyRatio(n, "1[1:1[1:1:1]]:1")),
    /expected 2 values for cell 1 > cell 2, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2:1[1:1]")), /right is a window, so it has nothing to split/);
  assert.match(refused("h[a, *]", (n) => L.applyRatio(n, "1:1[1:1]")), /the place for other windows is a window/);
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
    ["scroll[x, y]", null]]) {
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
  // a scroll branch's columns sit side by side, in order
  const film = tree("scroll[p, q, r]");
  assert.equal(L.navigate(film, "p", "right"), "q");
  assert.equal(L.navigate(film, "r", "left"), "q");
  assert.equal(L.navigate(film, "q", "down"), null);
  assert.equal(L.navigate(tree("main"), "main", "right"), null);
});

test("h j k l swap a node with its neighbour along its container", () => {
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "left")), "h[b:2, a, c]");
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "right")), "h[a, c, b:2]");
  assert.equal(edited("v[a, b]", (n) => L.move(n, "a", "down")), "v[b, a]");
  assert.equal(edited("scroll[x, y]", (n) => L.move(n, "x", "right")), "scroll[y, x]");
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

});

test("nothing pairs up or leaves a scroll branch: it holds slots only", () => {
  assert.match(refused("scroll[x, y]", (n) => L.forceMove(n, "x", "right")), /a scroll branch holds slots only/);
  assert.match(refused("scroll[x, y]", (n) => L.forceMove(n, "x", "down")), /a scroll branch holds slots only/);
});

test("/ flips every split of the tree, and leaves a scroll branch as it is", () => {
  assert.equal(L.format(L.flip(tree("h[m, v[b, c:2]]"))), "v[m, h[b, c:2]]");
  assert.equal(L.format(L.flip(tree("scroll[x, y]"))), "scroll[x, y]");
});

test("t makes the whole tree a scroll branch of its slots in order, and back as it was", () => {
  const scrolled = L.toggleScroll(tree("h[a, v[b:2, c]:3]"));
  assert.equal(L.format(scrolled.node), "scroll[a, b, c]");
  assert.equal(L.format(L.toggleScroll(scrolled.node).node), "h[a, v[b:2, c]:3]");
  // the overflow leaf becomes the column windows with no slot take, in
  // reading order, and comes back with the tree
  const withOverflow = L.toggleScroll(tree("h[a, v[*, b]]"));
  assert.equal(L.format(withOverflow.node), "scroll[a, *, b]");
  assert.equal(L.format(L.toggleScroll(withOverflow.node).node), "h[a, v[*, b]]");
  assert.equal(edited("main", (n) => L.toggleScroll(n)), "scroll[main]");
});

test("t back from a scroll branch whose columns changed tiles them side by side in their order", () => {
  const scrolled = L.toggleScroll(tree("h[a, v[b, c]]"));
  const moved = L.move(scrolled.node, "a", "right");
  assert.equal(L.format(moved.node), "scroll[b, a, c]");
  assert.equal(L.format(L.toggleScroll(moved.node).node), "h[b, a, c]");
  // one parsed as text has no tree to go back to: side by side
  assert.equal(edited("scroll[x, y]", (n) => L.toggleScroll(n)), "h[x, y]");
});

test("t refuses a tree with no slot to scroll", () => {
  assert.match(refused("*", (n) => L.toggleScroll(n)), /nothing to scroll/);
});

// --- other windows (windows assigned to no slot): o shows or hides their place --

test("every tree has a place for other windows: its * leaf, else where the engine puts them", () => {
  // tree.with_overflow: h[tree:3, *:1]; a scroll branch: a column after its own
  assert.equal(L.format(L.withOther(tree("v[a, b]"))), "h[v[a, b]:3, *]");
  assert.equal(L.format(L.withOther(tree("h[a, b]"))), "h[a:3, b:3, *:2]");
  assert.equal(L.format(L.withOther(tree("main"))), "h[main:3, *]");
  assert.equal(L.format(L.withOther(tree("scroll[x, y]"))), "scroll[x, y, *]");
  assert.equal(L.format(L.withOther(tree("h[main:2, v[right, *]]"))), "h[main:2, v[right, *]]", "its own * as it is");
  assert.equal(L.format(L.withOther(tree("scroll[x, *, y]"))), "scroll[x, *, y]");
});

test("the picture shows that place only when o says so; the tree keeps it either way", () => {
  const own = tree("h[main:2, v[right, *]]");
  assert.equal(L.format(L.picture(own, false)), "h[main:2, right]");
  assert.equal(L.format(L.picture(own, true)), "h[main:2, v[right, *]]");
  assert.equal(L.format(own), "h[main:2, v[right, *]]", "the tree given is untouched");
  assert.equal(L.format(L.picture(tree("h[a, b]"), false)), "h[a, b]");
  assert.equal(L.format(L.picture(tree("h[a, b]"), true)), "h[a:3, b:3, *:2]");
  assert.equal(L.format(L.picture(tree("scroll[x, *, y]"), false)), "scroll[x, y]");
  assert.equal(L.format(L.picture(tree("scroll[x, y]"), true)), "scroll[x, y, *]");
  assert.equal(L.format(L.picture(tree("*"), false)), "*", "a tree that is only the place stays drawn");
  assert.equal(L.picture(null, true), null);
});

test("moving other windows' place writes it into the tree where it goes", () => {
  const moved = L.move(L.withOther(tree("h[a, b]")), "*", "left");
  assert.equal(L.format(moved.node), "h[a:3, *:2, b:3]");
  assert.equal(edited("scroll[x, y]", (n) => L.move(L.withOther(n), "*", "left")), "scroll[x, *, y]");
});

// --- moving a leaf to another screen of the workspace ----------------------------

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

test("a leaf moved onto a scroll branch becomes its column at the near edge, and one leaves its columns", () => {
  let moved = L.crossMove(tree("h[a, b]"), tree("scroll[c, d]"), "b", "right");
  assert.equal(L.format(moved.source), "a");
  assert.equal(L.format(moved.target), "scroll[b, c, d]");
  moved = L.crossMove(tree("scroll[c, d]"), tree("e"), "d", "right");
  assert.equal(L.format(moved.source), "scroll[c]");
  assert.equal(L.format(moved.target), "h[d, e]");
});

test("a screen keeps at least one leaf; other windows' place stays on its screen", () => {
  assert.match(L.crossMove(tree("c"), tree("h[a, b]"), "c", "left").error, /only window/);
  assert.match(L.crossMove(tree("h[a, *]"), tree("scroll[c]"), "*", "right").error, /other windows stay on their screen/);
  assert.match(L.crossMove(tree("h[a, *]"), tree("h[b, *]"), "*", "right").error, /other windows stay on their screen/);
});

// --- the mirror holds: the engine's own modules give the same answers -------

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const LUA = ["lua5.4", "lua5.5", "lua"].find((bin) => spawnSync(bin, ["-v"]).status === 0);

test("tree text and ratios read as tree.lua, serialize.lua and ratio.lua read them", { skip: !LUA && "no lua" }, () => {
  const cases = [
    ["h[a, b:2, c]", "1:1:1"], ["h[v[left, main], right]", "2[1:2]:1"], ["h[v[a, b], v[c, d]]", "3[1:3]:1[3:1]"],
    ["h[a, b]", "1.5:1"], ["h[a, b, c]", "0.25:0.25:0.5"], ["h[a, b]", "1.37:1"], ["scroll[x, y, z]", "*:1:*"],
    ["scroll[x, y]", "2:1"], ["h[a, b]", "*:1"], ["h[v[a, h[b, c]], d]", "1[1:1[1:1:1]]:1"], ["h[a, *]", "1:1[1:1]"],
    ["main", "1:1"], ["h[a, b]", "1:"], ["h[a, b]", "[1:2]:1"], ["h[a, b]", "2[1:2"], ["h[a, b]", "x:1"],
    ["h[a, b]", "0:1"], ["h[a, b]", ""], ["h[a, b]", " 3  1 "], ["v[top, h[a:3, b:5]:2]", "1:1[1:1]"],
    ["h[main:2, v[right, *]]", "1:2[3:1]"], ["h[a, a]", "1:1"], ["scroll[x, v[y]]", "1"], ["h[a:0, b]", "1"],
    ["h[a, b]:2", "1"], ["h[a, b", "1"], ["", "1"], ["h[a, *, *]", "1"], ["scroll[x:2, y]", "1"], ["h[a, b]", "1:2]"],
    ["a[x, y]", "1"], ["h[a[x, y], d]", "1"], ["h[scroll[x], y]", "1"], ["scroll[x, *]", "1"], ["scroll[main]", "1"],
    ["scroll[x, y]", "*[1]:*"], ["scroll[x, *, y]", "*:*:*"], ["scroll[*, x]", "1:1"], ["scroll[x, *, *]", "1"],
    ["scroll[x, *:2]", "1"], ["scroll[x, *]", "2:1"],
    ["scroll:0.5[x, y]", "*:*"], ["scroll:1[x]", "1"], ["scroll:1.0[x, *]", "*:1"], ["scroll:2[x]", "1"],
    ["scroll:x[a]", "1"], ["scroll:[a]", "1"], ["h[scroll:0.5[x], y]", "1"], ["h[scroll:2, b]", "1:1"],
    ["scroll : .5 [a, *]", "1:1"], ["scroll:0.33333[a]", "1"], ["scroll:0.05[a]", "1"], ["scroll:0.5[a]:2", "1"],
    ["scroll:0.25[a, v[b]]", "1"],
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

// Desk "docked" (eDP-1 left, DP-2 right) uses layout "dual", which office
// shares; dual has default trees (screen 1: main) and workspaces 3 and 4 of
// its own; workspace 5 shows the default trees.
function fixture() {
  return {
    ok: true,
    desk: "docked",
    layout: "dual",
    dirty: false,
    used_workspaces: [3, 4],
    screens: ["eDP-1", "DP-2"],
    monitors: [
      { name: "DP-2", description: "Samsung G95NC", width: 5120, height: 1440 },
      { name: "eDP-1", description: "BOE 0x0BCA", width: 1920, height: 1200 },
    ],
    workspaces: { 3: { workspace: 3, screen: 1 }, 13: { workspace: 3, screen: 2 }, 4: { workspace: 4, screen: 1 } },
    desks: { docked: { monitors: ["eDP-1", "Samsung G95NC"], layout: "dual", active: true },
      office: { monitors: ["eDP-1", "Dell"], layout: "dual", active: false } },
    layouts: {
      dual: {
        screens: 2, active: true, read_only: false, used_by: ["docked", "office"], own: [3, 4],
        default: { 1: { tree: "main", ratio: "", slots: ["main"] } },
        workspaces: {
          3: { 1: { tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", slots: ["main", "right"], resized: true },
            2: { tree: "left", ratio: "", slots: ["left"] } },
          4: { 1: { tree: "mail", ratio: "", slots: ["mail"] } },
          5: { 1: { tree: "main", ratio: "", slots: ["main"] } },
        },
      },
      single: { screens: 1, active: false, read_only: true, used_by: [], own: [], default: {}, workspaces: {} },
    },
    windows: [
      { address: "0xa", class: "t-main", title: "editor", workspace_id: 3, workspace: 3, slot: "main" },
      { address: "0xb", class: "t-left", title: "notes", workspace_id: 13, workspace: 3, slot: "left" },
    ],
    config: { editable: true, read_only: ["layouts.single"] },
  };
}

test("a workspace shows one pane per screen of the layout, with the tree it shows", () => {
  assert.deepEqual(plain(L.panes(fixture(), "dual", 3)), [
    { screen: 1, key: "1", tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", resized: true, connector: "eDP-1" },
    { screen: 2, key: "2", tree: "left", ratio: "", resized: false, connector: "DP-2" },
  ]);
  assert.deepEqual(plain(L.panes(fixture(), "dual", 4))[1], { screen: 2, key: "2", tree: null, ratio: "", resized: false,
    connector: "DP-2" });
  assert.deepEqual(plain(L.panes(fixture(), "nope", 3)), []);
});

test("the default trees are a workspace of their own to the panes", () => {
  assert.deepEqual(plain(L.panes(fixture(), "dual", "default")).map((p) => [p.screen, p.tree]), [[1, "main"], [2, null]]);
});

test("a pane is labelled with the active desk's monitor at its position", () => {
  assert.equal(L.screenLabel(fixture(), 1), "Screen 1 · eDP-1 (BOE 0x0BCA)");
  assert.equal(L.screenLabel(fixture(), 2), "Screen 2 · DP-2 (Samsung G95NC)");
  assert.equal(L.screenLabel(fixture(), 3), "Screen 3");
  assert.equal(L.screenLabel(null, 1), "Screen 1");
});

test("a workspace on the shared trees says it uses them, and whom its edits are for once asked", () => {
  assert.equal(L.defaultNote(fixture(), "dual", 5), "(uses the shared tree)");
  assert.equal(L.defaultNote(fixture(), "dual", 7), "(uses the shared tree)", "the shared tree may be empty");
  assert.equal(L.defaultNote(fixture(), "dual", 5, "all"), "(uses the shared tree: editing it for all workspaces)");
  assert.equal(L.defaultNote(fixture(), "dual", 5, "only"), "(uses the shared tree: w gives workspace 5 its own)");
  assert.equal(L.defaultNote(fixture(), "dual", 3), "", "trees of its own");
  assert.equal(L.defaultNote(fixture(), "dual", "default"), "");
});

test("a workspace has trees of its own, or uses the shared ones", () => {
  assert.equal(L.hasOwn(fixture(), "dual", 3), true);
  assert.equal(L.hasOwn(fixture(), "dual", 5), false);
  assert.equal(L.hasOwn(fixture(), "dual", "default"), false);
  assert.equal(L.hasOwn(null, "dual", 3), false);
});

test("the first edit of a workspace on the shared trees asks whom it is for", () => {
  assert.equal(L.needsScope(fixture(), "dual", 5, ""), true);
  assert.equal(L.needsScope(fixture(), "dual", 5, "all"), false, "asked already");
  assert.equal(L.needsScope(fixture(), "dual", 5, "only"), false);
  assert.equal(L.needsScope(fixture(), "dual", 3, ""), false, "its own trees");
  assert.equal(L.needsScope(fixture(), "dual", "default", ""), false, "All workspaces edits the shared trees");
  const P = load("Prompts.js");
  const scope = L.scopeQuestion(5);
  const prompt = P.choice(scope.label, scope.options, { inline: true });
  assert.equal(P.display(prompt), "Apply to (a)ll workspaces or (o)nly workspace 5? [Esc] cancel");
  assert.deepEqual(plain(P.key(prompt, "", "a").result), { value: "all" });
  assert.deepEqual(plain(P.key(prompt, "", "o").result), { value: "only" });
  assert.equal(P.key(prompt, "", "x").result, null);
});

test("an edit goes to the shared trees for all workspaces, else to the workspace", () => {
  assert.equal(L.editTarget(5, "all"), "default");
  assert.equal(L.editTarget(5, "only"), 5);
  assert.equal(L.editTarget(3, ""), 3);
  assert.equal(L.editTarget("default", ""), "default");
});

test("the view opens at the focused workspace's number and screen", () => {
  assert.deepEqual(plain(L.initialTarget(fixture(), 13)), { workspace: 3, screen: 2 });
  assert.deepEqual(plain(L.initialTarget(fixture(), 1)), { workspace: 3, screen: 1 }, "an unknown id: the first used workspace");
  const none = fixture();
  none.used_workspaces = [];
  assert.deepEqual(plain(L.initialTarget(none, 1)), { workspace: 1, screen: 1 });
});

test("what may not be edited says why", () => {
  assert.equal(L.editBlock(fixture(), "dual"), "");
  assert.equal(L.editBlock(fixture(), "single"), "layout 'single' is set by code in your config; edit it there");
  const noData = fixture();
  noData.config.editable = false;
  assert.equal(L.editBlock(noData, "dual"), "your config loads no editor data, so there is nothing the editor may change");
  const off = fixture();
  off.refused = "hyprmoncfg's workspace planner is on";
  assert.match(L.editBlock(off, "dual"), /hyprslots is off: hyprmoncfg/);
  assert.match(L.editBlock(null, "dual"), /no state/);
  assert.match(L.editBlock(fixture(), ""), /no desk is active/);
});

test("the slot -> window title map for a pane: what sits in each slot on that screen", () => {
  assert.deepEqual(plain(L.titles(fixture(), 3, 1)), { main: "editor" });
  assert.deepEqual(plain(L.titles(fixture(), 3, 2)), { left: "notes" });
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
    ["overflow", "*", 204, 55, 92, 41, "other windows", 2],
  ]);
});

test("a scroll branch is a filmstrip: its columns side by side in order, numbered, no tabs", () => {
  const rects = plain(L.rects(tree("scroll[x, y, z]"), { x: 0, y: 0, w: 301, h: 100 }, { pad: 4, title: 10, selected: "y" }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key, r.x, r.y, r.w, r.h, r.label, r.column, !!r.selected]), [
    ["slot", "x", 0, 0, 100, 100, "1. x", 1, false],
    ["slot", "y", 100, 0, 100, 100, "2. y", 2, true],
    ["slot", "z", 200, 0, 101, 100, "3. z", 3, false],
  ]);
  assert.equal(rects.some((r) => r.kind === "tab"), false);
});

test("a scroll branch's column for other windows is a frame of the filmstrip where it stands", () => {
  const rects = plain(L.rects(tree("scroll[x, *, z]"), { x: 0, y: 0, w: 300, h: 100 }, { selected: "*" }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key, r.x, r.w, r.label, r.column, !!r.selected]), [
    ["slot", "x", 0, 100, "1. x", 1, false],
    ["overflow", "*", 100, 100, "2. other windows", 2, true],
    ["slot", "z", 200, 100, "3. z", 3, false],
  ]);
});

test("the ratio prompt names the current ratio, and refuses a tree with nothing to divide", () => {
  assert.equal(L.ratioPrompt(tree("h[main:2, v[right, *]]")).text,
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.equal(L.ratioPrompt(tree("h[a, b]")).text,
    "Ratios for the whole tree (current 1:1; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.match(L.ratioPrompt(tree("main")).error, /Nothing to divide/);
  assert.match(L.ratioPrompt(tree("scroll[x, y]")).error,
    /Ratios don't apply to a scroll branch — each of its columns is full width \(\*:\*\)\. Press t for tiles first\./);
});

// --- adding and removing slots (global slots) --------------------------------

test("a adds a slot right after the selected leaf, in its container", () => {
  assert.equal(edited("h[a, b:2, c]", (n) => L.addSlot(n, "b", "x")), "h[a, b:2, x, c]");
  assert.equal(edited("h[a, v[b, c]]", (n) => L.addSlot(n, "b", "x")), "h[a, v[b, x, c]]");
  assert.equal(edited("scroll[a, b]", (n) => L.addSlot(n, "a", "x")), "scroll[a, x, b]");
  assert.equal(edited("h[a, *]", (n) => L.addSlot(n, "*", "x")), "h[a, *, x]");
});

test("a on a tree that is one leaf splits it side by side; on a screen with no tree the slot is the tree", () => {
  assert.equal(edited("main", (n) => L.addSlot(n, "main", "x")), "h[main, x]");
  assert.equal(L.format(L.addSlot(null, "", "x").node), "x");
});

test("a refuses a slot the tree already has", () => {
  assert.match(refused("h[a, b]", (n) => L.addSlot(n, "a", "b")), /already/);
});

test("x takes the selected slot out of the tree, tidied; the last leaf leaves no tree", () => {
  assert.equal(edited("h[a, v[b, c]:2]", (n) => L.removeSlot(n, "b")), "h[a, c:2]");
  assert.equal(edited("scroll[a, b]", (n) => L.removeSlot(n, "a")), "scroll[b]");
  assert.equal(L.removeSlot(tree("a"), "a").node, null);
  assert.match(refused("h[a, *]", (n) => L.removeSlot(n, "*")), /other windows always have a place/);
});

test("the slots a adds are the global ones no pane of the workspace places yet", () => {
  const state = { slots: [{ name: "left" }, { name: "main" }, { name: "right" }, { name: "side" }] };
  const drafts = { 1: { node: tree("h[main, right]") }, 2: { node: null }, 3: { node: tree("left") } };
  assert.deepEqual(plain(L.slotChoices(state, drafts)), ["side"]);
  assert.deepEqual(plain(L.slotChoices(null, drafts)), []);
});

test("the screen whose draft places a slot, null when no screen of the workspace does", () => {
  const drafts = { 1: { node: tree("h[main, right]") }, 2: { node: null }, 3: { node: tree("left") } };
  assert.equal(L.placedIn(drafts, "right"), "1");
  assert.equal(L.placedIn(drafts, "left"), "3");
  assert.equal(L.placedIn(drafts, "notes"), null);
  assert.equal(L.placedIn(drafts, "*"), null);
});

test("a slot renamed in a draft keeps its place and weight", () => {
  assert.equal(edited("h[main:2, v[right, *]]", (n) => ({ node: L.renameSlot(n, "right", "aside") })), "h[main:2, v[aside, *]]");
  assert.equal(edited("scroll[a, b]", (n) => ({ node: L.renameSlot(n, "a", "x") })), "scroll[x, b]");
  assert.equal(edited("main", (n) => ({ node: L.renameSlot(n, "other", "x") })), "main");
});
