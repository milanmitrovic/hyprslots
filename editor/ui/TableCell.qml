import QtQuick
import qs.Commons

// One cell of a TableRow: body text, padded like its column title,
// elided, centred in the row. Callers set the width and what the row's
// state makes of its colour and weight.
Text {
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  leftPadding: Tokens.cellPadding
  textFormat: Text.PlainText
  color: Tokens.text
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
}
