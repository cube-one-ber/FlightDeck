import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// GNOME AdwToastOverlay-style floating bottom notification capsule for transient
// action confirmations ("Checklist copied", "Pinned to the bar", etc.).
Item {
    id: root

    property string text: ""
    property bool showing: false

    function show(message) {
        if (!message) return
        root.text = message
        root.showing = true
        hideTimer.restart()
    }

    function dismiss() {
        hideTimer.stop()
        root.showing = false
    }

    Timer {
        id: hideTimer
        interval: 2800
        onTriggered: root.showing = false
    }

    Kirigami.ShadowedRectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.showing ? 20 : 8
        implicitWidth: Math.min(parent.width - 48, row.implicitWidth + 32)
        implicitHeight: row.implicitHeight + 18
        radius: Math.min(height / 2, theme.pillRadius)
        color: theme.popoverBg
        border.width: 1
        border.color: theme.borderStrong
        opacity: root.showing ? 1.0 : 0.0
        visible: opacity > 0.01

        shadow.size: 16
        shadow.yOffset: 4
        shadow.color: theme.isDark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.16)

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.width - 32)
            spacing: 10
            LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true

            QQC2.Label {
                text: root.text
                color: theme.fg
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
                Layout.fillWidth: true
                textFormat: Text.PlainText
            }

            SymbolicIcon {
                name: "window-close-symbolic"
                color: theme.fgMuted
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.showing
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.dismiss()
        }
    }
}
