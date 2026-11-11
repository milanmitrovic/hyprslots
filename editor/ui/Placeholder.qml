import QtQuick
import qs.Commons

// What stands where a list or a picture is empty ("No windows",
// "No slots yet …", "No shared tree on this screen"): muted, centred.
Text {
  horizontalAlignment: Text.AlignHCenter
  wrapMode: Text.WordWrap
  textFormat: Text.PlainText
  color: Tokens.info
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.body
}
