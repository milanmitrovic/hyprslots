import QtQuick
import qs.Commons

// What stands where a list or a picture is empty ("No windows",
// "No slots yet …", "No shared tree on this screen"): muted, centred.
// Wrapped between words, or inside one too long for a line (a path).
Text {
  horizontalAlignment: Text.AlignHCenter
  wrapMode: Text.Wrap
  textFormat: Text.PlainText
  color: Tokens.info
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.body
}
