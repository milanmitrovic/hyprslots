.pragma library

// The editor's side of the hyprslots api protocol (docs/design.md §9). The
// engine runs inside Hyprland's Lua VM, so every call is one
//
//   hyprctl repl 'return hyprslots.api.call("<name>", "<json>")'
//
// whose output is a JSON object: {"ok": true, ...} or {"ok": false, "error": ...}.
// Pure: Engine.qml runs the commands and feeds the output back here.

// A Lua double-quoted string literal holding `text` exactly.
function luaString(text) {
  var out = '"'
  var s = String(text)
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i)
    var code = s.charCodeAt(i)
    if (c === "\\") out += "\\\\"
    else if (c === '"') out += '\\"'
    else if (c === "\n") out += "\\n"
    else if (c === "\r") out += "\\r"
    else if (code < 32 || code === 127) out += "\\" + ("00" + code).slice(-3)
    else out += c
  }
  return out + '"'
}

// The argv (no shell involved) that runs an api call with these arguments.
function callCommand(name, args) {
  var json = JSON.stringify(args || {})
  return ["hyprctl", "repl", "return hyprslots.api.call(" + luaString(name) + ", " + luaString(json) + ")"]
}

// The argv that reads the engine's state.
function stateCommand() {
  return ["hyprctl", "repl", "return hyprslots.api.state()"]
}

function failure(message) {
  return { ok: false, error: message }
}

function excerpt(text) {
  var s = String(text || "").trim()
  return s.length > 300 ? s.slice(0, 300) + "…" : s
}

// The reply to one command: the engine's JSON object, or a failure saying
// what went wrong (hyprctl failed, hyprslots is not loaded, garbage).
function parseReply(text, exitCode) {
  var body = String(text || "").trim()
  if (exitCode !== 0) {
    return failure("hyprctl exited " + exitCode + ": " + (excerpt(body) || "no output"))
  }
  if (body === "") {
    return failure("hyprslots did not answer: empty reply")
  }
  var value
  try {
    value = JSON.parse(body)
  } catch (e) {
    return failure("hyprslots did not answer: " + excerpt(body))
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return failure("hyprslots did not answer: " + excerpt(body))
  }
  if (value.ok !== true) {
    return failure(typeof value.error === "string" && value.error !== "" ? value.error : "the call failed")
  }
  return value
}

// Socket2 events after which the editor reads state again. The engine's own
// "custom>>hyprslots changed <seq>" is the contract; seq restarts at 0 when
// Hyprland reloads its config, so it is no ordering, only "something
// changed". Window events are added because a title or a move changes what
// the Assignment view shows without the engine announcing it.
var REREAD_EVENTS = {
  openwindow: true,
  closewindow: true,
  movewindow: true,
  movewindowv2: true,
  windowtitle: true,
  windowtitlev2: true,
  configreloaded: true,
  monitoradded: true,
  monitoraddedv2: true,
  monitorremoved: true,
  monitorremovedv2: true,
}

function meansReread(name, data) {
  if (name === "custom") return String(data || "").indexOf("hyprslots changed") === 0
  return REREAD_EVENTS[name] === true
}
