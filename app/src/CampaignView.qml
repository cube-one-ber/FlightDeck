import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The live Starship campaign: mission readiness hero + boxed milestone list on
// the primary side, and Starbase telemetry cards in a scrollable inspector.
Item {
    id: root

    property var campaign: null
    readonly property var milestones: campaign ? campaign.milestones : []
    readonly property bool narrow: width < 880
    property int narrowTab: 0 // 0 = Milestones, 1 = Starbase Telemetry
    property int selectedId: -1
    property real savedContentY: 0
    property bool restoringModel: false
    // Hoisted onto root so the 350 ms double-click guard survives fast daemon reloads.
    property int lastToggleId: -1
    property double lastToggleMs: 0

    readonly property int nextMilestoneIndex: {
        for (var i = 0; i < milestones.length; ++i) {
            if (!milestones[i].done) return i
        }
        return -1
    }
    readonly property var nextMilestone: nextMilestoneIndex >= 0 ? milestones[nextMilestoneIndex] : null

    // Checks whether an active fleet vehicle is referenced in the current flight's milestones.
    function isFlightVehicle(name) {
        if (!name || !milestones.length) return false
        for (var i = 0; i < milestones.length; ++i) {
            if (milestones[i].title && milestones[i].title.indexOf(name) >= 0)
                return true
        }
        return false
    }

    // Active flight vehicles lead the fleet card so current hardware anchors the top-left.
    readonly property var sortedVehicles: {
        var list = root.campaign && root.campaign.vehicles ? root.campaign.vehicles : []
        var active = []
        var rest = []
        for (var i = 0; i < list.length; ++i) {
            if (isFlightVehicle(list[i].name)) active.push(list[i])
            else rest.push(list[i])
        }
        return active.concat(rest)
    }

    function selectIndex(idx) {
        if (milestones.length === 0) return
        root.forceActiveFocus()
        var clamped = Math.max(0, Math.min(milestones.length - 1, idx))
        list.currentIndex = clamped
        selectedId = milestones[clamped].id
        list.positionViewAtIndex(clamped, ListView.Contain)
        Qt.callLater(function() { if (!root.restoringModel) root.savedContentY = list.contentY })
    }

    onMilestonesChanged: {
        restoringModel = true
        var id = root.selectedId
        var y = root.savedContentY
        Qt.callLater(function() {
            var i = id >= 0 ? root.milestones.findIndex(function(m) { return m.id === id }) : -1
            // Default initial selection to the active Next milestone rather than a completed one.
            var fallbackIdx = root.nextMilestoneIndex >= 0 ? root.nextMilestoneIndex : 0
            list.currentIndex = i >= 0 ? i : fallbackIdx
            if (root.milestones[list.currentIndex] && id >= 0)
                root.selectedId = root.milestones[list.currentIndex].id
            var maxY = Math.max(0, list.contentHeight - list.height)
            list.contentY = Math.max(0, Math.min(y, maxY))
            root.savedContentY = list.contentY
            root.restoringModel = false
        })
    }

    function move(delta) {
        if (narrow && narrowTab !== 0) narrowTab = 0
        selectIndex(list.currentIndex + delta)
    }

    // Space or clicking the check circle flips a milestone; a second press hands it back to live.
    function activate() {
        if (narrow && narrowTab !== 0) return
        var m = milestones[list.currentIndex]
        if (!m) return
        if (m.forced === null || m.forced === undefined) backend.setMilestone(m.id, m.live ? "off" : "on")
        else backend.setMilestone(m.id, "auto")
    }

    // Only allow http(s) URLs to reach the desktop opener.
    function isSafeWebUrl(u) {
        if (typeof u !== "string") return false
        return /^https?:\/\/[^/\s?#]+(?:[/?#][^\s]*)?$/i.test(u.trim())
    }

    function openWebUrl(u) {
        if (isSafeWebUrl(u)) Qt.openUrlExternally(u.trim())
    }

    function openLink() {
        if (narrow && narrowTab !== 0) return
        var m = milestones[list.currentIndex]
        if (m && isSafeWebUrl(m.url)) openWebUrl(m.url)
        else if (campaign && isSafeWebUrl(campaign.live_url)) openWebUrl(campaign.live_url)
    }

    // Closures and TFRs have no fixed shape in the feed; show the first readable fields.
    function describe(item) {
        var keys = ["title", "name", "description", "status", "date", "start", "end"]
        var parts = keys.filter(function(k) { return item && typeof item[k] === "string" && item[k] !== "" })
                        .slice(0, 3).map(function(k) { return item[k] })
        return parts.length ? parts.join(" · ") : JSON.stringify(item).slice(0, 80)
    }

    function capitalize(s) {
        if (!s) return ""
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function shortLocation(loc) {
        if (!loc) return ""
        return loc.replace(/,\s*Texas,\s*USA$/i, "").replace(/,\s*USA$/i, "")
    }

    function formatShortDate(iso) {
        if (!iso) return ""
        var lang = translator.language
        void lang
        return new Date(iso).toLocaleDateString(Qt.locale(), "d MMM")
    }

    // Maps weather condition summaries to clean Papirus symbolic weather icons.
    function weatherIcon(summary) {
        var s = (summary || "").toLowerCase()
        if (s.indexOf("thunder") >= 0 || s.indexOf("storm") >= 0 || s.indexOf("squall") >= 0)
            return "weather-storm-symbolic"
        if (s.indexOf("snow") >= 0 || s.indexOf("sleet") >= 0 || s.indexOf("hail") >= 0)
            return "weather-snow-symbolic"
        if (s.indexOf("drizzle") >= 0 || s.indexOf("light rain") >= 0)
            return "weather-showers-scattered-symbolic"
        if (s.indexOf("rain") >= 0 || s.indexOf("shower") >= 0)
            return "weather-showers-symbolic"
        if (s.indexOf("fog") >= 0 || s.indexOf("mist") >= 0 || s.indexOf("haze") >= 0 || s.indexOf("smoke") >= 0 || s.indexOf("dust") >= 0)
            return "weather-fog-symbolic"
        if (s.indexOf("cloud") >= 0 || s.indexOf("overcast") >= 0)
            return "weather-overcast-symbolic"
        if (s.indexOf("wind") >= 0 || s.indexOf("breez") >= 0 || s.indexOf("gale") >= 0)
            return "weather-windy-symbolic"
        if (s.indexOf("clear") >= 0 || s.indexOf("sun") >= 0)
            return "weather-clear-symbolic"
        return "weather-overcast-symbolic"
    }

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        visible: !root.campaign
        icon.name: "view-list-details-symbolic"
        text: qsTr("No Active Starship Campaign")
        explanation: qsTr("FlightDeck will show milestones, range notices, and fleet status as soon as the feed publishes a campaign.")
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 16
        spacing: 22
        visible: !!root.campaign

        // Primary pane: mission readiness hero card + boxed milestone list.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Mission Readiness Hero Card — focal counterpart to Schedule's countdown hero.
            BoxedCard {
                Layout.fillWidth: true
                accented: true
                padding: 0
                implicitHeight: heroCol.implicitHeight + 30

                // Subtle top-edge accent wash for aerospace instrument presence.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Math.max(0, theme.cardRadius - 1)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, theme.isDark ? 0.07 : 0.045) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                ColumnLayout {
                    id: heroCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 10

                    // Title + readiness counter + Starbase Live button.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            QQC2.Label {
                                text: root.campaign ? root.campaign.title : ""
                                color: theme.fg
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            QQC2.AbstractButton {
                                id: nextJumpBtn
                                Layout.fillWidth: true
                                implicitHeight: nextJumpRow.implicitHeight
                                padding: 0
                                enabled: root.nextMilestoneIndex >= 0
                                hoverEnabled: true
                                focusPolicy: enabled ? Qt.TabFocus : Qt.NoFocus
                                Accessible.role: enabled ? Accessible.Button : Accessible.StaticText
                                Accessible.name: root.nextMilestone
                                                 ? qsTr("Jump to next milestone: %1").arg(root.nextMilestone.title)
                                                 : qsTr("All milestones complete")
                                onClicked: {
                                    if (root.narrow) root.narrowTab = 0
                                    root.selectIndex(root.nextMilestoneIndex)
                                }

                                background: Rectangle {
                                    visible: nextJumpBtn.visualFocus
                                    radius: theme.controlRadius
                                    color: "transparent"
                                    border.width: 2
                                    border.color: theme.accent
                                }

                                contentItem: RowLayout {
                                    id: nextJumpRow
                                    spacing: 7

                                    Rectangle {
                                        Layout.preferredWidth: 7
                                        Layout.preferredHeight: 7
                                        radius: 3.5
                                        color: root.nextMilestone ? theme.accentText : theme.positive
                                    }

                                    QQC2.Label {
                                        text: root.nextMilestone
                                              ? qsTr("Next gate: %1").arg(root.nextMilestone.title)
                                              : qsTr("All milestones complete")
                                        color: root.nextMilestone ? theme.fgMuted : theme.positive
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        font.underline: nextJumpBtn.enabled && nextJumpBtn.hovered
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                    }
                                }

                                QQC2.ToolTip.visible: nextJumpBtn.enabled && nextJumpBtn.hovered
                                QQC2.ToolTip.delay: 450
                                QQC2.ToolTip.text: qsTr("Jump to next milestone")
                            }
                        }

                        // Prominent tabular readiness metric.
                        ColumnLayout {
                            readonly property int done: root.campaign ? root.campaign.done : 0
                            readonly property int total: root.campaign ? root.campaign.total : 0
                            readonly property int pct: total > 0 ? Math.round((done / total) * 100) : 0
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: 2
                                QQC2.Label {
                                    text: parent.parent.done.toString()
                                    color: theme.accentText
                                    font.pixelSize: 22
                                    font.weight: Font.Bold
                                    font.features: { "tnum": 1 }
                                    textFormat: Text.PlainText
                                }
                                QQC2.Label {
                                    text: "/" + parent.parent.total
                                    color: theme.fgMuted
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                    textFormat: Text.PlainText
                                }
                            }
                            QQC2.Label {
                                Layout.alignment: Qt.AlignRight
                                text: qsTr("%1% ready").arg(parent.pct)
                                color: theme.fgMuted
                                font.pixelSize: 12
                                font.features: { "tnum": 1 }
                                textFormat: Text.PlainText
                            }
                        }

                        QQC2.AbstractButton {
                            id: liveBtn
                            visible: !!(root.campaign && root.isSafeWebUrl(root.campaign.live_url))
                            implicitWidth: liveBtnRow.implicitWidth + 20
                            implicitHeight: 34
                            hoverEnabled: true
                            focusPolicy: Qt.TabFocus
                            Accessible.role: Accessible.Button
                            Accessible.name: qsTr("Open Starbase Live")
                            onClicked: root.openWebUrl(root.campaign ? root.campaign.live_url : "")

                            background: Rectangle {
                                radius: theme.controlRadius
                                color: liveBtn.hovered ? theme.cardHoverBg : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.05 : 0.03)
                                border.width: liveBtn.visualFocus ? 2 : 1
                                border.color: liveBtn.visualFocus ? theme.accent : theme.borderStrong
                            }

                            contentItem: Item {
                                RowLayout {
                                    id: liveBtnRow
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SymbolicIcon {
                                        name: "media-playback-start-symbolic"
                                        color: theme.accentText
                                        Layout.preferredWidth: 14
                                        Layout.preferredHeight: 14
                                    }
                                    QQC2.Label {
                                        text: qsTr("Starbase Live")
                                        color: theme.fg
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        textFormat: Text.PlainText
                                    }
                                    SymbolicIcon {
                                        name: "external-link-symbolic"
                                        color: theme.fgMuted
                                        Layout.preferredWidth: 12
                                        Layout.preferredHeight: 12
                                    }
                                }
                            }

                            QQC2.ToolTip.visible: liveBtn.hovered
                            QQC2.ToolTip.delay: 400
                            QQC2.ToolTip.text: qsTr("Open Starbase Live stream")
                        }
                    }

                    // Interactive segmented readiness track (hover for milestone, click to jump).
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 10

                        Row {
                            id: segTrack
                            anchors.fill: parent
                            spacing: 3
                            visible: root.milestones.length > 0 && root.milestones.length <= 30
                            readonly property int count: Math.max(1, root.milestones.length)

                            Repeater {
                                model: root.milestones.length <= 30 ? root.milestones : []
                                Item {
                                    id: segWrap
                                    required property var modelData
                                    required property int index
                                    readonly property bool isNext: index === root.nextMilestoneIndex
                                    width: Math.max(4, (segTrack.width - segTrack.spacing * (segTrack.count - 1)) / segTrack.count)
                                    height: segTrack.height

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: segMouse.containsMouse ? 10 : 7
                                        radius: Math.min(3, theme.controlRadius > 0 ? theme.controlRadius : 2)
                                        color: segWrap.modelData.done
                                               ? (segWrap.modelData.diverged ? theme.warning : theme.accent)
                                               : (segWrap.isNext
                                                  ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, segMouse.containsMouse ? 0.65 : 0.45)
                                                  : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, segMouse.containsMouse ? 0.28 : 0.13))
                                        Behavior on height { NumberAnimation { duration: 100 } }
                                    }

                                    MouseArea {
                                        id: segMouse
                                        anchors.fill: parent
                                        anchors.topMargin: -4
                                        anchors.bottomMargin: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.narrow) root.narrowTab = 0
                                            root.selectIndex(segWrap.index)
                                        }
                                    }

                                    QQC2.ToolTip.visible: segMouse.containsMouse
                                    QQC2.ToolTip.delay: 200
                                    QQC2.ToolTip.text: (segWrap.modelData.done ? "✓ " : (segWrap.isNext ? "→ " : "")) + segWrap.modelData.title
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 7
                            visible: root.milestones.length > 30
                            radius: Math.min(3, theme.controlRadius > 0 ? theme.controlRadius : 2)
                            color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.13)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: root.campaign && root.campaign.total > 0
                                       ? parent.width * (root.campaign.done / root.campaign.total) : 0
                                radius: parent.radius
                                color: theme.accent
                            }
                        }
                    }
                }
            }

            // Narrow-window lightweight underline sub-tabs (distinct from primary header switcher).
            Item {
                visible: root.narrow
                Layout.fillWidth: true
                implicitHeight: 32

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Repeater {
                        model: [qsTr("Milestones"), qsTr("Starbase Telemetry")]
                        QQC2.AbstractButton {
                            id: subSeg
                            required property int index
                            required property string modelData
                            readonly property bool active: root.narrowTab === index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            checkable: true
                            checked: active
                            hoverEnabled: true
                            focusPolicy: Qt.TabFocus
                            Accessible.role: Accessible.PageTab
                            Accessible.name: subSeg.modelData
                            onClicked: root.narrowTab = subSeg.index

                            background: Item {
                                Rectangle {
                                    anchors.fill: parent
                                    radius: theme.controlRadius
                                    color: subSeg.hovered && !subSeg.active ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.05) : "transparent"
                                    border.width: subSeg.visualFocus ? 2 : 0
                                    border.color: theme.accent
                                }
                                Rectangle {
                                    visible: subSeg.active
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    height: 2
                                    radius: 1
                                    color: theme.accent
                                }
                            }

                            contentItem: QQC2.Label {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: subSeg.modelData
                                color: subSeg.active ? theme.fg : theme.fgMuted
                                font.pixelSize: 13
                                font.weight: subSeg.active ? Font.DemiBold : Font.Medium
                                textFormat: Text.PlainText
                            }
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

            // Milestone boxed list with inset rounded row highlights and smooth bottom fade.
            BoxedCard {
                visible: !root.narrow || root.narrowTab === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 4

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: root.milestones
                    currentIndex: 0
                    onContentYChanged: if (!root.restoringModel && (contentY > 0 || moving || dragging || flicking)) root.savedContentY = contentY
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                    highlightMoveDuration: 0

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: ListView.isCurrentItem
                        readonly property bool overridden: modelData.forced !== null && modelData.forced !== undefined
                        readonly property bool isNext: index === root.nextMilestoneIndex
                        readonly property bool isLast: index === root.milestones.length - 1

                        width: ListView.view.width
                        height: 46

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: theme.controlRadius
                            color: row.selected
                                   ? theme.cardSelectedBg
                                   : (rowMouse.containsMouse ? theme.cardHoverBg : "transparent")
                        }

                        // Subtle leading accent bar on the keyboard-selected row.
                        Rectangle {
                            visible: row.selected
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            anchors.leftMargin: 3
                            width: 2.5
                            radius: theme.controlRadius > 0 ? 1.25 : 0
                            color: Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.80)
                        }

                        // Single click selects; double click toggles override.
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.selectIndex(row.index)
                            onDoubleClicked: {
                                root.selectIndex(row.index)
                                root.activate()
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 12

                            // Direct circular toggle button; debounces accidental double-clicks.
                            QQC2.AbstractButton {
                                id: checkBtn
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.role: Accessible.CheckBox
                                Accessible.checked: row.modelData.done
                                Accessible.name: row.modelData.title
                                onClicked: {
                                    var t = Date.now()
                                    if (root.lastToggleId === row.modelData.id && t - root.lastToggleMs < 350) return
                                    root.lastToggleId = row.modelData.id
                                    root.lastToggleMs = t
                                    root.selectIndex(row.index)
                                    root.activate()
                                }

                                background: Rectangle {
                                    visible: checkBtn.visualFocus
                                    radius: Math.min(height / 2, theme.pillRadius > 0 ? theme.pillRadius : 16)
                                    color: "transparent"
                                    border.width: 2
                                    border.color: theme.accent
                                }

                                contentItem: Item {
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: row.modelData.done
                                               ? (row.modelData.diverged ? theme.warning : theme.accent)
                                               : (row.isNext
                                                  ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.16)
                                                  : (checkBtn.hovered ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.08) : "transparent"))
                                        border.width: row.modelData.done ? 0 : (row.isNext ? 2 : 1.5)
                                        border.color: row.isNext ? theme.accentText : theme.borderStrong

                                        SymbolicIcon {
                                            visible: row.modelData.done
                                            anchors.centerIn: parent
                                            width: 13
                                            height: 13
                                            name: "object-select-symbolic"
                                            color: row.modelData.diverged
                                                   ? (theme.isDark ? "#121214" : "#ffffff")
                                                   : theme.accentForeground
                                        }
                                    }
                                }

                                QQC2.ToolTip.visible: checkBtn.hovered
                                QQC2.ToolTip.delay: 450
                                QQC2.ToolTip.text: row.overridden
                                                    ? qsTr("Return to live feed (Space)")
                                                    : (row.modelData.live ? qsTr("Override as pending (Space)") : qsTr("Override as done (Space)"))
                            }

                            QQC2.Label {
                                text: row.modelData.title
                                color: row.selected || !row.modelData.done ? theme.fg : theme.fgMuted
                                font.pixelSize: 14
                                font.weight: row.isNext ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                            }

                            StatusPill {
                                visible: row.isNext && !row.overridden
                                label: qsTr("Next")
                                tint: theme.accentText
                                showDot: false
                                compact: true
                            }

                            // Override pill with one-click accessible 24x24 reset button back to live feed.
                            Rectangle {
                                id: ovBadge
                                visible: row.overridden
                                implicitWidth: ovRow.implicitWidth + 14
                                implicitHeight: 26
                                radius: theme.radius === 0 ? 4 : Math.min(height / 2, theme.pillRadius)
                                readonly property color ovTint: row.modelData.diverged ? theme.warning : theme.fgMuted
                                color: Qt.rgba(ovTint.r, ovTint.g, ovTint.b, theme.isDark ? 0.16 : 0.13)
                                border.width: 1
                                border.color: Qt.rgba(ovTint.r, ovTint.g, ovTint.b, 0.32)

                                RowLayout {
                                    id: ovRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    spacing: 4

                                    QQC2.Label {
                                        text: row.modelData.diverged
                                              ? (row.modelData.live ? qsTr("Override · Live done") : qsTr("Override · Live pending"))
                                              : qsTr("Override · Matches live")
                                        color: ovBadge.ovTint
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        textFormat: Text.PlainText
                                    }

                                    QQC2.AbstractButton {
                                        id: resetBtn
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        hoverEnabled: true
                                        focusPolicy: Qt.TabFocus
                                        Accessible.role: Accessible.Button
                                        Accessible.name: qsTr("Follow live feed")
                                        onClicked: backend.setMilestone(row.modelData.id, "auto")

                                        background: Rectangle {
                                            radius: Math.min(height / 2, theme.pillRadius > 0 ? theme.pillRadius : 12)
                                            color: resetBtn.hovered
                                                   ? Qt.rgba(ovBadge.ovTint.r, ovBadge.ovTint.g, ovBadge.ovTint.b, 0.20)
                                                   : "transparent"
                                            border.width: resetBtn.visualFocus ? 2 : 0
                                            border.color: theme.accent
                                        }

                                        contentItem: Item {
                                            SymbolicIcon {
                                                anchors.centerIn: parent
                                                width: 12
                                                height: 12
                                                name: "window-close-symbolic"
                                                color: ovBadge.ovTint
                                                opacity: resetBtn.hovered ? 1.0 : 0.78
                                            }
                                        }

                                        QQC2.ToolTip.visible: resetBtn.hovered
                                        QQC2.ToolTip.delay: 300
                                        QQC2.ToolTip.text: qsTr("Follow live feed")
                                    }
                                }
                            }

                            // External source link button when the milestone has a safe web URL.
                            QQC2.AbstractButton {
                                id: linkBtn
                                visible: root.isSafeWebUrl(row.modelData.url)
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                hoverEnabled: true
                                focusPolicy: Qt.TabFocus
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Open source link")
                                onClicked: {
                                    root.selectIndex(row.index)
                                    root.openWebUrl(row.modelData.url)
                                }

                                background: Rectangle {
                                    radius: theme.controlRadius
                                    color: linkBtn.hovered ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.10) : "transparent"
                                    border.width: linkBtn.visualFocus ? 2 : 0
                                    border.color: theme.accent
                                }

                                contentItem: Item {
                                    SymbolicIcon {
                                        anchors.centerIn: parent
                                        width: 14
                                        height: 14
                                        name: "external-link-symbolic"
                                        color: linkBtn.hovered ? theme.fg : theme.fgMuted
                                    }
                                }

                                QQC2.ToolTip.visible: linkBtn.hovered
                                QQC2.ToolTip.delay: 400
                                QQC2.ToolTip.text: qsTr("Open source link (L)")
                            }
                        }

                        // Inset hairline divider aligned with milestone titles; suppressed
                        // both on and immediately above the selected row for clean framing.
                        Rectangle {
                            visible: !row.isLast && !row.selected && (row.index + 1 !== list.currentIndex)
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 54
                            anchors.rightMargin: 8
                            height: 1
                            color: theme.border
                        }
                    }
                }

                // Smooth 3-stop bottom fade pinned to BoxedCard viewport so clipped rows dissolve cleanly.
                Rectangle {
                    visible: !list.atYEnd && list.contentHeight > list.height
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 36
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.62; color: Qt.rgba(theme.cardBg.r, theme.cardBg.g, theme.cardBg.b, 0.82) }
                        GradientStop { position: 1.0; color: theme.cardBg }
                    }
                }
            }

            // Narrow-window inspector slot.
            Loader {
                visible: root.narrow && root.narrowTab === 1
                active: root.narrow
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: inspectorComponent
            }
        }

        // Wide-window Starbase telemetry inspector pane.
        Loader {
            visible: !root.narrow
            active: !root.narrow
            Layout.preferredWidth: Math.min(364, Math.max(316, Math.floor(root.width * 0.32)))
            Layout.fillHeight: true
            sourceComponent: inspectorComponent
        }
    }

    Component {
        id: inspectorComponent

        Item {
            Flickable {
                id: inspectorFlick
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: inspectorCol.implicitHeight + 16
                boundsBehavior: Flickable.StopAtBounds
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                ColumnLayout {
                    id: inspectorCol
                    anchors.left: parent.left
                    width: inspectorFlick.width - 6
                    spacing: 13

                    component SectionTitle: QQC2.Label {
                        color: theme.fgMuted
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                    }

                    // 1. Starbase Conditions: weather, road closures, and FAA TFRs in one card.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SectionTitle { text: qsTr("Starbase Conditions") }

                        BoxedCard {
                            Layout.fillWidth: true
                            implicitHeight: condCol.implicitHeight

                            ColumnLayout {
                                id: condCol
                                width: parent.width
                                spacing: 0

                                // Weather row.
                                Item {
                                    id: weatherItem
                                    readonly property var w: root.campaign ? root.campaign.weather : null
                                    visible: !!w
                                    Layout.fillWidth: true
                                    implicitHeight: visible ? weatherRow.implicitHeight + 16 : 0

                                    RowLayout {
                                        id: weatherRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 12

                                        Rectangle {
                                            Layout.preferredWidth: 36
                                            Layout.preferredHeight: 36
                                            radius: theme.controlRadius
                                            color: Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.12)

                                            SymbolicIcon {
                                                anchors.centerIn: parent
                                                width: 19
                                                height: 19
                                                name: root.weatherIcon(weatherItem.w ? weatherItem.w.summary : "")
                                                color: theme.accentText
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8
                                                QQC2.Label {
                                                    text: weatherItem.w && weatherItem.w.temp_c !== null && weatherItem.w.temp_c !== undefined
                                                          ? qsTr("%1 °C").arg(weatherItem.w.temp_c.toLocaleString(Qt.locale(), "f", 0))
                                                          : ""
                                                    color: theme.fg
                                                    font.pixelSize: 17
                                                    font.weight: Font.Bold
                                                    font.features: { "tnum": 1 }
                                                    textFormat: Text.PlainText
                                                }
                                                QQC2.Label {
                                                    text: weatherItem.w ? root.capitalize(weatherItem.w.summary) : ""
                                                    color: theme.fg
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    textFormat: Text.PlainText
                                                }
                                            }

                                            QQC2.Label {
                                                text: {
                                                    var lang = translator.language
                                                    void lang
                                                    var w = weatherItem.w
                                                    if (!w) return ""
                                                    return [
                                                        w.location,
                                                        w.wind_kmh !== null && w.wind_kmh !== undefined
                                                            ? qsTr("Wind %1 km/h").arg(w.wind_kmh.toLocaleString(Qt.locale(), "f", 0))
                                                            : "",
                                                        w.gusts_kmh !== null && w.gusts_kmh !== undefined
                                                            ? qsTr("Gusts %1 km/h").arg(w.gusts_kmh.toLocaleString(Qt.locale(), "f", 0))
                                                            : ""
                                                    ].filter(function(s) { return s }).join(" · ")
                                                }
                                                color: theme.fgMuted
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 14
                                        height: 1
                                        color: theme.border
                                    }
                                }

                                // Road Closures row.
                                Item {
                                    id: closureItem
                                    readonly property var items: root.campaign ? root.campaign.closures : []
                                    Layout.fillWidth: true
                                    implicitHeight: closureCol.implicitHeight + 12

                                    ColumnLayout {
                                        id: closureCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            QQC2.Label {
                                                text: qsTr("Road Closures")
                                                color: theme.fg
                                                font.pixelSize: 13
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                            }
                                            StatusPill {
                                                label: closureItem.items.length
                                                       ? qsTr("%n active", "", closureItem.items.length)
                                                       : qsTr("None posted")
                                                tint: closureItem.items.length ? theme.warning : theme.positive
                                                compact: true
                                            }
                                        }

                                        QQC2.Label {
                                            visible: closureItem.items.length > 0
                                            text: closureItem.items.map(root.describe).join("\n")
                                            color: theme.fgMuted
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 14
                                        height: 1
                                        color: theme.border
                                    }
                                }

                                // FAA TFRs row.
                                Item {
                                    id: tfrItem
                                    readonly property var items: root.campaign ? root.campaign.tfrs : []
                                    Layout.fillWidth: true
                                    implicitHeight: tfrCol.implicitHeight + 12

                                    ColumnLayout {
                                        id: tfrCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            QQC2.Label {
                                                text: qsTr("FAA TFRs")
                                                color: theme.fg
                                                font.pixelSize: 13
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                            }
                                            StatusPill {
                                                label: tfrItem.items.length
                                                       ? qsTr("%n active", "", tfrItem.items.length)
                                                       : qsTr("None posted")
                                                tint: tfrItem.items.length ? theme.warning : theme.positive
                                                compact: true
                                            }
                                        }

                                        QQC2.Label {
                                            visible: tfrItem.items.length > 0
                                            text: tfrItem.items.map(root.describe).join("\n")
                                            color: theme.fgMuted
                                            font.pixelSize: 12
                                            wrapMode: Text.Wrap
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2. Active Fleet chips — highlights vehicles assigned to the active flight's milestones.
                    ColumnLayout {
                        visible: !!(root.campaign && root.campaign.vehicles && root.campaign.vehicles.length)
                        Layout.fillWidth: true
                        spacing: 6

                        SectionTitle { text: qsTr("Active Fleet") }

                        BoxedCard {
                            Layout.fillWidth: true
                            padding: 10
                            implicitHeight: fleetFlow.implicitHeight + 20

                            Flow {
                                id: fleetFlow
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: root.sortedVehicles
                                    Rectangle {
                                        id: vChip
                                        required property var modelData
                                        readonly property bool isSta: modelData.kind && modelData.kind.indexOf("Structural") >= 0
                                        readonly property bool onFlight: root.isFlightVehicle(modelData.name)
                                        implicitWidth: vRow.implicitWidth + 16
                                        implicitHeight: 27
                                        radius: theme.radius === 0 ? 4 : Math.min(height / 2, theme.pillRadius)
                                        color: onFlight
                                               ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, theme.isDark ? 0.14 : 0.11)
                                               : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.065 : 0.05)
                                        border.width: 1
                                        border.color: onFlight
                                                      ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.36)
                                                      : theme.border

                                        RowLayout {
                                            id: vRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Rectangle {
                                                visible: vChip.onFlight
                                                Layout.preferredWidth: 5
                                                Layout.preferredHeight: 5
                                                radius: 2.5
                                                color: theme.accentText
                                            }
                                            QQC2.Label {
                                                text: vChip.modelData.name
                                                color: vChip.onFlight ? theme.fg : theme.fgMuted
                                                font.pixelSize: 13
                                                font.weight: vChip.onFlight ? Font.DemiBold : Font.Medium
                                                textFormat: Text.PlainText
                                            }
                                            QQC2.Label {
                                                visible: vChip.isSta
                                                text: qsTr("STA")
                                                color: theme.fgMuted
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                textFormat: Text.PlainText
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. Recent Tests (tactile circular play button when vid_url is present).
                    ColumnLayout {
                        visible: !!(root.campaign && root.campaign.recent_tests && root.campaign.recent_tests.length)
                        Layout.fillWidth: true
                        spacing: 6

                        SectionTitle { text: qsTr("Recent Tests") }

                        BoxedCard {
                            Layout.fillWidth: true
                            padding: 4
                            implicitHeight: testsCol.implicitHeight + 8

                            ColumnLayout {
                                id: testsCol
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: root.campaign ? root.campaign.recent_tests : []
                                    QQC2.AbstractButton {
                                        id: tRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool hasUrl: root.isSafeWebUrl(modelData.vid_url)
                                        readonly property bool isLast: root.campaign && index === root.campaign.recent_tests.length - 1

                                        Layout.fillWidth: true
                                        implicitHeight: tContent.implicitHeight + 10
                                        padding: 0
                                        enabled: hasUrl
                                        hoverEnabled: true
                                        focusPolicy: hasUrl ? Qt.TabFocus : Qt.NoFocus
                                        Accessible.role: hasUrl ? Accessible.Link : Accessible.StaticText
                                        Accessible.name: tRow.modelData.name
                                        onClicked: if (tRow.hasUrl) root.openWebUrl(tRow.modelData.vid_url)

                                        background: Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: 1
                                            anchors.bottomMargin: 1
                                            radius: theme.controlRadius
                                            color: tRow.hasUrl && tRow.hovered ? theme.cardHoverBg : "transparent"
                                            border.width: tRow.visualFocus ? 2 : 0
                                            border.color: theme.accent
                                        }

                                        contentItem: Item {
                                            RowLayout {
                                                id: tContent
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 8
                                                spacing: 10

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    QQC2.Label {
                                                        text: tRow.modelData.name
                                                        color: theme.fg
                                                        font.pixelSize: 13
                                                        font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        textFormat: Text.PlainText
                                                    }
                                                    QQC2.Label {
                                                        text: [
                                                            root.formatShortDate(tRow.modelData.date),
                                                            root.shortLocation(tRow.modelData.location)
                                                        ].filter(function(s) { return s }).join(" · ")
                                                        color: theme.fgMuted
                                                        font.pixelSize: 12
                                                        font.features: { "tnum": 1 }
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        textFormat: Text.PlainText
                                                    }
                                                }

                                                // Tactile circular play badge.
                                                Rectangle {
                                                    visible: tRow.hasUrl
                                                    Layout.preferredWidth: 24
                                                    Layout.preferredHeight: 24
                                                    radius: 12
                                                    color: tRow.hovered
                                                           ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.18)
                                                           : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.08 : 0.06)
                                                    border.width: 1
                                                    border.color: tRow.hovered
                                                                  ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.40)
                                                                  : theme.border

                                                    SymbolicIcon {
                                                        anchors.centerIn: parent
                                                        width: 11
                                                        height: 11
                                                        name: "media-playback-start-symbolic"
                                                        color: tRow.hovered ? theme.accentText : theme.fgMuted
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible: !tRow.isLast
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.leftMargin: 13
                                                height: 1
                                                color: theme.border
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 4. Latest Videos (peeks cleanly with its first card above the fold at 740px).
                    ColumnLayout {
                        visible: !!(root.campaign && root.campaign.videos && root.campaign.videos.length)
                        Layout.fillWidth: true
                        spacing: 6

                        SectionTitle { text: qsTr("Latest Videos") }

                        BoxedCard {
                            Layout.fillWidth: true
                            padding: 4
                            implicitHeight: vidCol.implicitHeight + 8

                            ColumnLayout {
                                id: vidCol
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: root.campaign ? root.campaign.videos : []
                                    QQC2.AbstractButton {
                                        id: vRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool hasUrl: root.isSafeWebUrl(modelData.url)
                                        readonly property bool isLast: root.campaign && index === root.campaign.videos.length - 1

                                        Layout.fillWidth: true
                                        implicitHeight: vContent.implicitHeight + 12
                                        padding: 0
                                        enabled: hasUrl
                                        hoverEnabled: true
                                        focusPolicy: hasUrl ? Qt.TabFocus : Qt.NoFocus
                                        Accessible.role: hasUrl ? Accessible.Link : Accessible.StaticText
                                        Accessible.name: vRow.modelData.title
                                        onClicked: if (vRow.hasUrl) root.openWebUrl(vRow.modelData.url)

                                        background: Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: 1
                                            anchors.bottomMargin: 1
                                            radius: theme.controlRadius
                                            color: vRow.hasUrl && vRow.hovered ? theme.cardHoverBg : "transparent"
                                            border.width: vRow.visualFocus ? 2 : 0
                                            border.color: theme.accent
                                        }

                                        contentItem: Item {
                                            RowLayout {
                                                id: vContent
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 10
                                                anchors.rightMargin: 8
                                                spacing: 10

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    QQC2.Label {
                                                        text: vRow.modelData.title
                                                        color: vRow.hovered ? theme.accentText : theme.fg
                                                        font.pixelSize: 13
                                                        maximumLineCount: 2
                                                        wrapMode: Text.Wrap
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                        textFormat: Text.PlainText
                                                    }
                                                    QQC2.Label {
                                                        visible: !!vRow.modelData.date
                                                        text: root.formatShortDate(vRow.modelData.date)
                                                        color: theme.fgMuted
                                                        font.pixelSize: 12
                                                        font.features: { "tnum": 1 }
                                                        textFormat: Text.PlainText
                                                    }
                                                }

                                                SymbolicIcon {
                                                    visible: vRow.hasUrl
                                                    name: "external-link-symbolic"
                                                    color: vRow.hovered ? theme.accentText : theme.fgMuted
                                                    Layout.preferredWidth: 13
                                                    Layout.preferredHeight: 13
                                                }
                                            }

                                            Rectangle {
                                                visible: !vRow.isLast
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                anchors.leftMargin: 13
                                                height: 1
                                                color: theme.border
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Smooth bottom fade finishing cleanly above the shared bottom baseline so
            // scrolled cards never visually bleed into the window's bottom gutter.
            Rectangle {
                visible: !inspectorFlick.atYEnd && inspectorFlick.contentHeight > inspectorFlick.height
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 44
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.45; color: Qt.rgba(theme.windowBg.r, theme.windowBg.g, theme.windowBg.b, 0.72) }
                    GradientStop { position: 0.78; color: theme.windowBg }
                    GradientStop { position: 1.0; color: theme.windowBg }
                }
            }
        }
    }
}
