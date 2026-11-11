pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../Workspaces.js" as Workspaces

// The workspace switcher heading the Assignment and Layout tabs, one look
// on both: a section header ("WORKSPACE") and the workspaces by their keys,
// the current one in the accent colour, bold and underlined; [ ] step and
// the digits jump (the views' keys). `entries` are Workspaces.js's: the
// Assignment tab's Workspaces.numbers (1 to N), the Layout tab's
// Workspaces.strip, which leads with All workspaces (the layout's shared
// trees, a dot after it), puts a dot on a workspace with trees of its own
// and shows the ones using the shared trees dimmer. A click picks one.
Row {
  id: root

  property var entries: []
  signal picked(var workspace)

  spacing: Style.spacing.lg

  SectionHeader {
    anchors.verticalCenter: parent.verticalCenter
    title: "Workspace"
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xxs

    Repeater {
      model: root.entries
      delegate: Row {
        id: entry
        required property var modelData
        required property int index
        readonly property bool lit: modelData.current
        readonly property bool shared: !!modelData.shared
        readonly property bool afterAll: index > 0 && root.entries[index - 1].workspace === "default"
        spacing: Style.spacing.xxs

        Text {
          visible: entry.afterAll
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "·"
          color: Tokens.info
          font.family: Tokens.fontFamily
          font.pixelSize: Style.font.body
        }

        Item {
          width: key.implicitWidth + Style.spacing.sm * 2
          height: key.implicitHeight + Style.spacing.xs * 2
          Text {
            id: key
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: Workspaces.stripText(entry.modelData)
            color: entry.lit ? Tokens.header : entry.shared ? Tokens.info : Tokens.text
            opacity: entry.lit || !entry.shared ? 1 : 0.75
            font.family: Tokens.fontFamily
            font.pixelSize: Style.font.body
            font.bold: entry.lit
            font.italic: entry.shared
          }
          Rectangle {
            visible: entry.lit
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: key.implicitWidth
            height: Math.max(1, Style.spacing.xxs)
            radius: height / 2
            color: Tokens.header
          }
          MouseArea {
            anchors.fill: parent
            onClicked: root.picked(entry.modelData.workspace)
          }
        }
      }
    }
  }
}
