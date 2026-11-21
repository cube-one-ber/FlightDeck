import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Countdown.js" as Countdown

// The next launch as a bespoke split-unit aerospace countdown instrument,
// followed by upcoming launches grouped by day inside GNOME boxed cards.
Item {
    id: root

    property var launches: []
    property var next: null
    property double now: 0

    // Keep the horizontal hero and row countdowns intact at 720px; only stack below 600px.
    readonly property bool compact: width < 820
    readonly property bool narrow: width < 600
    readonly property bool hideRowCountdown: width < 580
    property int currentIndex: 0
    // The selection follows the launch ID across daemon refreshes.
    property int selectedId: -1
    property real savedContentY: 0
    property bool restoringModel: false
    // Hoisted onto root so the 350 ms double-click guard survives fast daemon reloads.
    property int lastPinId: -1
    property double lastPinMs: 0
    // Tracks instantiated row items by flat index for keyboard scroll-into-view.
    property var rowItems: ({})

    // Local date keys only change at midnight so dayGroups never rebuilds at 1 Hz.
    readonly property string todayKey: {
        var d = new Date(root.now)
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    }
    readonly property string tomorrowKey: {
        var d = new Date(root.now + 86400000)
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    }

    // Structured countdown segments for the hero telemetry instrument.
    readonly property var heroClock: {
        if (!root.next || root.next.net !== "") return null
        var t0Ms = Date.parse(root.next.t0)
        var secs = Math.floor((t0Ms - root.now) / 1000)
        var sign = secs >= 0 ? "T-" : "T+"
        var s = Math.abs(secs)
        var d = Math.floor(s / 86400)
        var h = Math.floor(s / 3600) % 24
        var m = Math.floor(s / 60) % 60
        var sec = s % 60
        function two(n) { return n < 10 ? "0" + n : "" + n }
        if (d > 0) {
            return {
                sign: sign,
                units: [
                    { value: two(d), label: qsTr("DAYS") },
                    { value: two(h), label: qsTr("HRS") },
                    { value: two(m), label: qsTr("MIN") }
                ]
            }
        }
        return {
            sign: sign,
            units: [
                { value: two(h), label: qsTr("HRS") },
                { value: two(m), label: qsTr("MIN") },
                { value: two(sec), label: qsTr("SEC") }
            ]
        }
    }

    // Groups launches by day label while preserving each launch's flat index for J/K navigation.
    readonly property var dayGroups: {
        var lang = translator.language
        var tk = root.todayKey
        var tmk = root.tomorrowKey
        void lang
        var groups = []
        var byKey = {}
        for (var i = 0; i < launches.length; ++i) {
            var l = launches[i]
            var label = dayLabel(l, tk, tmk)
            var grp = byKey[label]
            if (!grp) {
                grp = { label: label, isToday: launchDateKey(l) === tk, items: [] }
                byKey[label] = grp
                groups.push(grp)
            }
            grp.items.push({ launch: l, flatIndex: i })
        }
        return groups
    }

    function ensureSelectedVisible(idx) {
        var item = rowItems[idx]
        if (!item) return
        var pt = item.mapToItem(contentColumn, 0, 0)
        var top = pt.y + 16
        var bottom = top + item.height
        var pad = 28
        if (top - pad < flick.contentY) {
            flick.contentY = Math.max(0, top - pad)
        } else if (bottom + pad > flick.contentY + flick.height) {
            var maxY = Math.max(0, flick.contentHeight - flick.height)
            flick.contentY = Math.min(maxY, bottom + pad - flick.height)
        }
    }

    function selectIndex(idx) {
        if (launches.length === 0) return
        root.forceActiveFocus()
        var clamped = Math.max(0, Math.min(launches.length - 1, idx))
        currentIndex = clamped
        selectedId = launches[clamped].id
        ensureSelectedVisible(clamped)
        Qt.callLater(function() { if (!root.restoringModel) root.savedContentY = flick.contentY })
    }

    onLaunchesChanged: {
        restoringModel = true
        var id = root.selectedId
        var y = root.savedContentY
        Qt.callLater(function() {
            var i = id >= 0 ? root.launches.findIndex(function(l) { return l.id === id }) : -1
            root.currentIndex = i >= 0 ? i : 0
            if (root.launches[root.currentIndex] && id >= 0)
                root.selectedId = root.launches[root.currentIndex].id
            var maxY = Math.max(0, flick.contentHeight - flick.height)
            flick.contentY = Math.max(0, Math.min(y, maxY))
            root.savedContentY = flick.contentY
            root.restoringModel = false
        })
    }

    function move(delta) { selectIndex(currentIndex + delta) }

    // Space pins the selected launch to the bar, or clears the pin.
    function activate() {
        var l = launches[currentIndex]
        if (!l) return
        if (l.pinned) backend.unpin()
        else backend.pin(l.id)
    }

    function togglePin(launch) {
        if (!launch) return
        if (launch.pinned) backend.unpin()
        else backend.pin(launch.id)
    }

    function openDetails(launch) {
        if (launch && Number.isInteger(launch.id) && launch.id > 0)
            Qt.openUrlExternally("https://nextspaceflight.com/launches/details/" + launch.id + "/")
    }

    function openLink() { openDetails(launches[currentIndex]) }

    function launchDateKey(l) {
        if (l.net !== "" && l.precision !== "day") return ""
        var d = l.precision === "day" ? new Date(l.t0.slice(0, 10) + "T12:00:00") : new Date(l.t0)
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    }

    // Sentence-case day heading with Today / Tomorrow callouts.
    function dayLabel(l, tk, tmk) {
        if (l.net !== "" && l.precision !== "day") return l.net
        var d = l.precision === "day" ? new Date(l.t0.slice(0, 10) + "T12:00:00") : new Date(l.t0)
        var formatted = d.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
        var key = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
        if (key === tk) return qsTr("Today · %1").arg(formatted)
        if (key === tmk) return qsTr("Tomorrow · %1").arg(formatted)
        return formatted
    }

    function heroTimeLine(iso) {
        var lang = translator.language
        void lang
        var d = new Date(iso)
        var local = d.toLocaleTimeString(Qt.locale(), "HH:mm")
        var utc = iso.slice(11, 16)
        var dateStr = d.toLocaleDateString(Qt.locale(), "ddd, d MMM")
        return d.getTimezoneOffset() === 0
               ? dateStr + " · " + utc + " UTC"
               : dateStr + " · " + local + " (" + utc + " UTC)"
    }

    function rowPrimaryClock(iso) {
        var lang = translator.language
        void lang
        var d = new Date(iso)
        return d.getTimezoneOffset() === 0 ? iso.slice(11, 16) : d.toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    function rowIsUtcOnly(iso) {
        return new Date(iso).getTimezoneOffset() === 0
    }

    function rowSecondaryTime(iso) {
        var d = new Date(iso)
        return d.getTimezoneOffset() === 0 ? "" : iso.slice(11, 16) + " UTC"
    }

    component HeroActions: RowLayout {
        spacing: 8

        QQC2.AbstractButton {
            id: pinHeroBtn
            implicitWidth: pinHeroRow.implicitWidth + 18
            implicitHeight: 30
            hoverEnabled: true
            focusPolicy: Qt.TabFocus
            Accessible.role: Accessible.Button
            Accessible.name: root.next && root.next.pinned ? qsTr("Unpin launch") : qsTr("Pin launch to bar")
            onClicked: {
                var t = Date.now()
                if (!root.next) return
                if (root.lastPinId === root.next.id && t - root.lastPinMs < 350) return
                root.lastPinId = root.next.id
                root.lastPinMs = t
                root.togglePin(root.next)
            }

            background: Rectangle {
                radius: theme.controlRadius
                color: root.next && root.next.pinned
                       ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, pinHeroBtn.hovered ? 0.24 : 0.16)
                       : (pinHeroBtn.hovered ? theme.cardHoverBg : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.05 : 0.03))
                border.width: pinHeroBtn.visualFocus ? 2 : 1
                border.color: pinHeroBtn.visualFocus
                              ? theme.accent
                              : (root.next && root.next.pinned
                                 ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.40)
                                 : theme.borderStrong)
            }

            contentItem: Item {
                RowLayout {
                    id: pinHeroRow
                    anchors.centerIn: parent
                    spacing: 6
                    SymbolicIcon {
                        name: "pin-symbolic"
                        color: root.next && root.next.pinned ? theme.accentText : theme.fg
                        Layout.preferredWidth: 13
                        Layout.preferredHeight: 13
                    }
                    QQC2.Label {
                        text: root.next && root.next.pinned ? qsTr("Unpin") : qsTr("Pin to Bar")
                        color: root.next && root.next.pinned ? theme.accentText : theme.fg
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        QQC2.AbstractButton {
            id: detHeroBtn
            implicitWidth: detHeroRow.implicitWidth + 18
            implicitHeight: 30
            hoverEnabled: true
            focusPolicy: Qt.TabFocus
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Open launch details")
            onClicked: root.openDetails(root.next)

            background: Rectangle {
                radius: theme.controlRadius
                color: detHeroBtn.hovered ? theme.cardHoverBg : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.05 : 0.03)
                border.width: detHeroBtn.visualFocus ? 2 : 1
                border.color: detHeroBtn.visualFocus ? theme.accent : theme.borderStrong
            }

            contentItem: Item {
                RowLayout {
                    id: detHeroRow
                    anchors.centerIn: parent
                    spacing: 6
                    QQC2.Label {
                        text: qsTr("Details")
                        color: theme.fg
                        font.pixelSize: 12
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
        }
    }

    Kirigami.PlaceholderMessage {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        visible: !root.next && root.launches.length === 0
        icon.name: "view-calendar-symbolic"
        text: qsTr("No Launches Scheduled")
        explanation: qsTr("No upcoming launches fall within your configured schedule window.")
    }

    Flickable {
        id: flick
        anchors.fill: parent
        visible: !!root.next || root.launches.length > 0
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 36
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: if (!root.restoringModel && (contentY > 0 || moving || dragging || flicking)) root.savedContentY = contentY
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        ColumnLayout {
            id: contentColumn
            x: Math.max(20, Math.floor((flick.width - width) / 2))
            y: 16
            width: Math.min(flick.width - 40, 1020)
            spacing: 14

            // Bespoke Aerospace Countdown Hero Card.
            BoxedCard {
                id: heroCard
                visible: !!root.next
                Layout.fillWidth: true
                accented: !!(root.next && root.next.pinned)
                padding: 0
                implicitHeight: heroLayout.implicitHeight + (root.compact ? 30 : 36)

                // Subtle top-to-bottom accent wash for focal depth in both dark and light modes.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Math.max(0, theme.cardRadius - 1)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, theme.isDark ? 0.08 : 0.055) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                GridLayout {
                    id: heroLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: root.compact ? 15 : 18
                    anchors.leftMargin: root.compact ? 18 : 22
                    anchors.rightMargin: root.compact ? 18 : 22
                    columns: root.narrow ? 1 : 3
                    columnSpacing: root.compact ? 16 : 20
                    rowSpacing: root.narrow ? 10 : 14

                    // Left zone: mission identity, vehicle, pad, and actions.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: root.compact ? 4 : 5

                        RowLayout {
                            spacing: 8

                            StatusPill {
                                label: root.next && root.next.pinned ? qsTr("Pinned Launch") : qsTr("Next Launch")
                                iconName: root.next && root.next.pinned ? "pin-symbolic" : ""
                                showDot: false
                                tint: root.next && root.next.pinned ? theme.accentText : theme.fgMuted
                                compact: true
                            }

                            StatusPill {
                                visible: !!(root.next && root.next.status)
                                label: root.next ? root.next.status : ""
                                tint: root.next ? theme.statusColor(root.next.status_color) : theme.fgMuted
                                compact: true
                            }
                        }

                        QQC2.Label {
                            text: root.next ? root.next.name : ""
                            color: theme.fg
                            font.pixelSize: root.compact ? 20 : 24
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                        }

                        QQC2.Label {
                            text: !root.next ? "" : [root.next.rocket, root.next.provider].filter(function(s) { return s }).join(" · ")
                            color: theme.fg
                            opacity: 0.90
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                        }

                        QQC2.Label {
                            text: !root.next ? "" : [root.next.pad, root.next.location].filter(function(s) { return s }).join(", ")
                            color: theme.fgMuted
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                        }

                        HeroActions {
                            visible: !root.narrow
                            Layout.topMargin: 6
                        }
                    }

                    // Subtle vertical divider separating mission identity from telemetry readout.
                    Rectangle {
                        visible: !root.narrow
                        Layout.preferredWidth: visible ? 1 : 0
                        Layout.preferredHeight: visible ? -1 : 0
                        Layout.fillHeight: visible
                        Layout.topMargin: visible ? 6 : 0
                        Layout.bottomMargin: visible ? 6 : 0
                        color: theme.border
                    }

                    // Right zone: bespoke split-unit T-minus instrument cluster + liftoff time.
                    ColumnLayout {
                        Layout.fillWidth: root.narrow
                        Layout.alignment: root.narrow ? Qt.AlignLeft : (Qt.AlignRight | Qt.AlignVCenter)
                        spacing: root.narrow ? 5 : 8

                        // Split-unit countdown instrument (inspired by Next Spaceflight & Space Launch Now).
                        RowLayout {
                            visible: !!root.heroClock
                            Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignRight
                            spacing: root.compact ? 4 : 6

                            QQC2.Label {
                                text: root.heroClock ? root.heroClock.sign : ""
                                color: theme.fgMuted
                                font.pixelSize: root.compact ? 20 : 26
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: root.compact ? 8 : 10
                                textFormat: Text.PlainText
                            }

                            Repeater {
                                model: root.heroClock ? root.heroClock.units : []
                                RowLayout {
                                    required property var modelData
                                    required property int index
                                    spacing: root.compact ? 4 : 6

                                    QQC2.Label {
                                        visible: index > 0
                                        text: ":"
                                        color: theme.fgMuted
                                        opacity: 0.55
                                        font.pixelSize: root.compact ? 22 : 30
                                        font.weight: Font.Bold
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: root.compact ? 5 : 7
                                        textFormat: Text.PlainText
                                    }

                                    ColumnLayout {
                                        spacing: 3

                                        Rectangle {
                                            implicitWidth: root.compact ? 48 : 64
                                            implicitHeight: root.compact ? 42 : 52
                                            radius: theme.controlRadius > 0 ? theme.controlRadius : 3
                                            color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, theme.isDark ? 0.065 : 0.045)
                                            border.width: 1
                                            border.color: theme.border

                                            QQC2.Label {
                                                anchors.centerIn: parent
                                                text: modelData.value
                                                color: theme.accentText
                                                font.pixelSize: root.compact ? 23 : 32
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                                textFormat: Text.PlainText
                                            }
                                        }

                                        QQC2.Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.label
                                            color: theme.fgMuted
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 0.8
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }
                            }
                        }

                        // Inexact NET display when pinned launch has no exact T-0.
                        QQC2.Label {
                            visible: !root.heroClock && !!root.next
                            text: root.next ? root.next.net : ""
                            color: theme.fg
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignRight
                            textFormat: Text.PlainText
                        }

                        // Exact liftoff timestamp beneath the clock.
                        QQC2.Label {
                            text: !root.next ? "" : (root.next.net === "" ? root.heroTimeLine(root.next.t0) : qsTr("Exact T-0 to be determined"))
                            color: theme.fgMuted
                            font.pixelSize: 13
                            font.features: { "tnum": 1 }
                            Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignRight
                            textFormat: Text.PlainText
                        }

                        // On narrow viewports, anchor actions beneath the countdown so title flows straight into T-.
                        HeroActions {
                            visible: root.narrow
                            Layout.topMargin: 4
                        }
                    }
                }
            }

            // Boxed day groups (GNOME AdwPreferencesGroup pattern).
            Repeater {
                model: root.dayGroups

                ColumnLayout {
                    id: daySection
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.topMargin: index > 0 ? 4 : 0
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 2
                        spacing: 8

                        QQC2.Label {
                            text: daySection.modelData.label
                            color: theme.fg
                            opacity: daySection.modelData.isToday ? 1.0 : 0.86
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            textFormat: Text.PlainText
                        }

                        QQC2.Label {
                            visible: daySection.modelData.items.length > 1
                            text: qsTr("%n launches", "", daySection.modelData.items.length)
                            color: theme.fgMuted
                            font.pixelSize: 12
                            font.features: { "tnum": 1 }
                            textFormat: Text.PlainText
                        }
                    }

                    BoxedCard {
                        Layout.fillWidth: true
                        padding: 4
                        implicitHeight: dayRowsCol.implicitHeight + 8

                        ColumnLayout {
                            id: dayRowsCol
                            width: parent.width
                            spacing: 0

                            Repeater {
                                model: daySection.modelData.items

                                Item {
                                    id: lRow
                                    required property var modelData
                                    required property int index
                                    readonly property var launch: modelData.launch
                                    readonly property int flatIndex: modelData.flatIndex
                                    readonly property bool selected: root.currentIndex === flatIndex
                                    readonly property bool isLast: index === daySection.modelData.items.length - 1
                                    readonly property bool showActions: rowMouse.containsMouse || pinActionBtn.hovered || linkActionBtn.hovered || pinActionBtn.visualFocus || linkActionBtn.visualFocus || selected || launch.pinned

                                    Layout.fillWidth: true
                                    implicitHeight: 56

                                    Component.onCompleted: root.rowItems[flatIndex] = lRow
                                    Component.onDestruction: {
                                        if (root.rowItems[flatIndex] === lRow)
                                            delete root.rowItems[flatIndex]
                                    }

                                    // Inset rounded selection surface keeps corners strictly inside the card silhouette.
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.topMargin: 2
                                        anchors.bottomMargin: 2
                                        radius: theme.controlRadius
                                        color: lRow.selected
                                               ? theme.cardSelectedBg
                                               : (rowMouse.containsMouse ? theme.cardHoverBg : "transparent")
                                    }

                                    // Subtle leading focus bar that never competes with the hero card above.
                                    Rectangle {
                                        visible: lRow.selected
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.topMargin: 9
                                        anchors.bottomMargin: 9
                                        anchors.leftMargin: 3
                                        width: 2.5
                                        radius: theme.controlRadius > 0 ? 1.25 : 0
                                        color: Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, 0.72)
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectIndex(lRow.flatIndex)
                                        onDoubleClicked: {
                                            root.selectIndex(lRow.flatIndex)
                                            root.activate()
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 14

                                        // Compact time column: bold numerals + muted UTC tag for crisp vertical scanning.
                                        ColumnLayout {
                                            Layout.preferredWidth: root.narrow ? 86 : 98
                                            spacing: 1

                                            RowLayout {
                                                visible: lRow.launch.net === ""
                                                spacing: 4
                                                QQC2.Label {
                                                    text: lRow.launch.net === "" ? root.rowPrimaryClock(lRow.launch.t0) : ""
                                                    color: theme.fg
                                                    font.pixelSize: 14
                                                    font.weight: Font.DemiBold
                                                    font.features: { "tnum": 1 }
                                                    textFormat: Text.PlainText
                                                }
                                                QQC2.Label {
                                                    visible: lRow.launch.net === "" && root.rowIsUtcOnly(lRow.launch.t0)
                                                    text: "UTC"
                                                    color: theme.fgMuted
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                            QQC2.Label {
                                                readonly property string sec: lRow.launch.net === "" ? root.rowSecondaryTime(lRow.launch.t0) : ""
                                                visible: sec !== ""
                                                text: sec
                                                color: theme.fgMuted
                                                font.pixelSize: 12
                                                font.features: { "tnum": 1 }
                                                textFormat: Text.PlainText
                                            }
                                            StatusPill {
                                                visible: lRow.launch.net !== ""
                                                label: lRow.launch.net
                                                tint: theme.fgMuted
                                                showDot: false
                                                compact: true
                                            }
                                        }

                                        // Mission & vehicle stack.
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 7

                                                QQC2.Label {
                                                    text: lRow.launch.name
                                                    color: theme.fg
                                                    font.pixelSize: 14
                                                    font.weight: lRow.launch.pinned || lRow.selected ? Font.DemiBold : Font.Medium
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    textFormat: Text.PlainText
                                                }

                                                StatusPill {
                                                    visible: lRow.launch.pinned
                                                    label: qsTr("Pinned")
                                                    iconName: "pin-symbolic"
                                                    tint: theme.accentText
                                                    compact: true
                                                }
                                            }

                                            QQC2.Label {
                                                text: [lRow.launch.rocket, lRow.launch.provider, lRow.launch.pad].filter(function(s) { return s }).join(" · ")
                                                color: theme.fgMuted
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                            }
                                        }

                                        // Live countdown on viewports with sufficient horizontal space.
                                        QQC2.Label {
                                            visible: lRow.launch.net === "" && !root.hideRowCountdown
                                            Layout.preferredWidth: root.compact ? 84 : 92
                                            horizontalAlignment: Text.AlignRight
                                            text: Countdown.format(Date.parse(lRow.launch.t0), root.now)
                                            color: theme.fg
                                            opacity: 0.88
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                            font.features: { "tnum": 1 }
                                            textFormat: Text.PlainText
                                        }

                                        // Contrast-normalized status badge.
                                        StatusPill {
                                            label: lRow.launch.status
                                            tint: theme.statusColor(lRow.launch.status_color)
                                            compact: true
                                        }

                                        // Clearly legible resting affordances (0.80 -> 1.0 on hover/selection/focus).
                                        RowLayout {
                                            spacing: 4
                                            opacity: lRow.showActions ? 1.0 : 0.80
                                            Behavior on opacity { NumberAnimation { duration: 120 } }

                                            QQC2.AbstractButton {
                                                id: pinActionBtn
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                hoverEnabled: true
                                                focusPolicy: Qt.TabFocus
                                                Accessible.role: Accessible.Button
                                                Accessible.name: lRow.launch.pinned ? qsTr("Unpin %1").arg(lRow.launch.name) : qsTr("Pin %1 to bar").arg(lRow.launch.name)
                                                onClicked: {
                                                    var t = Date.now()
                                                    if (root.lastPinId === lRow.launch.id && t - root.lastPinMs < 350) return
                                                    root.lastPinId = lRow.launch.id
                                                    root.lastPinMs = t
                                                    root.selectIndex(lRow.flatIndex)
                                                    root.togglePin(lRow.launch)
                                                }

                                                background: Rectangle {
                                                    radius: theme.controlRadius
                                                    color: pinActionBtn.hovered
                                                           ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.10)
                                                           : "transparent"
                                                    border.width: pinActionBtn.visualFocus ? 2 : 0
                                                    border.color: theme.accent
                                                }

                                                contentItem: Item {
                                                    SymbolicIcon {
                                                        anchors.centerIn: parent
                                                        width: 14
                                                        height: 14
                                                        name: "pin-symbolic"
                                                        color: lRow.launch.pinned ? theme.accentText : theme.fgMuted
                                                    }
                                                }

                                                QQC2.ToolTip.visible: pinActionBtn.hovered
                                                QQC2.ToolTip.delay: 350
                                                QQC2.ToolTip.text: lRow.launch.pinned ? qsTr("Unpin launch (Space)") : qsTr("Pin to bar (Space)")
                                            }

                                            QQC2.AbstractButton {
                                                id: linkActionBtn
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28
                                                hoverEnabled: true
                                                focusPolicy: Qt.TabFocus
                                                Accessible.role: Accessible.Button
                                                Accessible.name: qsTr("Open details for %1").arg(lRow.launch.name)
                                                onClicked: {
                                                    root.selectIndex(lRow.flatIndex)
                                                    root.openDetails(lRow.launch)
                                                }

                                                background: Rectangle {
                                                    radius: theme.controlRadius
                                                    color: linkActionBtn.hovered
                                                           ? Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.10)
                                                           : "transparent"
                                                    border.width: linkActionBtn.visualFocus ? 2 : 0
                                                    border.color: theme.accent
                                                }

                                                contentItem: Item {
                                                    SymbolicIcon {
                                                        anchors.centerIn: parent
                                                        width: 13
                                                        height: 13
                                                        name: "external-link-symbolic"
                                                        color: linkActionBtn.hovered ? theme.fg : theme.fgMuted
                                                    }
                                                }

                                                QQC2.ToolTip.visible: linkActionBtn.hovered
                                                QQC2.ToolTip.delay: 350
                                                QQC2.ToolTip.text: qsTr("Open launch details (L)")
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: !lRow.isLast && !lRow.selected && (lRow.flatIndex + 1 !== root.currentIndex)
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
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

    // Smooth bottom fade when more schedule days lie below the viewport.
    Rectangle {
        visible: flick.visible && !flick.atYEnd && flick.contentHeight > flick.height
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 32
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.65; color: Qt.rgba(theme.windowBg.r, theme.windowBg.g, theme.windowBg.b, 0.82) }
            GradientStop { position: 1.0; color: theme.windowBg }
        }
    }
}
