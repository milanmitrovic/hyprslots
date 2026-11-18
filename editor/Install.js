.pragma library

// Enabling the engine from the editor (docs/design.md §9, "Enabling the
// engine"). The plugin's service never writes anything by itself: while no
// engine runs (Protocol.parseReply's `absent`) the panel asks, saying what
// enabling writes and what it leaves alone, and its Enable runs the plugin's
// own tools/install-engine.sh, which puts the loader into Omarchy's
// workspace-layouts folder, reloads Hyprland and checks the engine runs.
// Pure, so node can test it (editor/tests/install.test.mjs).

var FOLDER = "~/.local/state/omarchy/workspace-layouts"
// The uninstall script by its full path, so the prompt says where it is.
var UNINSTALL = "~/.config/omarchy/plugins/io.github.milanmitrovic.hyprslots/tools/uninstall-engine.sh"

// What Enable also does, as chosen in the prompt (k, m, or a click on the
// box): bind the editor's keys (Super+Ctrl+Y opens it, Super+Ctrl+Shift+C
// captures the focused workspace; each only where it is free), off unless
// asked; add hyprslots' entries to the Omarchy menu, on.
function defaults() {
  return { keys: false, menu: true }
}

var CHOICES = [
  { id: "keys", key: "k", label: "Also bind Super+Ctrl+Y to open the editor and Super+Ctrl+Shift+C to capture" },
  { id: "menu", key: "m", label: "Add hyprslots to the Omarchy menu (Open editor, Capture this workspace, Launch missing apps)" },
]

// Whether `text` (a key typed) toggles a choice.
function toggles(text) {
  return CHOICES.some(function(c) { return c.key === text })
}

// The choices with the one keyed `text` toggled.
function toggle(options, text) {
  var out = { keys: !!options.keys, menu: !!options.menu }
  CHOICES.forEach(function(c) { if (c.key === text) out[c.id] = !out[c.id] })
  return out
}

// What the panel asks, for input { absent, loadError (the loader's error,
// "" when it did not run), stale (a state was read before: the views show
// it), enabling (the script runs), error (its last run's error, ""),
// options (the choices, defaults() when none) }: { mode: "card" (the whole
// page, nothing to show behind it) | "banner" (over the stale views),
// title, lines[], options: [{ id, key, label, checked }], action: { key,
// label }, busy, error }, or null while an engine runs.
function prompt(input) {
  if (!input || !input.absent) return null
  var chosen = input.options || defaults()
  var out = { mode: input.stale ? "banner" : "card", title: "", lines: [],
    options: CHOICES.map(function(c) { return { id: c.id, key: c.key, label: c.label, checked: !!chosen[c.id] } }),
    action: { key: "e", label: "Enable" }, busy: !!input.enabling, error: String(input.error || "") }
  if (input.loadError) {
    out.mode = "card"
    out.title = "The hyprslots engine failed to load"
    out.lines = [String(input.loadError), "Fix that, then try again: it reloads Hyprland."]
    out.action.label = "Try again"
  } else if (input.stale) {
    out.title = "The hyprslots engine is not running: what shows here is from before."
    out.lines = ["Enable it? That adds one file to Omarchy's workspace-layouts folder and reloads Hyprland;"
      + " your Hyprland config is not edited."]
  } else {
    out.title = "Enable the hyprslots engine?"
    out.lines = [
      "hyprslots puts your windows into their slots from inside Hyprland. Enabling it adds one file,"
        + " zz-hyprslots.lua, to Omarchy's workspace-layouts folder (" + FOLDER + "), which Omarchy loads"
        + " with its own saved layouts, and reloads Hyprland.",
      "It doesn't edit your Hyprland config. Super+1..9 then switch every screen at once."
        + " To undo, run " + UNINSTALL + ".",
    ]
  }
  if (out.busy) out.action.label = "Enabling…"
  return out
}

// The argv Enable runs: the install script, from its file URL
// (Qt.resolvedUrl of ../tools/install-engine.sh beside the editor's QML),
// through bash, so a copy that lost its executable bit still runs; with
// --keys and --menu as chosen (a choice left off passes nothing: the
// script then keeps what an earlier install set up).
function enableCommand(scriptUrl, options) {
  var path = String(scriptUrl)
  if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice("file://".length))
  var out = ["bash", path]
  if (options && options.keys) out.push("--keys")
  if (options && options.menu) out.push("--menu")
  return out
}

function lastLine(text) {
  var lines = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  return lines.length ? lines[lines.length - 1] : ""
}

function sentence(line) {
  return /[.!?:]$/.test(line) ? line : line + "."
}

// What a run of the script says: { ok, message }, when it worked its lines
// about the keys and the menu (a key bound, or left as it was) and its last
// line; its error (without the script's name) when not.
function outcome(exitCode, stdout, stderr) {
  if (exitCode === 0) {
    var last = lastLine(stdout)
    var said = String(stdout || "").split("\n").map(function(l) { return l.trim() })
      .filter(function(l) { return l !== "" && l !== last && (l.indexOf("Super+") >= 0 || /menu/i.test(l)) })
    if (!last) return { ok: true, message: said.concat(["The hyprslots engine is running."]).map(sentence).join(" ") }
    return { ok: true, message: said.length ? said.concat([last]).map(sentence).join(" ") : last }
  }
  var err = String(stderr || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  var first = err.length ? err[0].replace(/^install-engine\.sh: /, "") : ""
  return { ok: false, message: first || "tools/install-engine.sh failed (exit " + exitCode + ")" }
}

// The help row while the panel asks (Help.js groups).
function helpGroups() {
  return [
    [{ key: "e", label: "enable" }],
    [{ key: "k", label: "keys" }, { key: "m", label: "menu" }],
    [{ key: "Tab", label: "view" }, { key: "q", label: "close" }],
  ]
}
