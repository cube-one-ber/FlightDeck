import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// Contrast-safe capsule badge used for launch status, range alerts, and tags.
Rectangle {
    id: pill

    property string label: ""
    property color tint: theme.fgMuted
    property bool showDot: true
    property string iconName: ""
    property bool compact: false

    visible: label !== "" || iconName !== ""
    implicitWidth: row.implicitWidth + (compact ? 14 : 18)
    implicitHeight: row.implicitHeight + (compact ? 6 : 8)
    // Keep status badges gently softened even on zero-radius themes so pills
    // stay visually distinct from rectangular cards and action buttons.
    radius: theme.radius === 0 ? 4 : Math.min(height / 2, theme.pillRadius)
    color: Qt.rgba(tint.r, tint.g, tint.b, theme.isDark ? 0.16 : 0.13)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, theme.isDark ? 0.30 : 0.24)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            visible: pill.showDot && pill.iconName === ""
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: pill.tint
        }

        SymbolicIcon {
            visible: pill.iconName !== ""
            name: pill.iconName
            color: pill.tint
            Layout.preferredWidth: pill.compact ? 12 : 13
            Layout.preferredHeight: pill.compact ? 12 : 13
        }

        QQC2.Label {
            visible: pill.label !== ""
            text: pill.label
            color: pill.tint
            font.pixelSize: pill.compact ? 11 : 12
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }
}
