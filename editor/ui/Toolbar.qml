pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// The help row as a toolbar (Help.buttons): every action of the view a
// button showing its label with the trigger key highlighted, an action of
// several keys a button per key and then its label, groups set apart;
// what the view would refuse now dim and inert. A click emits pressed(key)
// with the key's name as Panel.press takes it: the panel feeds it through
// its own key handling, so a click does exactly what the key does.
// objectName "toolbar:<key>" on each button, for the e2e smoke's clicks.
Flow {
  id: root

  property var cells: []
  property string accent: String(Commons.Color.accent)
  signal pressed(string key)

  spacing: Style.spacing.xxs

  // How many lines the toolbar takes (it should take one).
  function lineCount() {
    var tops = {}
    var n = 0
    for (var i = 0; i < root.children.length; i++) {
      var child = root.children[i]
      if (!child.visible || child.width <= 0 || child.height <= 0) continue
      var top = Math.round(child.y)
      if (!tops[top]) {
        tops[top] = true
        n++
      }
    }
    return n
  }

  function mark(glyph) {
    return '<b><font color="' + root.accent + '">' + String(glyph).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;") + "</font></b>"
  }

  Repeater {
    model: root.cells
    delegate: Row {
      id: cell
      required property var modelData
      required property int index
      readonly property bool gap: cell.modelData.first && cell.index > 0
      spacing: 1

      // a group's start, set apart from the one before
      Item {
        visible: cell.gap
        width: Style.spacing.md
        height: 1
      }

      InfoText {
        visible: cell.modelData.kind === "title" || cell.modelData.kind === "text"
        anchors.verticalCenter: parent.verticalCenter
        text: cell.modelData.kind === "title" ? cell.modelData.text + ":" : (cell.modelData.text || "")
      }

      ActionButton {
        visible: cell.modelData.kind === "button"
        objectName: visible ? "toolbar:" + cell.modelData.press : ""
        anchors.verticalCenter: parent.verticalCenter
        padX: Style.spacing.xs
        styled: true
        text: cell.modelData.styled || ""
        available: cell.modelData.available !== false
        onClicked: root.pressed(cell.modelData.press)
      }

      Repeater {
        model: cell.modelData.kind === "keys" ? cell.modelData.keys : []
        delegate: Item {
          id: key
          required property var modelData
          anchors.verticalCenter: parent ? parent.verticalCenter : undefined
          width: key.modelData.press === null ? glyph.implicitWidth : button.width
          height: Math.max(glyph.implicitHeight, button.height)
          // a key that is shown, not clicked (the digits: the workspace
          // switcher's)
          Text {
            id: glyph
            visible: key.modelData.press === null
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.StyledText
            text: root.mark(key.modelData.glyph)
            font.family: Tokens.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          ActionButton {
            id: button
            visible: key.modelData.press !== null
            objectName: visible ? "toolbar:" + key.modelData.press : ""
            anchors.verticalCenter: parent.verticalCenter
            padX: Style.spacing.xxs + 1
            styled: true
            text: root.mark(key.modelData.glyph)
            available: cell.modelData.available !== false
            onClicked: root.pressed(key.modelData.press)
          }
        }
      }

      Text {
        visible: cell.modelData.kind === "keys" && cell.modelData.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: Style.spacing.xxs
        rightPadding: Style.spacing.xs
        textFormat: Text.PlainText
        text: cell.modelData.label || ""
        color: Tokens.text
        opacity: cell.modelData.available !== false ? 0.85 : Tokens.faint
        font.family: Tokens.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
