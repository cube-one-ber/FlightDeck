import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Countdown.js" as Countdown

Kirigami.ApplicationWindow {
    id: win

    width: 1120
    height: 740
    minimumWidth: 720
    minimumHeight: 480
    visible: true
    title: "FlightDeck"
    color: theme.windowBg

    // Suppress Kirigami's default PageRow toolbar; our flat GNOME HeaderBar owns top chrome.
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.visible: false

    // Bridge live Omarchy colors into Kirigami.Theme for all Kirigami primitives.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: theme.windowBg
    Kirigami.Theme.alternateBackgroundColor: theme.cardBg
    Kirigami.Theme.textColor: theme.fg
    Kirigami.Theme.disabledTextColor: theme.fgMuted
    Kirigami.Theme.highlightColor: theme.accent
    Kirigami.Theme.highlightedTextColor: theme.accentForeground
    Kirigami.Theme.positiveTextColor: theme.positive
    Kirigami.Theme.neutralTextColor: theme.warning
    Kirigami.Theme.negativeTextColor: theme.negative
    Kirigami.Theme.linkColor: theme.accentText

    property int view: 0
    property bool helpVisible: false
    property double now: Date.now()
    readonly property var st: backend.state
    readonly property var sources: st.sources || ({})
    readonly property bool shortcutsActive: !win.helpVisible && !headerBar.menuOpen
    readonly property bool buttonFocused: win.activeFocusItem instanceof QQC2.AbstractButton
    // The daemon publishes the earliest deadline across sources as bar.stale_after.
    readonly property bool stale: Countdown.stale(st.bar ? st.bar.stale_after : null, win.now)
    // The older of the two live feeds, so "synced 4 mins ago" never flatters.
    readonly property string synced: ["starship", "launches"]
        .map(function(k) { return sources[k] ? sources[k].fetched_at : null })
        .reduce(function(a, b) { return !a || !b ? null : (a < b ? a : b) }, "9999")

    readonly property string sourceError: {
        var keys = ["starship", "launches", "lookups"]
        for (var i = 0; i < keys.length; ++i) {
            var s = sources[keys[i]]
            if (s && s.error) return s.error
        }
        return ""
    }

    readonly property string freshnessTooltip: {
        var lang = translator.language
        void lang
        var lines = []
        var labels = { starship: qsTr("Starship"), launches: qsTr("Launches"), lookups: qsTr("Lookups") }
        var keys = ["starship", "launches", "lookups"]
        for (var i = 0; i < keys.length; ++i) {
            var k = keys[i]
            var s = sources[k]
            if (!s) continue
            var line = labels[k] + " · " + win.ago(s.fetched_at)
            if (s.error) line += " (" + s.error + ")"
            lines.push(line)
        }
        return lines.join("\n")
    }

    onViewChanged: currentView().forceActiveFocus()

    onHelpVisibleChanged: {
        if (helpVisible && !helpDialog.opened) helpDialog.open()
        else if (!helpVisible && helpDialog.opened) helpDialog.close()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: win.now = Date.now()
    }

    Connections {
        target: backend
        function onToastRequested(message) {
            toastOverlay.show(message)
        }
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequences: ["Q", "Ctrl+Q"]; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "F10"; context: Qt.ApplicationShortcut; enabled: !win.helpVisible; onActivated: headerBar.openMenu() }
    Shortcut { sequences: ["1", "Alt+1"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: win.view = 0 }
    Shortcut { sequences: ["2", "Alt+2"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: win.view = 1 }
    Shortcut { sequence: "Ctrl+Tab"; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: win.view = 1 - win.view }
    Shortcut { sequences: ["R", "Ctrl+R"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: backend.sync() }
    Shortcut { sequence: "C"; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: backend.copyChecklist() }
    Shortcut { sequence: "W"; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: backend.copyWeekend() }
    Shortcut { sequences: ["J", "Down"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: currentView().move(1) }
    Shortcut { sequences: ["K", "Up"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: currentView().move(-1) }
    // When a focusable button has keyboard focus, let Space/Return/Enter activate it.
    Shortcut { sequences: ["Space", "Return", "Enter"]; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive && !win.buttonFocused; onActivated: currentView().activate() }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.ApplicationShortcut
        enabled: win.shortcutsActive && win.buttonFocused
        onActivated: {
            if (win.activeFocusItem.action) win.activeFocusItem.action.trigger()
            else win.activeFocusItem.clicked()
        }
    }
    Shortcut { sequence: "L"; context: Qt.ApplicationShortcut; enabled: win.shortcutsActive; onActivated: currentView().openLink() }

    function currentView() { return win.view === 0 ? campaign : schedule }

    // Plural-aware relative timestamp for the freshness indicator and tooltips.
    function ago(iso) {
        if (!iso) return qsTr("never")
        var lang = translator.language
        void lang
        var mins = Math.max(0, Math.round((win.now - Date.parse(iso)) / 60000))
        if (mins === 0) return qsTr("Just now")
        if (mins < 60) return qsTr("%n min ago", "", mins)
        if (mins < 2880) return qsTr("%n hr ago", "", Math.round(mins / 60))
        return qsTr("%n day ago", "", Math.round(mins / 1440))
    }

    function isSafeWebUrl(u) {
        if (typeof u !== "string") return false
        return /^https?:\/\/[^/\s?#]+(?:[/?#][^\s]*)?$/i.test(u.trim())
    }

    function openWebUrl(u) {
        if (isSafeWebUrl(u)) Qt.openUrlExternally(u.trim())
    }

    header: HeaderBar {
        id: headerBar
        currentView: win.view
        stale: win.stale
        syncedText: win.ago(win.synced)
        freshnessTooltip: win.freshnessTooltip
        busy: backend.busy
        hasProblem: backend.problem !== ""
        hasCampaign: !!(win.st && win.st.campaign)
        campaignProgress: win.st && win.st.campaign
                          ? win.st.campaign.done + "/" + win.st.campaign.total
                          : ""
        liveUrl: win.st && win.st.campaign && win.isSafeWebUrl(win.st.campaign.live_url)
                 ? win.st.campaign.live_url.trim()
                 : ""

        onViewSelected: function(idx) { win.view = idx }
        onSyncRequested: backend.sync()
        onCopyChecklistRequested: backend.copyChecklist()
        onCopyWeekendRequested: backend.copyWeekend()
        onOpenLiveRequested: win.openWebUrl(liveUrl)
        onShortcutsRequested: win.helpVisible = true
        onQuitRequested: Qt.quit()
    }

    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top inline warning banner when feed data is stale or failing.
            Kirigami.InlineMessage {
                id: staleBanner
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: visible ? 12 : 0
                visible: backend.problem === "" && win.stale
                type: Kirigami.MessageType.Warning
                text: win.sourceError !== ""
                      ? qsTr("Live feeds are stale (synced %1) — %2").arg(win.ago(win.synced)).arg(win.sourceError)
                      : qsTr("Live feeds are stale (last synced %1). Showing cached data.").arg(win.ago(win.synced))
                actions: [
                    Kirigami.Action {
                        text: qsTr("Sync Now")
                        icon.name: "view-refresh-symbolic"
                        onTriggered: backend.sync()
                    }
                ]
            }

            // Centered GNOME AdwStatusPage / Kirigami.PlaceholderMessage for fatal state problems.
            Item {
                visible: backend.problem !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, 460)
                    icon.name: "dialog-warning-symbolic"
                    text: qsTr("Unable to Load FlightDeck Data")
                    explanation: backend.problem
                    helpfulAction: Kirigami.Action {
                        text: qsTr("Sync Now")
                        icon.name: "view-refresh-symbolic"
                        onTriggered: backend.sync()
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.view
                visible: backend.problem === ""

                CampaignView {
                    id: campaign
                    campaign: win.st.campaign || null
                }
                ScheduleView {
                    id: schedule
                    launches: win.st.launches || []
                    next: win.st.next || null
                    now: win.now
                }
            }
        }

        ToastOverlay {
            id: toastOverlay
            anchors.fill: parent
            z: 90
        }
    }

    HelpOverlay {
        id: helpDialog
        onClosed: win.helpVisible = false
    }
}
