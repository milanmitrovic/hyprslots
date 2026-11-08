// The help row's model (Help.js): every action with its trigger key
// highlighted inside its label, as Qt StyledText.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const H = load("Help.js");
const ACCENT = "#89b4fa";
const k = (key) => `<b><font color="#89b4fa">${key}</font></b>`;

test("a single-letter key is highlighted where it first occurs in its label", () => {
  assert.equal(H.item({ key: "a", label: "add" }, ACCENT), k("a") + "dd");
  assert.equal(H.item({ key: "f", label: "fork" }, ACCENT), k("f") + "ork");
  assert.equal(H.item({ key: "u", label: "unassign" }, ACCENT), k("u") + "nassign");
  assert.equal(H.item({ key: "n", label: "rename" }, ACCENT), "re" + k("n") + "ame", "the first occurrence, not the first letter");
});

test("the match ignores case; a shifted key shows itself in place", () => {
  assert.equal(H.item({ key: "a", label: "Apply" }, ACCENT), k("A") + "pply");
  assert.equal(H.item({ key: "R", label: "record" }, ACCENT), k("R") + "ecord");
});

test("a key the label lacks goes before it", () => {
  assert.equal(H.item({ key: "x", label: "delete" }, ACCENT), k("x") + " delete");
  assert.equal(H.item({ key: "/", label: "flip" }, ACCENT), k("/") + " flip");
  assert.equal(H.item({ key: "-", label: "default trees" }, ACCENT), k("-") + " default trees");
});

test("a multi-character key always goes before its label", () => {
  assert.equal(H.item({ key: "Tab", label: "switch view" }, ACCENT), k("Tab") + " switch view");
  assert.equal(H.item({ key: "Ctrl+S", label: "save" }, ACCENT), k("Ctrl+S") + " save");
  assert.equal(H.item({ key: "[ ]", label: "workspace" }, ACCENT), k("[ ]") + " workspace");
  assert.equal(H.item({ key: "←→", label: "page" }, ACCENT), k("←→") + " page");
});

test("a key with no label stands alone", () => {
  assert.equal(H.item({ key: "1–9 0", label: "" }, ACCENT), k("1–9 0"));
});

test("markup in labels and keys is escaped", () => {
  assert.equal(H.item({ key: "<", label: "a < b & c > d" }, ACCENT), "a " + k("&lt;") + " b &amp; c &gt; d");
  assert.equal(H.item({ key: "&", label: "x" }, ACCENT), k("&amp;") + " x");
  assert.equal(H.escape("<b>&"), "&lt;b&gt;&amp;");
});

test("a row joins items with two spaces and groups with a dot; a group may have a title", () => {
  const row = H.row([
    [{ key: "↑/↓", label: "select" }],
    { title: "Tree", items: [{ key: "a", label: "add" }, { key: "x", label: "delete" }] },
    [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
  ], ACCENT);
  assert.equal(row, k("↑/↓") + " select   ·   Tree: " + k("a") + "dd  " + k("x") + " delete   ·   "
    + k("Tab") + " switch view  " + k("q") + " close");
});

test("an item with no key in a row is its plain, escaped text", () => {
  assert.equal(H.row([[{ text: "Read only <here>" }]], ACCENT), "Read only &lt;here&gt;");
});

test("the plain text of a row is what it reads like without the markup", () => {
  assert.equal(H.plain(H.row([[{ key: "a", label: "add" }, { key: "x", label: "a & b" }]], ACCENT)), "add  x a & b");
});
