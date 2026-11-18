pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Prompts.js" as Prompts
import "Messages.js" as Messages
import "ui"

// The message band at the foot of the editor's page (Messages.js): the
// prompt being answered, as an input with its question in the accent colour
// (a refusal after it, on its line when there is room), or the last message
// on a tint of its kind (an accent tint for info, an urgent one for an
// error) with a stripe of that colour at its left. The band's own height is
// one line, kept whether or not it shows, so the view above never moves; a
// longer text grows it upwards, over the view's foot. Panel.qml decides what
// shows and when it fades.
//
// A prompt's controls follow its question (Prompts.controls): a choice's
// options as chips with their keys, y/n's Yes and No, a text prompt's OK
// and Cancel, a choice's Cancel. Each is a key: press(name) asks the panel
// to feed that key (Panel.press), choose(index) to pick that option
// (Prompts.pickPresses), so a click does what the keys do.
Item {
  id: root

  // "prompt", "info", "error" or "none" (Messages.kind).
  property string kind: "none"
  property string message: ""
  property var prompt: null
  property color foreground: Commons.Color.menu.text
  property color background: Commons.Color.menu.background
  property string fontFamily: Style.font.menuFamily

  signal press(string name)
  signal choose(int index)

  readonly property bool shown: kind !== "none"
  // What shows while the band fades out: the last kind shown.
  property string lastKind: "info"
  onKindChanged: if (kind !== "none") lastKind = kind
  readonly property string look: shown ? kind : lastKind

  readonly property int hairline: Math.max(1, Style.spacing.hairline)
  readonly property int padX: Style.spacing.xl
  readonly property int padY: Style.spacing.sm + Style.spacing.xxs
  readonly property int stripe: look === "prompt" ? 0 : Tokens.stripeWidth
  readonly property color tone: look === "error" ? Commons.Color.urgent : Commons.Color.accent

  readonly property var parts: Messages.promptParts(prompt, Prompts.display(prompt))
  // the options are the chips' to show: a choice's line is its question
  readonly property bool chipsOnly: !!prompt && (prompt.kind === "choice" || prompt.kind === "confirm")
  readonly property var controls: Prompts.controls(prompt)
  // a control's height, which the prompt's text lines up with
  readonly property int controlHeight: Style.font.body + Style.spacing.xxs * 4 + Style.spacing.xxs * 2
  readonly property string promptError: prompt && prompt.error ? String(prompt.error) : ""

  implicitHeight: Style.font.body + Math.round(Style.font.body * 0.4) + padY * 2
  height: implicitHeight

  Rectangle {
    id: box
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(root.height, content.implicitHeight + root.padY * 2)
    radius: Tokens.radius
    clip: true
    opacity: root.shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
      NumberAnimation { duration: root.shown ? 120 : 450; easing.type: Easing.OutCubic }
    }
    color: root.look === "prompt" ? root.background
      : Qt.tint(root.background, Commons.Util.alpha(root.tone, root.look === "error" ? 0.16 : 0.12))
    border.color: root.look === "prompt" ? Commons.Util.alpha(Commons.Color.accent, 0.85)
      : Commons.Util.alpha(root.tone, root.look === "error" ? 0.45 : 0.3)
    border.width: root.hairline

    // The kind's stripe, down the left edge.
    Rectangle {
      visible: root.stripe > 0
      x: root.hairline
      y: root.hairline
      width: root.stripe
      height: parent.height - root.hairline * 2
      topLeftRadius: Math.max(0, box.radius - root.hairline)
      bottomLeftRadius: Math.max(0, box.radius - root.hairline)
      color: root.tone
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: root.padX + root.stripe
      anchors.rightMargin: root.padX
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        visible: root.look !== "prompt"
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        maximumLineCount: 4
        elide: Text.ElideRight
        text: root.message
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // The question in the accent colour, then what is typed (a text
      // prompt); the answer the engine refused, and why, after it on the
      // same line when there is room, else under it; then the prompt's
      // controls, each a key (a choice's chips, Yes / No, OK / Cancel).
      Flow {
        width: parent.width
        visible: root.look === "prompt"
        spacing: Style.spacing.sm
        Text {
          width: Math.min(implicitWidth, parent.width)
          height: Math.max(implicitHeight, root.controlHeight)
          verticalAlignment: Text.AlignVCenter
          rightPadding: Style.spacing.lg
          textFormat: Text.StyledText
          wrapMode: Text.WordWrap
          maximumLineCount: 4
          elide: Text.ElideRight
          text: '<b><font color="' + String(Commons.Color.accent) + '">' + root.markup(root.parts.question) + "</font></b>"
            + (root.chipsOnly ? "" : root.markup(root.parts.rest))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: Math.min(implicitWidth, parent.width)
          height: Math.max(implicitHeight, root.controlHeight)
          verticalAlignment: Text.AlignVCenter
          rightPadding: Style.spacing.lg
          visible: root.promptError !== ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "✕ " + root.promptError
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Repeater {
          model: root.look === "prompt" ? root.controls : []
          delegate: ActionButton {
            required property var modelData
            objectName: modelData.name
            keyText: modelData.key
            text: modelData.label
            pixelSize: Style.font.body
            padY: Style.spacing.xxs
            selected: modelData.kind === "chip" && modelData.selected
            accented: modelData.kind === "answer" && modelData.accented
            onClicked: {
              if (modelData.kind === "chip") root.choose(modelData.index)
              else root.press(modelData.press)
            }
          }
        }
      }
    }
  }

  function markup(text) {
    // StyledText folds runs of spaces as HTML does; the prompts space their
    // parts with them ("[Enter] save  [Esc] cancel").
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/ {2,}/g, function(run) { return new Array(run.length + 1).join("&nbsp;") })
  }
}
