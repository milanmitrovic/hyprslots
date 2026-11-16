.pragma library

// Enabling the engine from the editor (docs/design.md §9, "Enabling the
// engine"). The plugin's service never writes anything by itself: while no
// engine runs (Protocol.parseReply's `absent`) the panel asks, saying what
// enabling writes and what it leaves alone, and its Enable runs the plugin's
// own tools/install-engine.sh, which puts the loader into Omarchy's
// workspace-layouts folder, reloads Hyprland and checks the engine runs.
// Pure, so node can test it (editor/tests/install.test.mjs).

var FOLDER = "~/.local/state/omarchy/workspace-layouts"

// What the panel asks, for input { absent, loadError (the loader's error,
// "" when it did not run), stale (a state was read before: the views show
// it), enabling (the script runs), error (its last run's error, "") }:
// { mode: "card" (the whole page, nothing to show behind it) | "banner"
// (over the stale views), title, lines[], action: { key, label }, busy,
// error }, or null while an engine runs.
function prompt(input) {
  if (!input || !input.absent) return null
  var out = { mode: input.stale ? "banner" : "card", title: "", lines: [],
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
        + " To undo, run tools/uninstall-engine.sh from the plugin's folder.",
    ]
  }
  if (out.busy) out.action.label = "Enabling…"
  return out
}

// The argv Enable runs: the install script, from its file URL
// (Qt.resolvedUrl of ../tools/install-engine.sh beside the editor's QML),
// through bash, so a copy that lost its executable bit still runs.
function enableCommand(scriptUrl) {
  var path = String(scriptUrl)
  if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice("file://".length))
  return ["bash", path]
}

function lastLine(text) {
  var lines = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  return lines.length ? lines[lines.length - 1] : ""
}

// What a run of the script says: { ok, message }, the message its last line
// of output when it worked, its error (without the script's name) when not.
function outcome(exitCode, stdout, stderr) {
  if (exitCode === 0) return { ok: true, message: lastLine(stdout) || "The hyprslots engine is running." }
  var err = String(stderr || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  var first = err.length ? err[0].replace(/^install-engine\.sh: /, "") : ""
  return { ok: false, message: first || "tools/install-engine.sh failed (exit " + exitCode + ")" }
}

// The help row while the panel asks (Help.js groups).
function helpGroups() {
  return [
    [{ key: "e", label: "enable" }],
    [{ key: "Tab", label: "view" }, { key: "q", label: "close" }],
  ]
}
