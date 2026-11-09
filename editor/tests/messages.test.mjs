// The message band's model (Messages.js): what it shows, how long, and what
// dismisses it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const M = load("Messages.js");

test("an open prompt is what the band shows, whatever the message", () => {
  assert.equal(M.kind(true, "", false, false), "prompt");
  assert.equal(M.kind(true, "Saved.", true, true), "prompt", "even over a dismissed error");
});

test("a message shows by its kind until it is dismissed; no message shows nothing", () => {
  assert.equal(M.kind(false, "Saved /x/slots.lua.", false, false), "info");
  assert.equal(M.kind(false, "there is a slot 'main' already", true, false), "error");
  assert.equal(M.kind(false, "Saved.", false, true), "none");
  assert.equal(M.kind(false, "", true, false), "none");
  assert.equal(M.kind(false, null, false, false), "none");
});

test("info fades after HOLD_MS; an error, a prompt and nothing stay", () => {
  assert.equal(M.HOLD_MS, 4000);
  assert.equal(M.holdMs("info"), 4000);
  assert.equal(M.holdMs("error"), 0);
  assert.equal(M.holdMs("prompt"), 0);
  assert.equal(M.holdMs("none"), 0);
});

test("the next key dismisses an error only", () => {
  assert.equal(M.dismissedByKey("error"), true);
  assert.equal(M.dismissedByKey("info"), false);
  assert.equal(M.dismissedByKey("prompt"), false, "the prompt owns the key");
  assert.equal(M.dismissedByKey("none"), false);
});

test("a message is known by its view and count: the same text said again is new", () => {
  assert.equal(M.key(1, 7), "1:7");
  assert.notEqual(M.key(1, 7), M.key(1, 8));
  assert.notEqual(M.key(0, 7), M.key(1, 7));
});

test("a prompt's line splits into its question and the rest", () => {
  const text = { kind: "text", label: "Rename 'right' to " };
  assert.deepEqual({ ...M.promptParts(text, "Rename 'right' to ma▏in") }, { question: "Rename 'right' to ", rest: "ma▏in" });
  const choice = { kind: "choice", label: "Assign t-stray to a slot on workspace 3" };
  assert.deepEqual({ ...M.promptParts(choice, "Assign t-stray to a slot on workspace 3: (m)ain? [Esc] cancel") },
    { question: "Assign t-stray to a slot on workspace 3", rest: ": (m)ain? [Esc] cancel" });
  assert.deepEqual({ ...M.promptParts({ label: "Other" }, "Delete it? (y/n)") }, { question: "", rest: "Delete it? (y/n)" });
  assert.deepEqual({ ...M.promptParts(null, undefined) }, { question: "", rest: "" });
});
