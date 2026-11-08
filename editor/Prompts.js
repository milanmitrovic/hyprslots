.pragma library

// The prompts of every view of the panel, after aerolayout's
// prompt_input / prompt_key: a line of text typed in place, a pick among
// keyed options, a yes/no question. While one is open it owns the keyboard
// (the panel routes every key to it, Tab, q and Esc included); Esc cancels.
// Pure, so node can test it (editor/tests/prompts.test.mjs).
//
// key(prompt, name, text) takes a key by name ("Return", "Escape",
// "Backspace", "Delete", "Left", "Right", "Home", "End", "Up", "Down",
// "ClearLine", or "" for a plain character) and the text it types, and
// returns { prompt, result }: prompt is the prompt to keep showing (null once
// it is answered), result null, { cancel: true } or { value }.

// A text prompt. opts: value (the starting line), suggestions (what Up/Down
// step through), required (refuse an empty line).
function text(label, opts) {
  opts = opts || {}
  var value = opts.value !== undefined && opts.value !== null ? String(opts.value) : ""
  return {
    kind: "text",
    label: label,
    value: value,
    cursor: value.length,
    suggestions: opts.suggestions || [],
    required: !!opts.required,
    error: "",
  }
}

// A pick among options [{ key, label, value }]; a key of "" is picked with
// the arrows only. opts.inline: the label names the options itself
// ("Apply to (a)ll workspaces or (o)nly workspace 5?"), which are picked by
// key only.
function choice(label, options, opts) {
  return { kind: "choice", label: label, options: options, index: 0, error: "", inline: !!(opts && opts.inline) }
}

function confirm(label) {
  return { kind: "confirm", label: label, error: "" }
}

function copy(prompt) {
  var out = {}
  for (var k in prompt) out[k] = prompt[k]
  return out
}

// The prompt again with an error under it (the engine refused its answer).
function withError(prompt, error) {
  var out = copy(prompt)
  out.error = error || ""
  return out
}

function answered(value) {
  return { prompt: null, result: { value: value } }
}

function stay(prompt) {
  return { prompt: prompt, result: null }
}

function textKey(prompt, name, typed) {
  var p = copy(prompt)
  var v = p.value
  var c = p.cursor
  switch (name) {
  case "Return":
    if (p.required && v.trim() === "") {
      p.error = "Type something, or Esc to cancel."
      return stay(p)
    }
    return answered(v)
  case "Backspace":
    if (c > 0) {
      p.value = v.slice(0, c - 1) + v.slice(c)
      p.cursor = c - 1
    }
    break
  case "Delete":
    p.value = v.slice(0, c) + v.slice(c + 1)
    break
  case "Left":
    p.cursor = Math.max(0, c - 1)
    return stay(p)
  case "Right":
    p.cursor = Math.min(v.length, c + 1)
    return stay(p)
  case "Home":
    p.cursor = 0
    return stay(p)
  case "End":
    p.cursor = v.length
    return stay(p)
  case "ClearLine":
    p.value = ""
    p.cursor = 0
    break
  case "Up":
  case "Down":
    var list = p.suggestions
    if (list.length === 0) return stay(p)
    var at = list.indexOf(v)
    var step = name === "Down" ? 1 : -1
    var next = at < 0 ? (step > 0 ? 0 : list.length - 1) : (at + step + list.length) % list.length
    p.value = String(list[next])
    p.cursor = p.value.length
    break
  default:
    if (!typed) return stay(p)
    p.value = v.slice(0, c) + typed + v.slice(c)
    p.cursor = c + typed.length
  }
  p.error = ""
  return stay(p)
}

function choiceKey(prompt, name, typed) {
  var options = prompt.options
  if (typed) {
    for (var i = 0; i < options.length; i++) {
      if (options[i].key !== "" && options[i].key === typed) return answered(options[i].value)
    }
  }
  if (prompt.inline) return stay(prompt)
  if (name === "Up" || name === "Down") {
    var p = copy(prompt)
    p.index = Math.max(0, Math.min(options.length - 1, prompt.index + (name === "Up" ? -1 : 1)))
    return stay(p)
  }
  if (name === "Return" && options.length > 0) return answered(options[prompt.index].value)
  return stay(prompt)
}

