.pragma library

// The message band of the panel (docs/design.md §9): the strip at the foot
// of the page that shows the current view's prompt while one is open, else
// its last message, tinted by kind. An info message fades after HOLD_MS; an
// error stays until the next key; a prompt stays while it is open. A
// message is known by a key naming its view and its count, so the same text
// said twice is two messages and shows again. Pure, so node can test it
// (editor/tests/messages.test.mjs).

var HOLD_MS = 4000

// What the band shows: "prompt" while a prompt is open, else "error" or
// "info" for a message not dismissed yet, else "none".
function kind(prompting, message, isError, dismissed) {
  if (prompting) return "prompt"
  if (message === undefined || message === null || String(message) === "" || dismissed) return "none"
  return isError ? "error" : "info"
}

// How long the band holds what it shows before it fades, in milliseconds:
// HOLD_MS for an info message, 0 (until something else replaces it) for an
// error, a prompt or nothing.
function holdMs(kind) {
  return kind === "info" ? HOLD_MS : 0
}

// Whether the next key press dismisses what the band shows: an error does
// (the key is the answer to it); an info message fades on its own.
function dismissedByKey(kind) {
  return kind === "error"
}

// The identity of a view's message: the view (its tab) and its count.
function key(view, seq) {
  return String(view) + ":" + String(seq)
}

// A prompt's line (Prompts.display) split for the band: the question (the
// prompt's label) and the rest, the answer being typed or the options.
// The whole line is the rest when it does not start with the label.
function promptParts(prompt, line) {
  var text = line === undefined || line === null ? "" : String(line)
  var label = prompt && prompt.label ? String(prompt.label) : ""
  if (label !== "" && text.indexOf(label) === 0) return { question: label, rest: text.slice(label.length) }
  return { question: "", rest: text }
}
