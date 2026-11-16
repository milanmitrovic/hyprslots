import QtQuick
import qs.Commons
import qs.Commons as Commons

// A choice that is on or off: a box (the accent filled with a check mark
// when `checked`), the key that toggles it as a KeyCap, then its label,
// wrapping. A click anywhere on it does what the key does: the caller feeds
// the key through the panel's handler (Panel.press). The enable prompt's
// choices (Install.js) use it.
Item {
  id: root

  property string text: ""
  property string keyText: ""
  property bool checked: false
  property bool available: true
  property int pixelSize: Style.font.bodySmall

  signal clicked()

  readonly property bool hot: mouse.containsMouse && root.available

  implicitHeight: Math.max(box.height, label.implicitHeight) + Style.spacing.xxs * 2
  implicitWidth: box.width + cap.width + label.implicitWidth + Style.spacing.md * 2
  opacity: root.available ? 1 : Tokens.faint

  Rectangle {
    id: box
    readonly property int size: Math.round(root.pixelSize * 1.15)
    anchors.verticalCenter: parent.verticalCenter
    width: size
    height: size
    radius: Math.min(Tokens.radius, size / 4)
    color: root.checked ? Commons.Color.accent : (root.hot ? Commons.Util.alpha(Tokens.text, 0.08) : "transparent")
    border.width: Math.max(1, Style.spacing.hairline)
    border.color: root.checked ? Commons.Color.accent
      : Commons.Util.alpha(Tokens.text, root.hot ? 0.8 : 0.5)
    Text {
      anchors.centerIn: parent
      visible: root.checked
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.menu.background
      font.family: Tokens.fontFamily
      font.pixelSize: Math.round(box.size * 0.8)
      font.bold: true
    }
  }
  KeyCap {
    id: cap
    x: box.width + Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    text: root.keyText
    pixelSize: root.pixelSize
  }
  Text {
    id: label
    x: cap.x + cap.width + Style.spacing.md
    width: root.width - x
    anchors.verticalCenter: parent.verticalCenter
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: root.text
    color: Tokens.text
    font.family: Tokens.fontFamily
    font.pixelSize: root.pixelSize
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.available
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