function key(prompt, name, typed) {
  if (name === "Escape") return { prompt: null, result: { cancel: true } }
  if (prompt.kind === "text") return textKey(prompt, name, typed)
  if (prompt.kind === "choice") return choiceKey(prompt, name, typed)
  if (typed === "y" || typed === "Y") return answered(true)
  if (typed === "n" || typed === "N") return answered(false)
  return stay(prompt)
}

// "(m)ain" when the key is the label's first letter, else "(1) menu"; a
// label with no key stands alone.
function optionText(option) {
  var label = String(option.label)
  if (option.key === "") return label
  if (option.key === label.charAt(0).toLowerCase() && option.key === label.charAt(0)) return "(" + option.key + ")" + label.slice(1)
  return "(" + option.key + ") " + label
}

// The prompt as one line: the text with a cursor mark, the options with the
// highlighted one, or the question.
function display(prompt) {
  if (!prompt) return ""
  if (prompt.kind === "text") return prompt.label + prompt.value.slice(0, prompt.cursor) + "▏" + prompt.value.slice(prompt.cursor)
  if (prompt.kind === "choice" && prompt.inline) return prompt.label + " [Esc] cancel"
  if (prompt.kind === "choice") {
    var labels = prompt.options.map(optionText)
    var current = prompt.options[prompt.index]
    return prompt.label + ": " + labels.join(", ") + "? [Esc] cancel" + (current ? "   → " + current.label : "")
  }
  return prompt.label + " (y/n)"
}

// What the controls strip says while a prompt is open.
function help(prompt) {
  if (!prompt) return ""
  if (prompt.kind === "text") {
    return "type   ·   ←/→ Home End move   ·   Backspace Delete Ctrl+U edit"
      + (prompt.suggestions.length ? "   ·   ↑/↓ suggestions" : "") + "   ·   Return ok   ·   Esc cancel"
  }
  if (prompt.kind === "choice" && prompt.inline) return "letter pick   ·   Esc cancel"
  if (prompt.kind === "choice") return "letter/digit pick   ·   ↑/↓ Return pick   ·   Esc cancel"
  return "y yes   ·   n / Esc no"
}

// One key per name: its first letter (lower case) unless taken, else the
// first free digit, else "" (aerolayout's rule).
function keys(names) {
  var used = {}
  var out = []
  for (var i = 0; i < names.length; i++) {
    var k = String(names[i]).charAt(0).toLowerCase()
    if (k === "" || used[k] || !/[a-z0-9]/.test(k)) {
      k = ""
      for (var n = 1; n <= 9; n++) {
        if (!used[String(n)]) {
          k = String(n)
          break
        }
      }
    }
    if (k !== "") used[k] = true
    out.push(k)
  }
  return out
}

// Options for names (or [{ label, value }]) keyed by keys().
function options(items) {
  var labels = items.map(function(item) { return typeof item === "object" ? item.label : item })
  var ks = keys(labels)
  return items.map(function(item, i) {
    return typeof item === "object" ? { key: ks[i], label: item.label, value: item.value }
      : { key: ks[i], label: item, value: item }
  })
}

// Numbered options (1..9, then arrows only), for lists whose labels are not
// names (windows, monitors).
function numbered(items) {
  return items.map(function(item, i) {
    return { key: i < 9 ? String(i + 1) : "", label: item.label, value: item.value }
  })
}

// The name key() takes for a Qt key (`Q` is QML's Qt, or a stand-in), ""
// for one that only types.
function keyName(key, modifiers, Q) {
  if ((modifiers & Q.ControlModifier) && key === Q.Key_U) return "ClearLine"
  var names = [
    ["Key_Return", "Return"], ["Key_Enter", "Return"], ["Key_Escape", "Escape"], ["Key_Backspace", "Backspace"],
    ["Key_Delete", "Delete"], ["Key_Left", "Left"], ["Key_Right", "Right"], ["Key_Home", "Home"], ["Key_End", "End"],
    ["Key_Up", "Up"], ["Key_Down", "Down"],
  ]
  for (var i = 0; i < names.length; i++) if (key === Q[names[i][0]]) return names[i][1]
  return ""
}

// The text a key types: "" for control characters.
function typed(text) {
  if (!text) return ""
  for (var i = 0; i < text.length; i++) if (text.charCodeAt(i) < 32 || text.charCodeAt(i) === 127) return ""
  return text
}
