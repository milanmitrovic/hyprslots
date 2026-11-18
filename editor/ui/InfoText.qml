import QtQuick
import qs.Commons

// Informational text: what a tab is about, notes on a header line, a
// section's hint, the desk line over the tabs. Muted and small; `urgent`
// for a warning that something is not yet in force ("● unsaved").
Text {
  property bool urgent: false
  textFormat: Text.PlainText
  color: urgent ? Tokens.urgent : Tokens.info
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.bodySmall
}
