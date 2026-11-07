// The editor's side of the api protocol (docs/design.md §9): the hyprctl
// command lines it runs and how it reads their replies.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const P = load("Protocol.js");

test("a call is one hyprctl repl returning hyprslots.api.call with the JSON as a Lua string", () => {
  assert.deepEqual(Array.from(P.callCommand("assign", { address: "0x1", desk: 3, slot: "main" })), [
    "hyprctl",
    "repl",
    'return hyprslots.api.call("assign", "{\\"address\\":\\"0x1\\",\\"desk\\":3,\\"slot\\":\\"main\\"}")',
  ]);
});

test("state is read with hyprslots.api.state()", () => {
  assert.deepEqual(Array.from(P.stateCommand()), ["hyprctl", "repl", "return hyprslots.api.state()"]);
});

test("backslashes, quotes and control characters cannot break out of the Lua string", () => {
  const command = P.callCommand("x", { title: 'a"b\\c\nd]]e' });
  assert.equal(command[2], 'return hyprslots.api.call("x", "{\\"title\\":\\"a\\\\\\"b\\\\\\\\c\\\\nd]]e\\"}")');
});

test("a JSON reply is the reply", () => {
  const reply = P.parseReply('{"ok":true,"seq":4}\n', 0);
  assert.equal(reply.ok, true);
  assert.equal(reply.seq, 4);
});

test("an {ok:false} reply keeps the engine's error", () => {
  assert.deepEqual({ ...P.parseReply('{"ok":false,"error":"no open window 0x9"}', 0) }, {
    ok: false,
    error: "no open window 0x9",
  });
});

test("text that is no JSON object becomes a failure that says what came back", () => {
  const reply = P.parseReply("[string \"return hyprslots.api.state()\"]:1: attempt to index a nil value (global 'hyprslots')", 0);
  assert.equal(reply.ok, false);
  assert.match(reply.error, /^hyprslots did not answer: \[string/);
});

test("hyprctl failing is a failure with its exit status and output", () => {
  const reply = P.parseReply("Couldn't connect to the Hyprland socket", 1);
  assert.equal(reply.ok, false);
  assert.equal(reply.error, "hyprctl exited 1: Couldn't connect to the Hyprland socket");
});

test("an empty reply is a failure", () => {
  assert.equal(P.parseReply("", 0).ok, false);
});

test("the engine's change event and window events mean re-read state; others do not", () => {
  assert.equal(P.meansReread("custom", "hyprslots changed 12"), true);
  assert.equal(P.meansReread("custom", "something else"), false);
  for (const name of ["openwindow", "closewindow", "movewindowv2", "windowtitlev2", "configreloaded"]) {
    assert.equal(P.meansReread(name, ""), true, name);
  }
  assert.equal(P.meansReread("activewindowv2", "0x1"), false);
});

test("a raw control character becomes a three-digit Lua escape, so a digit after it stays a digit", () => {
  assert.equal(P.luaString("a\u0001" + "2"), '"a\\0012"');
});
