import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// GNOME AdwShortcutsDialog-style modal dialog parented to Overlay.overlay so
// the dim scrim covers and blocks the entire window including HeaderBar.
// Balanced two-column layout fits completely inside the 720x480 minimum window.
QQC2.Popup {
    id: root

    parent: QQC2.Overlay.overlay
    modal: true
    dim: true
    focus: true
    padding: 0
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    readonly property bool twoColumn: parent ? parent.width >= 660 : true

    width: parent ? Math.min(parent.width - 48, twoColumn ? 720 : 420) : 720
    height: parent ? Math.min(parent.height - 32, dialogCol.implicitHeight) : 400
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    function scrollBy(delta) {
        var maxY = Math.max(0, helpFlick.contentHeight - helpFlick.height)
        helpFlick.contentY = Math.max(0, Math.min(maxY, helpFlick.contentY + delta))
    }

    onOpened: {
        helpFlick.contentY = 0
        closeBtn.forceActiveFocus()
    }

    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, theme.isDark ? 0.56 : 0.34)
    }

    background: Kirigami.ShadowedRectangle {
        radius: theme.cardRadius
        color: theme.popoverBg
        border.width: 1
        border.color: theme.borderStrong
        shadow.size: 28
        shadow.yOffset: 8
        shadow.color: theme.isDark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.18)
    }

    component Keycap: Rectangle {
        property string label: ""
        implicitWidth: Math.max(24, capText.implicitWidth + 12)
        implicitHeight: 22
        radius: Math.min(6, theme.controlRadius > 0 ? theme.controlRadius : 4)
        color: theme.cardBg
        border.width: 1
        border.color: theme.border

        // Subtle lower key lip for tactile affordance.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            radius: Math.min(4, parent.radius)
            color: Qt.rgba(0, 0, 0, theme.isDark ? 0.24 : 0.08)
        }

        QQC2.Label {
            id: capText
            anchors.centerIn: parent
            text: parent.label
            color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.88)
            font.family: "Adwaita Mono"
            font.pixelSize: 11
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }

    component ShortcutGroup: ColumnLayout {
        id: grp
        property string title: ""
        property var items: []
        spacing: 6
        Layout.fillWidth: true

        QQC2.Label {
            text: grp.title
            color: theme.fg
            font.pixelSize: 12
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }

        BoxedCard {
            Layout.fillWidth: true
            implicitHeight: grpCol.implicitHeight

            ColumnLayout {
                id: grpCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: grp.items
                    Item {
                        id: sRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 34

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            QQC2.Label {
                                text: sRow.modelData.label
                                color: theme.fg
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                            }

                            // Differentiates chords ("+") from alternatives ("/").
                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: sRow.modelData.keys
                                    RowLayout {
                                        required property string modelData
                                        required property int index
                                        spacing: 4
                                        QQC2.Label {
                                            visible: index > 0
                                            text: sRow.modelData.sep || "/"
                                            color: theme.fgMuted
                                            font.pixelSize: 11
                                            textFormat: Text.PlainText
                                        }
                                        Keycap { label: modelData }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: sRow.index < grp.items.length - 1
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            height: 1
                            color: theme.border
                        }
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        id: dialogCol
        spacing: 0
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        // GNOME dialog header: centered title, trailing circular close button.
        Item {
            Layout.fillWidth: true
            implicitHeight: 44

            QQC2.Label {
                anchors.centerIn: parent
                text: qsTr("Keyboard Shortcuts")
                color: theme.fg
                font.pixelSize: 14
                font.weight: Font.Bold
                textFormat: Text.PlainText
            }

            QQC2.AbstractButton {
                id: closeBtn
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Close")
                onClicked: root.close()
                Keys.onReturnPressed: root.close()
                Keys.onEnterPressed: root.close()
                Keys.onDownPressed: root.scrollBy(44)
                Keys.onUpPressed: root.scrollBy(-44)
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_PageDown) { root.scrollBy(160); event.accepted = true }
                    else if (event.key === Qt.Key_PageUp) { root.scrollBy(-160); event.accepted = true }
                    else if (event.key === Qt.Key_J) { root.scrollBy(44); event.accepted = true }
                    else if (event.key === Qt.Key_K) { root.scrollBy(-44); event.accepted = true }
                }

                background: Rectangle {
                    radius: Math.min(14, theme.pillRadius > 0 ? theme.pillRadius : 14)
                    color: closeBtn.hovered
                           ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.14)
                           : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.07)
                    border.width: closeBtn.visualFocus ? 2 : 0
                    border.color: theme.accent
                }

                contentItem: Item {
                    SymbolicIcon {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        name: "window-close-symbolic"
                        color: theme.fg
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: theme.border
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: colsLayout.implicitHeight + 28

            Flickable {
                id: helpFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: colsLayout.implicitHeight + 28
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                // Two independent vertical stacks eliminate any dead hole under shorter groups.
                GridLayout {
                    id: colsLayout
                    x: 18
                    y: 14
                    width: parent.width - 36
                    columns: root.twoColumn ? 2 : 1
                    columnSpacing: 18
                    rowSpacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        ShortcutGroup {
                            title: qsTr("Navigation")
                            items: [
                                { label: qsTr("Campaign view"), keys: ["1"] },
                                { label: qsTr("Schedule view"), keys: ["2"] },
                                { label: qsTr("Switch view"), keys: ["Ctrl", "Tab"], sep: "+" },
                                { label: qsTr("Move selection"), keys: ["J", "K"], sep: "/" },
                                { label: qsTr("Move with arrows"), keys: ["↑", "↓"], sep: "/" }
                            ]
                        }

                        ShortcutGroup {
                            title: qsTr("Sync & Export")
                            items: [
                                { label: qsTr("Sync live feeds"), keys: ["R"] },
                                { label: qsTr("Copy campaign checklist"), keys: ["C"] },
                                { label: qsTr("Copy weekend slate"), keys: ["W"] }
                            ]
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        ShortcutGroup {
                            title: qsTr("Selection")
                            items: [
                                { label: qsTr("Toggle or pin selection"), keys: ["Space", "Enter"], sep: "/" },
                                { label: qsTr("Open selected item link"), keys: ["L"] },
                                { label: qsTr("Move focus between controls"), keys: ["Tab"] }
                            ]
                        }

                        ShortcutGroup {
                            title: qsTr("General")
                            items: [
                                { label: qsTr("Open main menu"), keys: ["F10"] },
                                { label: qsTr("Show or hide shortcuts"), keys: ["?"] },
                                { label: qsTr("Close dialog"), keys: ["Esc"] },
                                { label: qsTr("Quit FlightDeck"), keys: ["Q"] }
                            ]
                        }
                    }
                }
            }

            Rectangle {
                visible: !helpFlick.atYEnd && helpFlick.contentHeight > helpFlick.height
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 1
                height: 20
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: theme.popoverBg }
                }
            }
        }
    }
}
