.pragma library

// Where the bar widget finds the plugin's running Engine when the bar does
// not hand it the service. Omarchy's built-in bar gives a widget a facade
// with serviceFor(); a replacement bar (a `kind: bar` plugin, such as a
// clone of omarchy.bar) gives only toggle / summon / hide. A `.pragma
// library` script is one instance per QML engine, shared by every file of
// the plugin that imports it, so the service registers here and the widget
// reads it back: still the one Engine, no second poller.

var engines = []

function register(engine) {
  if (engine && engines.indexOf(engine) < 0) engines.push(engine)
}

function unregister(engine) {
  var i = engines.indexOf(engine)
  if (i >= 0) engines.splice(i, 1)
}

// The engine registered last that is still there, or null.
function engine() {
  for (var i = engines.length - 1; i >= 0; i--) {
    if (engines[i]) return engines[i]
  }
  return null
}
