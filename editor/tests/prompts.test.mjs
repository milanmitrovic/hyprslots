// The panel's prompts, every view's (Prompts.js): a line of text
// typed in place, a pick among keyed options, a yes/no question. Keys come
// in as names ("Return", "Backspace", ...) with the text they type.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const P = load("Prompts.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Feed keys: a string types its characters, [name] presses a named key.
function feed(prompt, ...keys) {
  let result = null;
  for (const k of keys) {
    const presses = Array.isArray(k) ? [[k[0], ""]] : [...k].map((c) => ["", c]);
    for (const [name, text] of presses) {
      const out = P.key(prompt, name, text);
      prompt = out.prompt;
      if (out.result) result = plain(out.result);
    }
  }
  return { prompt, result };
}

test("a text prompt types, edits and hands back its line on Return", () => {
  const { prompt, result } = feed(P.text("Name: "), "mian", ["Backspace"], ["Backspace"], ["Backspace"], "ain", ["Return"]);
  assert.deepEqual(result, { value: "main" });
  assert.equal(prompt, null);
});

test("a text prompt starts from a value, edits at the cursor, and Ctrl+U clears it", () => {
  let { prompt } = feed(P.text("Spec: ", { value: "kity" }), ["Left"], ["Left"], "t");
  assert.equal(prompt.value, "kitty");
  assert.equal(P.display(prompt), "Spec: kit▏ty");
  ({ prompt } = feed(prompt, ["Home"], ["Delete"], ["End"], "!"));
  assert.equal(prompt.value, "itty!");
  ({ prompt } = feed(prompt, ["ClearLine"]));
  assert.equal(prompt.value, "");
});

test("Escape cancels any prompt", () => {
  assert.deepEqual(feed(P.text("x"), "abc", ["Escape"]).result, { cancel: true });
  assert.deepEqual(feed(P.confirm("sure?"), ["Escape"]).result, { cancel: true });
  assert.deepEqual(feed(P.choice("pick", [{ key: "a", label: "a", value: 1 }]), ["Escape"]).result, { cancel: true });
});

test("Up and Down step a text prompt through its suggestions", () => {
  const start = P.text("Selector: ", { value: "HEADLESS-2", suggestions: ["Dell U2723QE", "HEADLESS-2", "SER-3"] });
  let { prompt } = feed(start, ["Down"]);
  assert.equal(prompt.value, "SER-3", "from the suggestion it holds, the next");
  ({ prompt } = feed(prompt, ["Down"]));
  assert.equal(prompt.value, "Dell U2723QE", "wrapping round");
  ({ prompt } = feed(prompt, ["Up"]));
  assert.equal(prompt.value, "SER-3");
});

test("a text prompt can refuse an empty line and keep going", () => {
  const { prompt, result } = feed(P.text("Name: ", { required: true }), ["Return"]);
  assert.equal(result, null);
  assert.equal(prompt.error, "Type something, or Esc to cancel.");
});

test("a choice prompt picks by key, or by Up/Down and Return", () => {
  const options = [
    { key: "m", label: "main", value: "main" },
    { key: "r", label: "right", value: "right" },
    { key: "", label: "zz", value: "zz" },
  ];
  assert.deepEqual(feed(P.choice("Slot", options), "r").result, { value: "right" });
  assert.deepEqual(feed(P.choice("Slot", options), ["Down"], ["Down"], ["Down"], ["Return"]).result, { value: "zz" });
  assert.equal(feed(P.choice("Slot", options), "x").result, null, "a key no option has does nothing");
});

test("a choice prompt reads like aerolayout's, with the highlighted option shown", () => {
  const options = [
    { key: "m", label: "main", value: 1 },
    { key: "1", label: "menu", value: 2 },
  ];
  assert.equal(P.display(P.choice("Assign to slot", options)), "Assign to slot: (m)ain, (1) menu? [Esc] cancel   → main");
});

