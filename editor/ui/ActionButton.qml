import QtQuick
import qs.Commons
import qs.Commons as Commons

// A clickable action (named apart from qs.Ui's Button, which the panel
// imports too): the help row's toolbar buttons (each action's label
// with its trigger key highlighted, Help.js's StyledText), a prompt's
// chips (an option with its key cap), Yes / No and OK / Cancel. A click
// does what the key does: the caller feeds the key through the panel's
// own handler (Panel.press), so the mouse and the keyboard are one path.
//
// States, from the theme (qs.Commons Style's control tokens, like Omarchy's
// own Button): at rest a faint fill, hovered the hover fill and outline,
// pressed the pressed fill; `selected` (the option the arrows are on) the
// selection's accent fill; `accented` (the answer Return gives: OK, Yes)
// an accent outline; not `available` (the view would refuse the key) dim
// and inert. `keyText` puts a KeyCap before the label.
Rectangle {
  id: root

  property string text: ""
  // `text` is Qt StyledText (a toolbar label, its key highlighted)
  property bool styled: false
  property string keyText: ""
  property bool available: true
  property bool selected: false
  property bool accented: false
  property int pixelSize: Style.font.bodySmall
  property int padX: Style.spacing.md
  property int padY: Style.spacing.xxs

  signal clicked()

  readonly property bool hot: mouse.containsMouse && root.available
  readonly property color ink: root.selected ? Tokens.selectedText : Tokens.text

  implicitWidth: content.implicitWidth + padX * 2
  implicitHeight: Math.max(label.implicitHeight, cap.visible ? cap.implicitHeight : 0) + padY * 2
  width: implicitWidth
  height: implicitHeight
  radius: Tokens.radius
  opacity: root.available ? 1 : Tokens.faint
  color: mouse.pressed && root.available ? Style.pressedFillFor(Tokens.text, Commons.Color.accent)
    : root.selected ? Tokens.selectionFill
    : root.hot ? Style.hoverFillFor(Tokens.text, Commons.Color.accent)
    : Tokens.restFill
  border.width: Math.max(1, Style.spacing.hairline)
  border.color: root.selected || root.accented ? Commons.Util.alpha(Commons.Color.accent, root.hot ? 1 : 0.7)
    : root.hot ? Style.hoverBorderFor(Tokens.text, Commons.Color.accent)
    : "transparent"

  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  scale: mouse.pressed && root.available ? 0.97 : 1

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.sm
    KeyCap {
      id: cap
      visible: root.keyText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.keyText
      ink: root.selected ? Tokens.selectedText : Commons.Color.accent
      pixelSize: root.pixelSize
    }
    Text {
      id: label
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: root.styled ? Text.StyledText : Text.PlainText
      text: root.text
      color: root.ink
      font.family: Tokens.fontFamily
      font.pixelSize: root.pixelSize
      font.bold: root.selected
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    scale: 1 / root.scale
    hoverEnabled: true
    cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.available) root.clicked()
  }
}
