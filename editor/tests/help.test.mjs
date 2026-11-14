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

test("an item with `before` puts even a one-letter key before its label", () => {
  assert.equal(H.item({ key: "o", label: "show/hide other windows", before: true }, ACCENT), k("o") + " show/hide other windows");
  assert.equal(H.item({ key: "o", label: "show/hide other windows" }, ACCENT), "sh" + k("o") + "w/hide other windows");
});

// --- the toolbar: the same rows as buttons ---------------------------------

const plain = (value) => JSON.parse(JSON.stringify(value));

test("a key names the key presses a click feeds the panel, as Panel.press names them", () => {
  assert.deepEqual(plain(H.presses("a")), [{ glyph: "a", press: "a" }]);
  assert.deepEqual(plain(H.presses("R")), [{ glyph: "R", press: "R" }]);
  assert.deepEqual(plain(H.presses("Ctrl+S")), [{ glyph: "Ctrl+S", press: "Ctrl+s" }]);
  assert.deepEqual(plain(H.presses("Tab")), [{ glyph: "Tab", press: "Tab" }]);
  assert.deepEqual(plain(H.presses("Return")), [{ glyph: "Return", press: "Return" }]);
  assert.deepEqual(plain(H.presses("/")), [{ glyph: "/", press: "/" }]);
  assert.deepEqual(plain(H.presses("s/Esc")), [{ glyph: "s", press: "s" }, { glyph: "Esc", press: "Escape" }]);
  assert.deepEqual(plain(H.presses("↑/↓")), [{ glyph: "↑", press: "Up" }, { glyph: "↓", press: "Down" }]);
  assert.deepEqual(plain(H.presses("←↑↓→")).map((p) => p.press), ["Left", "Up", "Down", "Right"]);
  assert.deepEqual(plain(H.presses("←/→ [ ]")).map((p) => p.press), ["Left", "Right", "[", "]"]);
  assert.deepEqual(plain(H.presses("hjkl/HJKL")).map((p) => p.press), ["h", "j", "k", "l", "H", "J", "K", "L"]);
});

test("the digits are the workspace switcher's to click: a range and its digits feed nothing", () => {
  assert.deepEqual(plain(H.presses("[ ] 1–9 0 -")), [
    { glyph: "[", press: "[" }, { glyph: "]", press: "]" }, { glyph: "1–9", press: null }, { glyph: "0", press: null },
    { glyph: "-", press: "-" },
  ]);
  assert.deepEqual(plain(H.presses("1–4")), [{ glyph: "1–4", press: null }]);
});

test("the toolbar is the help row as cells: a button per one-key action, keys then a label for several", () => {
  const cells = plain(H.buttons([
    [{ key: "↑/↓", label: "select" }],
    { title: "Workspace", items: [{ key: "←/→ [ ]", label: "prev/next" }, { key: "1–9", label: "jump" }] },
    [{ key: "a", label: "assign" }, { key: "u", label: "unassign", enabled: false }],
    [],
    [{ key: "Tab", label: "switch view" }],
  ], ACCENT));
  assert.deepEqual(cells.map((c) => [c.kind, c.group, c.styled || c.text || c.label]), [
    ["keys", 0, "select"],
    ["title", 1, "Workspace"],
    ["keys", 1, "prev/next"],
    ["keys", 1, "jump"],
    ["button", 2, k("a") + "ssign"],
    ["button", 2, k("u") + "nassign"],
    ["button", 3, k("Tab") + " switch view"],
  ]);
  assert.deepEqual(cells[0].keys, [{ glyph: "↑", press: "Up" }, { glyph: "↓", press: "Down" }]);
  assert.deepEqual([cells[4].press, cells[4].available], ["a", true]);
  assert.deepEqual([cells[5].press, cells[5].available], ["u", false], "an action the view would refuse looks it");
  assert.deepEqual(cells.map((c) => c.first), [true, true, false, false, true, false, true], "where a group starts");
});

test("plain text in a row is a cell of its own, and the toolbar reads as the row does", () => {
  const groups = [[{ key: "w", label: "apply" }, { text: "or" }, { key: "Ctrl+S", label: "save" }]];
  const cells = plain(H.buttons(groups, ACCENT));
  assert.deepEqual(cells.map((c) => c.kind), ["button", "text", "button"]);
  assert.equal(H.plain(H.row(groups, ACCENT)), "w apply  or  Ctrl+S save");
});
