.pragma library

// Launching apps from the editor (docs/design.md §9): each workspace's
// launch setting, never (the default), on demand (Launch missing) or at
// login (also when Hyprland starts), on its Assignment page with a key that
// cycles it (api set_launch); while it is not never, the command each slot
// with an app launches with, or why it can't (state.launch_status), and
// Launch missing (api launch_missing). The editor never edits the commands:
// a command from config.lua is shown as such. Pure, so node can test it
// (editor/tests/launch.test.mjs).

var MODES = ["never", "on_demand", "at_login"]
var WORDS = { never: "never", on_demand: "on demand", at_login: "at login" }

function mode(state, n) {
  var modes = state && state.launch ? state.launch : null
  var m = modes ? modes[String(n)] : null
  return WORDS[m] ? m : "never"
}

function next(m) {
  var i = Math.max(0, MODES.indexOf(m)) // anything else reads as never
  return MODES[(i + 1) % MODES.length]
}

// Whether config.lua sets workspace n's launch setting in code (all of
// them, "launch", or that one, "launch.<n>"), or loads no editor data.
function readOnly(state, n) {
  var cfg = state && state.config
  if (!cfg) return false
  if (cfg.editable === false) return true
  var list = Array.isArray(cfg.read_only) ? cfg.read_only : []
  return list.indexOf("launch") >= 0 || list.indexOf("launch." + n) >= 0
}

// The quiet line under the page's header: "Launch apps: on demand".
function line(state, n) {
  return "Launch apps: " + WORDS[mode(state, n)] + (readOnly(state, n) ? " (set in your config)" : "")
}

// What set_launch's reply says.
function setText(reply) {
  var n = reply.workspace
  if (reply.mode === "on_demand") return "Workspace " + n + " launches its missing apps when you press L. Ctrl+S saves."
  if (reply.mode === "at_login") return "Workspace " + n + " launches its missing apps at login, and when you press L. Ctrl+S saves."
  return "Workspace " + n + " launches no apps. Ctrl+S saves."
}

// Whether workspace n's slots show their command status (it launches).
function shows(state, n) {
  return mode(state, n) !== "never"
}

// Launch missing works where the setting is not never.
function canLaunch(state, n) {
  return mode(state, n) !== "never"
}

// A slot's command status on workspace n: { text (the command, marked
// when config.lua's; else why it can't launch), urgent (it can't) }, or
// null where nothing shows (the workspace launches nothing, or no app is
// assigned to the slot there).
function status(state, n, slot) {
  if (!shows(state, n)) return null
  var all = state && state.launch_status ? state.launch_status[String(n)] : null
  var s = all ? all[slot] : null
  if (!s) return null
  if (s.command) return { text: String(s.command) + (s.source === "config" ? " (from your config)" : ""), urgent: false }
  return { text: String(s.reason || "can't launch"), urgent: true }
}

// The program a command runs, by name: "/usr/bin/foot --server" is foot.
function program(command) {
  var first = String(command || "").trim().split(/\s+/)[0] || ""
  return first.slice(first.lastIndexOf("/") + 1)
}

// "can't launch: set a command" for notes: "can't launch notes: set a command".
function cannotText(item) {
  var reason = String(item.reason || "")
  var head = "can't launch: "
  if (reason.indexOf(head) === 0) return "can't launch " + item.slot + ": " + reason.slice(head.length)
  return item.slot + ": " + reason
}

// launch_missing's reply as the message band says it: { text, error (it
// could launch nothing it was asked to) }.
function missingText(reply) {
  var launched = reply.launched || []
  var pending = reply.pending || []
  var open = reply.open || []
  var cannot = reply.cannot || []
  var parts = []
  if (launched.length) {
    parts.push("Launched " + launched.map(function(l) { return program(l.command) + " for " + l.slot }).join(", "))
  }
  if (pending.length) {
    parts.push("the app" + (pending.length === 1 ? " for " : "s for ") + pending.join(", ")
      + (pending.length === 1 ? " is" : " are") + " on the way already")
  }
  cannot.forEach(function(c) { parts.push(cannotText(c)) })
  if (parts.length === 0) {
    // open[] names only slots whose app is open elsewhere; a slot its
    // window fills is not listed, so nothing listed may mean all are full.
    return { text: "Nothing to launch on workspace " + reply.workspace + ": "
      + (open.length ? "the app" + (open.length === 1 ? " for " : "s for ") + open.join(", ")
        + (open.length === 1 ? " is" : " are") + " open already."
        : "no empty slot there waits for an app."), error: false }
  }
  var text = parts.join("; ") + "."
  return { text: text.charAt(0).toUpperCase() + text.slice(1), error: launched.length === 0 && pending.length === 0 }
}

// The page's launch keys for its help row (Help.js items): m cycles the
// setting (dim where config.lua sets it), L launches the missing apps (dim
// while the setting is never).
function helpItems(state, n) {
  var cycle = { key: "m", label: "launch mode" }
  if (!state || readOnly(state, n)) cycle.enabled = false
  var missing = { key: "L", label: "launch missing" }
  if (!state || !canLaunch(state, n)) missing.enabled = false
  return [cycle, missing]
}
