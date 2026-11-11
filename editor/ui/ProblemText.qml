import QtQuick
import qs.Commons

// Why a tab cannot work: the engine unreachable, a config error, read
// only. The urgent colour, body size, shown only when there is one.
Text {
  visible: text !== ""
  textFormat: Text.PlainText
  wrapMode: Text.WordWrap
  leftPadding: Tokens.textInset
  rightPadding: Tokens.cellPadding
  color: Tokens.urgent
  font.family: Tokens.fontFamily
  font.pixelSize: Style.font.body
}