test("an option's letter key shows where it is in the label, else before it", () => {
  const options = [
    { key: "m", label: "main", value: 1 },
    { key: "a", label: "mail", value: 2 },
    { key: "z", label: "right", value: 3 },
    { key: "", label: "spare", value: 4 },
  ];
  assert.equal(P.display(P.choice("Slot", options)), "Slot: (m)ain, m(a)il, (z) right, spare? [Esc] cancel   → main");
  assert.equal(P.optionText({ key: "1", label: "DP-1" }), "(1) DP-1", "a digit always goes before the label");
});

test("a confirm prompt takes y or n", () => {
  assert.deepEqual(feed(P.confirm("Delete?"), "y").result, { value: true });
  assert.deepEqual(feed(P.confirm("Delete?"), "n").result, { value: false });
  assert.equal(P.display(P.confirm("Delete slot 'a'?")), "Delete slot 'a'? (y/n)");
});

test("keys get letters by first letter, then the first free digit", () => {
  assert.deepEqual(plain(P.keys(["main", "menu", "right", "Mail"])), ["m", "1", "r", "2"]);
});

test("layout and workspace picks read as one-key prompts", () => {
  assert.equal(P.display(P.choice("Layout for desk 'solo'", P.options(["dual", "single", "solo"]))),
    "Layout for desk 'solo': (d)ual, (s)ingle, (1) solo? [Esc] cancel   → dual");
  const workspaces = P.options(["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]);
  assert.deepEqual(plain(workspaces.map((o) => o.key)), ["1", "2", "3", "4", "5", "6", "7", "8", "9", ""]);
  assert.equal(P.display(P.choice("Edit workspace", workspaces.slice(2, 3))), "Edit workspace: (3)? [Esc] cancel   → 3");
  assert.deepEqual(feed(P.choice("Edit workspace", workspaces), "3").result, { value: "3" });
});

test("a refused ratio reopens with the entry kept and the refusal under it", () => {
  const again = P.withError(P.text("Ratios: ", { value: "2:x" }), "bad ratio");
  assert.equal(P.display(again), "Ratios: 2:x▏");
  const { prompt, result } = feed(again, ["Backspace"], "1", ["Return"]);
  assert.equal(prompt, null);
  assert.deepEqual(result, { value: "2:1" });
});

test("a prompt can carry an error from the engine and keep its line", () => {
  const prompt = P.withError(P.text("Spec: ", { value: "[Tag" }), "spec '[Tag': a tag needs a closing ']'");
  assert.equal(prompt.value, "[Tag");
  assert.equal(prompt.error, "spec '[Tag': a tag needs a closing ']'");
  assert.equal(feed(prompt, "]").prompt.error, "", "typing clears it");
});

test("Qt keys become the names key() takes", () => {
  const Q = { Key_Return: 1, Key_Enter: 2, Key_Escape: 3, Key_Backspace: 4, Key_Delete: 5, Key_Left: 6, Key_Right: 7,
    Key_Home: 8, Key_End: 9, Key_Up: 10, Key_Down: 11, Key_U: 85, ControlModifier: 0x4000000 };
  assert.equal(P.keyName(2, 0, Q), "Return");
  assert.equal(P.keyName(4, 0, Q), "Backspace");
  assert.equal(P.keyName(85, Q.ControlModifier, Q), "ClearLine");
  assert.equal(P.keyName(85, 0, Q), "");
  assert.equal(P.typed("\u0015"), "", "a control character types nothing");
  assert.equal(P.typed("é"), "é");
});

test("an inline choice says its options in its own words", () => {
  const prompt = P.choice("Apply to (a)ll workspaces or (o)nly workspace 5?",
    [{ key: "a", label: "all workspaces", value: "all" }, { key: "o", label: "only workspace 5", value: "only" }],
    { inline: true });
  assert.equal(P.display(prompt), "Apply to (a)ll workspaces or (o)nly workspace 5? [Esc] cancel");
  assert.deepEqual(feed(prompt, "o").result, { value: "only" });
  assert.equal(P.help(prompt), "letter pick   ·   Esc cancel");
});

test("a choice's help names digits only when an option is keyed by one", () => {
  const slots = P.choice("Assign kitty to a slot on workspace 3",
    [{ key: "m", label: "main", value: "main" }, { key: "", label: "right", value: "right" }]);
  assert.equal(P.help(slots), "letter pick   ·   ↑/↓ Return pick   ·   Esc cancel", "slot keys are letters only");
  const monitors = P.choice("Which monitor", P.options([{ label: "DP-1", value: 1 }, { label: "DP-2", value: 2 }]));
  assert.ok(monitors.options.some((o) => /^[0-9]$/.test(o.key)), "the second DP gets a digit");
  assert.equal(P.help(monitors), "letter/digit pick   ·   ↑/↓ Return pick   ·   Esc cancel");
});

// --- the prompt by mouse: its controls, each a key press -------------------

// Feed presses by Panel.press names ("m", "Down", "Return", "Escape").
function pressAll(prompt, names) {
  const keys = names.map((n) => (n.length === 1 ? n : [n]));
  return feed(prompt, ...keys);
}

test("a choice prompt's controls: a chip per option with its key, the one the arrows are on selected, and Cancel", () => {
  const options = [
    { key: "m", label: "main", value: 1 },
    { key: "", label: "spare", value: 2 },
  ];
  const controls = plain(P.controls(P.choice("Slot", options)));
  assert.deepEqual(controls, [
    { kind: "chip", name: "chip:m", key: "m", label: "main", index: 0, selected: true },
    { kind: "chip", name: "chip:#1", key: "", label: "spare", index: 1, selected: false },
    { kind: "answer", name: "prompt:cancel", key: "Esc", label: "Cancel", press: "Escape", accented: false },
  ]);
});

test("an inline choice's chips select nothing: its options are picked by key only", () => {
  const prompt = P.choice("Apply to (a)ll or (o)nly?", [{ key: "a", label: "all", value: "all" }, { key: "o", label: "only", value: "only" }],
    { inline: true });
  assert.deepEqual(plain(P.controls(prompt)).filter((c) => c.kind === "chip").map((c) => c.selected), [false, false]);
});

test("a y/n prompt's controls are Yes and No; a text prompt's OK and Cancel", () => {
  assert.deepEqual(plain(P.controls(P.confirm("Delete?"))), [
    { kind: "answer", name: "prompt:yes", key: "y", label: "Yes", press: "y", accented: true },
    { kind: "answer", name: "prompt:no", key: "n", label: "No", press: "n", accented: false },
  ]);
  assert.deepEqual(plain(P.controls(P.text("Name: "))), [
    { kind: "answer", name: "prompt:ok", key: "Return", label: "OK", press: "Return", accented: true },
    { kind: "answer", name: "prompt:cancel", key: "Esc", label: "Cancel", press: "Escape", accented: false },
  ]);
  assert.deepEqual(plain(P.controls(null)), []);
});

test("a chip picks its option by the keys that pick it: its key, else the arrows to it and Return", () => {
  const options = [
    { key: "m", label: "main", value: "main" },
    { key: "", label: "x", value: "x" },
    { key: "", label: "y", value: "y" },
  ];
  const prompt = P.choice("Slot", options);
  assert.deepEqual(plain(P.pickPresses(prompt, 0)), ["m"]);
  assert.deepEqual(plain(P.pickPresses(prompt, 2)), ["Down", "Down", "Return"]);
  assert.deepEqual(pressAll(prompt, P.pickPresses(prompt, 2)).result, { value: "y" });
  const moved = feed(prompt, ["Down"], ["Down"]).prompt;
  assert.deepEqual(plain(P.pickPresses(moved, 1)), ["Up", "Return"]);
  assert.deepEqual(pressAll(moved, P.pickPresses(moved, 1)).result, { value: "x" });
  assert.deepEqual(plain(P.pickPresses(prompt, 7)), [], "no such option");
  assert.deepEqual(plain(P.pickPresses(P.confirm("?"), 0)), [], "no choice prompt");
});
