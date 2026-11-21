import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Flat GNOME AdwHeaderBar with a truly centered AdwViewSwitcher, compact
// freshness status on the leading side, and Sync + Primary Menu on the trailing side.
Rectangle {
    id: header

    property int currentView: 0
    property bool stale: false
    property string syncedText: ""
    property string freshnessTooltip: ""
    property bool busy: false
    property bool hasProblem: false
    property bool hasCampaign: false
    property string campaignProgress: ""
    property string liveUrl: ""

    readonly property bool menuOpen: primaryMenu.opened
    readonly property bool compact: width < 780

    signal viewSelected(int index)
    signal syncRequested()
    signal copyChecklistRequested()
    signal copyWeekendRequested()
    signal openLiveRequested()
    signal shortcutsRequested()
    signal quitRequested()

    function openMenu() {
        if (primaryMenu.opened) primaryMenu.close()
        else primaryMenu.open()
    }

    implicitHeight: 54
    color: theme.headerBg

    // Subtle Libadwaita bottom hairline separating header from content.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: theme.border
    }

    Item {
        id: barInner
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        // Leading slot: freshness indicator pill with per-source tooltip and width guard.
        QQC2.AbstractButton {
            id: freshnessPill
            visible: !header.hasProblem
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            leftPadding: 9
            rightPadding: 9
            topPadding: 0
            bottomPadding: 0
            width: Math.min(implicitWidth, Math.max(0, switcher.x - 12))
            implicitWidth: freshnessRow.implicitWidth + leftPadding + rightPadding
            implicitHeight: 30
            focusPolicy: header.stale ? Qt.TabFocus : Qt.NoFocus
            Accessible.role: header.stale ? Accessible.Button : Accessible.StaticText
            Accessible.name: header.stale
                             ? qsTr("Stale feed, synced %1. Activate to sync now.").arg(header.syncedText)
                             : qsTr("Live feed, synced %1").arg(header.syncedText)
            onClicked: if (header.stale) header.syncRequested()

            background: Rectangle {
                radius: Math.min(height / 2, theme.pillRadius)
                color: header.stale
                       ? Qt.rgba(theme.warning.r, theme.warning.g, theme.warning.b, freshnessPill.hovered ? 0.22 : 0.14)
                       : (freshnessPill.hovered ? theme.cardHoverBg : "transparent")
                border.width: freshnessPill.visualFocus ? 2 : (header.stale ? 1 : 0)
                border.color: freshnessPill.visualFocus
                              ? theme.accent
                              : Qt.rgba(theme.warning.r, theme.warning.g, theme.warning.b, 0.34)
            }

            contentItem: RowLayout {
                id: freshnessRow
                spacing: 7

                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: header.stale ? theme.warning : theme.positive
                }

                QQC2.Label {
                    text: header.compact
                          ? header.syncedText
                          : (header.stale
                             ? qsTr("Stale · %1").arg(header.syncedText)
                             : qsTr("Live · %1").arg(header.syncedText))
                    color: header.stale ? theme.warning : theme.fgMuted
                    font.pixelSize: 13
                    font.weight: header.stale ? Font.DemiBold : Font.Normal
                    font.features: { "tnum": 1 }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                }
            }

            QQC2.ToolTip.visible: freshnessPill.hovered && header.freshnessTooltip !== ""
            QQC2.ToolTip.delay: 350
            QQC2.ToolTip.text: header.freshnessTooltip
        }

        // Center slot: GNOME AdwViewSwitcher-style segmented switcher.
        Rectangle {
            id: switcher
            anchors.centerIn: parent
            implicitWidth: switcherRow.implicitWidth + 6
            implicitHeight: 36
            radius: theme.controlRadius > 0 ? theme.controlRadius + 2 : 0
            color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.065 : 0.055)
            border.width: 1
            border.color: theme.border

            RowLayout {
                id: switcherRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [
                        { label: qsTr("Campaign"), icon: "view-list-details-symbolic", tip: qsTr("Starship campaign (1)") },
                        { label: qsTr("Schedule"), icon: "view-calendar-symbolic", tip: qsTr("Launch schedule (2)") }
                    ]

                    QQC2.AbstractButton {
                        id: seg
                        required property int index
                        required property var modelData
                        readonly property bool active: header.currentView === index
                        readonly property bool showBadge: index === 0 && header.campaignProgress !== "" && !header.compact

                        checkable: true
                        checked: active
                        hoverEnabled: true
                        focusPolicy: Qt.TabFocus
                        implicitWidth: segRow.implicitWidth + 24
                        implicitHeight: 30
                        padding: 0
                        Accessible.role: Accessible.PageTab
                        Accessible.name: seg.modelData.label
                        onClicked: header.viewSelected(seg.index)

                        background: Kirigami.ShadowedRectangle {
                            radius: theme.controlRadius
                            color: seg.active
                                   ? theme.cardBg
                                   : (seg.hovered ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.06) : "transparent")
                            border.width: seg.visualFocus ? 2 : (seg.active ? 1 : 0)
                            border.color: seg.visualFocus ? theme.accent : theme.border
                            shadow.size: seg.active ? 6 : 0
                            shadow.yOffset: 1
                            shadow.color: theme.isDark ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0.09)
                        }

                        contentItem: Item {
                            RowLayout {
                                id: segRow
                                anchors.centerIn: parent
                                spacing: 7

                                SymbolicIcon {
                                    name: seg.modelData.icon
                                    color: seg.active ? theme.accentText : theme.fgMuted
                                    Layout.preferredWidth: 15
                                    Layout.preferredHeight: 15
                                }

                                QQC2.Label {
                                    text: seg.modelData.label
                                    color: seg.active ? theme.fg : theme.fgMuted
                                    font.pixelSize: 13
                                    font.weight: seg.active ? Font.DemiBold : Font.Medium
                                    textFormat: Text.PlainText
                                }

                                Rectangle {
                                    visible: seg.showBadge
                                    implicitWidth: badgeLabel.implicitWidth + 10
                                    implicitHeight: 18
                                    radius: Math.min(height / 2, theme.pillRadius)
                                    color: seg.active
                                           ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.16)
                                           : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.08)

                                    QQC2.Label {
                                        id: badgeLabel
                                        anchors.centerIn: parent
                                        text: header.campaignProgress
                                        color: seg.active ? theme.accentText : theme.fgMuted
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        font.features: { "tnum": 1 }
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }

                        QQC2.ToolTip.visible: seg.hovered
                        QQC2.ToolTip.delay: 500
                        QQC2.ToolTip.text: seg.modelData.tip
                    }
                }
            }
        }

        // Trailing slot: Sync button and GNOME Primary Menu.
        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            QQC2.AbstractButton {
                id: syncBtn
                implicitWidth: 34
                implicitHeight: 34
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Sync Now")
                onClicked: header.syncRequested()

                background: Rectangle {
                    radius: theme.controlRadius
                    color: syncBtn.down
                           ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.12)
                           : (syncBtn.hovered ? theme.cardHoverBg : "transparent")
                    border.width: syncBtn.visualFocus ? 2 : 0
                    border.color: theme.accent
                }

                contentItem: Item {
                    SymbolicIcon {
                        id: syncIcon
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: "view-refresh-symbolic"
                        color: header.busy ? theme.accentText : theme.fg

                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: header.busy
                            onRunningChanged: if (!running) syncIcon.rotation = 0
                        }
                    }
                }

                QQC2.ToolTip.visible: syncBtn.hovered
                QQC2.ToolTip.delay: 400
                QQC2.ToolTip.text: header.busy ? qsTr("Syncing feeds…") : qsTr("Sync now (R)")
            }

            QQC2.AbstractButton {
                id: menuBtn
                implicitWidth: 34
                implicitHeight: 34
                hoverEnabled: true
                focusPolicy: Qt.TabFocus
                Accessible.role: Accessible.ButtonMenu
                Accessible.name: qsTr("Main Menu")
                onClicked: header.openMenu()

                background: Rectangle {
                    radius: theme.controlRadius
                    color: primaryMenu.opened || menuBtn.down
                           ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.12)
                           : (menuBtn.hovered ? theme.cardHoverBg : "transparent")
                    border.width: menuBtn.visualFocus ? 2 : 0
                    border.color: theme.accent
                }

                contentItem: Item {
                    SymbolicIcon {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: "open-menu-symbolic"
                        color: theme.fg
                    }
                }

                QQC2.ToolTip.visible: menuBtn.hovered && !primaryMenu.opened
                QQC2.ToolTip.delay: 400
                QQC2.ToolTip.text: qsTr("Main menu (F10)")

                QQC2.Menu {
                    id: primaryMenu
                    y: menuBtn.height + 6
                    x: Qt.application.layoutDirection === Qt.RightToLeft ? 0 : menuBtn.width - width
                    width: 242
                    padding: 6

                    background: Kirigami.ShadowedRectangle {
                        radius: theme.controlRadius > 0 ? theme.controlRadius + 2 : 0
                        color: theme.popoverBg
                        border.width: 1
                        border.color: theme.borderStrong
                        shadow.size: 16
                        shadow.yOffset: 4
                        shadow.color: theme.isDark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.14)
                    }

                    component PrimaryMenuItem: QQC2.MenuItem {
                        id: mi
                        property string shortcutHint: ""
                        property string iconName: ""
                        implicitHeight: 34
                        padding: 0
                        background: Rectangle {
                            radius: theme.controlRadius
                            color: mi.highlighted ? theme.cardHoverBg : "transparent"
                        }
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
                            LayoutMirroring.childrenInherit: true

                            SymbolicIcon {
                                name: mi.iconName
                                color: mi.enabled ? theme.fgMuted : Qt.rgba(theme.fgMuted.r, theme.fgMuted.g, theme.fgMuted.b, 0.4)
                                Layout.preferredWidth: 15
                                Layout.preferredHeight: 15
                            }
                            QQC2.Label {
                                text: mi.text
                                color: mi.enabled ? theme.fg : theme.fgMuted
                                opacity: mi.enabled ? 1.0 : 0.5
                                font.pixelSize: 13
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                visible: mi.shortcutHint !== ""
                                text: mi.shortcutHint
                                color: theme.fgMuted
                                font.family: "Adwaita Mono"
                                font.pixelSize: 11
                                textFormat: Text.PlainText
                            }
                        }
                    }

                    component MenuRule: QQC2.MenuSeparator {
                        padding: 4
                        contentItem: Rectangle {
                            implicitHeight: 1
                            color: theme.border
                        }
                    }

                    PrimaryMenuItem {
                        text: qsTr("Copy Checklist")
                        iconName: "edit-copy-symbolic"
                        shortcutHint: "C"
                        enabled: header.hasCampaign
                        onTriggered: header.copyChecklistRequested()
                    }
                    PrimaryMenuItem {
                        text: qsTr("Copy Weekend Slate")
                        iconName: "view-calendar-symbolic"
                        shortcutHint: "W"
                        enabled: !header.hasProblem
                        onTriggered: header.copyWeekendRequested()
                    }
                    MenuRule { visible: header.liveUrl !== ""; height: visible ? implicitHeight : 0 }
                    PrimaryMenuItem {
                        visible: header.liveUrl !== ""
                        enabled: visible
                        height: visible ? implicitHeight : 0
                        text: qsTr("Open Starbase Live")
                        iconName: "media-playback-start-symbolic"
                        onTriggered: header.openLiveRequested()
                    }
                    MenuRule {}
                    PrimaryMenuItem {
                        text: qsTr("Keyboard Shortcuts")
                        iconName: "preferences-desktop-keyboard-symbolic"
                        shortcutHint: "?"
                        onTriggered: header.shortcutsRequested()
                    }
                    PrimaryMenuItem {
                        text: qsTr("Quit")
                        iconName: "window-close-symbolic"
                        shortcutHint: "Q"
                        onTriggered: header.quitRequested()
                    }
                }
            }
        }
    }
}
