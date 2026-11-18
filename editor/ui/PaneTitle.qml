import QtQuick
import qs.Commons

// A pane's title over the Layout tab's pictures and its slot list
// ("Screen 1 · Built-in", "Slots"): the accent colour and bold on the
// pane that has the keys, quieter on the others.
Text {
  property bool active: false
  textFormat: Text.PlainText
  elide: Text.ElideRight
  color: active ? Tokens.header : Tokens.text
  opacity: active ? 1 : 0.7
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.subtitle
  font.bold: active
}
