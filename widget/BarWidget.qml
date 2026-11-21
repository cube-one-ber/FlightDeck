import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Countdown.js" as Countdown

// Bar pill for FlightDeck. It only reads ~/.local/share/flightdeck/state.json,
// which the `flightdeck daemon` service keeps current, and calls the
// `flightdeck` CLI for actions. Click for the popup, middle-click to sync,
// right-click to open Mission Control.
BarWidget {
  id: root
  moduleName: "io.github.cube-one-ber.flightdeck"

  // The same directory the daemon writes: $XDG_DATA_HOME, else ~/.local/share.
  readonly property string statePath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/flightdeck/state.json"
  property var feed: null
  property bool popupOpen: false
  property double now: Date.now()

  readonly property var bar_: feed ? feed.bar : null
  readonly property var campaign: feed ? feed.campaign : null
  readonly property bool stale: !bar_ || Countdown.stale(bar_.stale_after, now)
  readonly property double t0Ms: bar_ && bar_.t0 ? Date.parse(bar_.t0) : NaN
  readonly property string when: !bar_ ? "" : (!isNaN(t0Ms) ? Countdown.format(t0Ms, now) : bar_.net)
  readonly property string label: {
    if (!bar_) return ""
    var parts = []
    if (bar_.progress) parts.push(bar_.progress)
    if (bar_.label) parts.push(bar_.label + " " + when)
    return parts.join("  ·  ")
  }
  // Popup content: the hero is the bar's launch; the list is what follows it.
  readonly property var hero: feed ? feed.next : null
  readonly property var later: feed ? feed.launches.filter(function(l) {
    return (!hero || l.id !== hero.id) && Date.parse(l.t0) > now - 3600000
  }).slice(0, 4) : []
  readonly property var milestones: campaign ? campaign.milestones : []
  readonly property var lastDone: { var d = milestones.filter(function(m) { return m.done }); return d.length ? d[d.length - 1] : null }
  readonly property var pending: milestones.filter(function(m) { return !m.done })
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.darker(fg, 1.4)
  readonly property string family: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property int checkWidth: Style.space(16)
  function localTime(iso, fmt) { return new Date(iso).toLocaleString(Qt.locale(Commons.I18n.formatLocale), fmt) }
  function join(parts) { return parts.filter(function(s) { return s }).join("  ·  ") }


  function close() { popupOpen = false }
  function run(args) { Quickshell.execDetached(["flightdeck"].concat(args)) }

  function load(text) {
    try {
      var s = JSON.parse(text)
      // Only read the shape this widget was written against.
      root.feed = s && s.schema_version === 1 ? s : null
    } catch (e) {
      root.feed = null
    }
  }

  function tooltip() {
    if (!feed) return "FlightDeck: no data yet. Is the flightdeck service running?"
    var lines = []
    if (feed.next) lines.push([feed.next.name, feed.next.rocket, feed.next.pad].filter(function(s) { return s }).join(" · "))
    for (var k in feed.sources) {
      var src = feed.sources[k]
      if (Countdown.stale(src.stale_after, now) || src.error) lines.push(k + ": last sync " + Countdown.ago(src.fetched_at, now) + (src.error ? " (failing)" : ""))
    }
    return lines.join("\n")
  }

  FileView {
    id: file
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.load(text())
    onLoadFailed: root.feed = null
  }

  // The daemon replaces state.json by rename; reload now and then in case a
  // watch is lost with the old file.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: file.reload()
  }

  // Tick every second only when there is a countdown under a day away.
  Timer {
    interval: !isNaN(root.t0Ms) && Math.abs(root.t0Ms - root.now) < 86400000 ? 1000 : 30000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  // Wide text pills paint across the whole row, so match Omarchy's clock and
  // power widgets: span the painted content horizontally instead of Bar.qml's
  // 55% slot-width fallback (meant for square icon slots), and keep the
  // icon-sized mark on vertical bars.
  readonly property real openPanelIndicatorWidth: row.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    opacity: root.stale ? 0.5 : 1

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: "󱎯"
      color: root.bar ? root.bar.barForeground : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && text !== ""
      text: root.label
      color: root.bar ? root.bar.barForeground : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.run(["sync"])
      else if (mouse.button === Qt.RightButton) root.run(["open"])
      else root.popupOpen = !root.popupOpen
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip())
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      component Line: Text {
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }
      // A launch status other than Go, tinted with the feed's status colour.
      component Chip: Rectangle {
        property string label: ""
        property color tint: root.muted
        visible: label !== "" && label !== "Go"
        implicitWidth: chipText.implicitWidth + Style.space(12)
        implicitHeight: chipText.implicitHeight + Style.space(4)
        radius: height / 2
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.18)
        Text {
          id: chipText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: parent.label
          color: parent.tint
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }

      Line {
        visible: !root.feed
        width: column.width
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        text: "No FlightDeck data yet. Start the service with\nsystemctl --user enable --now flightdeck"
      }

      // Next launch: the countdown is the point of the widget, so it leads.
      Column {
        visible: !!root.hero
        width: column.width
        spacing: Style.space(3)

        Item {
          width: parent.width
          height: heroLabel.implicitHeight
          PanelSectionHeader {
            id: heroLabel
            text: root.hero && root.hero.pinned ? "󰐃 PINNED" : "NEXT LAUNCH"
            foreground: root.fg
          }
          Chip {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: root.hero ? root.hero.status : ""
            tint: root.hero && root.hero.status_color ? root.hero.status_color : root.muted
          }
        }
        Line {
          text: !root.hero ? "" : root.hero.net !== "" ? root.hero.net : Countdown.format(Date.parse(root.hero.t0), root.now)
          color: Commons.Color.accent
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }
        Line {
          width: parent.width
          text: root.hero ? root.hero.name : ""
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Line {
          width: parent.width
          color: root.muted
          font.pixelSize: Style.font.body
          text: !root.hero ? "" : root.join([root.hero.rocket, root.hero.pad])
        }
        Line {
          visible: !!root.hero && root.hero.net === ""
          width: parent.width
          color: root.muted
          font.pixelSize: Style.font.body
          text: root.hero ? root.localTime(root.hero.t0, "dddd d MMMM, HH:mm t") : ""
        }
      }

      PanelSeparator { visible: !!root.hero && !!root.campaign; foreground: root.fg }

      // Starship campaign: segmented progress, the last milestone met, and what's next.
      Column {
        visible: !!root.campaign
        width: column.width
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: campaignLabel.implicitHeight
          PanelSectionHeader {
            id: campaignLabel
            text: root.campaign ? root.campaign.title.toUpperCase() : ""
            foreground: root.fg
          }
          Line {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.campaign ? root.campaign.done + " / " + root.campaign.total : ""
            color: root.muted
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          id: segments
          readonly property int count: Math.max(1, root.milestones.length)
          spacing: Style.space(2)
          Repeater {
            model: root.milestones
            Rectangle {
              required property var modelData
              width: (column.width - segments.spacing * (segments.count - 1)) / segments.count
              height: Style.space(6)
              radius: Style.space(1)
              color: modelData.done ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
            }
          }
        }

        Repeater {
          model: [root.lastDone].concat(root.pending.slice(0, 3)).filter(function(m) { return m })
          Row {
            required property var modelData
            required property int index
            readonly property bool isNext: !modelData.done && root.pending.length > 0 && modelData.id === root.pending[0].id
            spacing: Style.space(8)
            width: column.width
            // Done is muted with an accent check; the next one is accent and bold.
            Line {
              width: root.checkWidth
              text: modelData.done ? "󰄵" : "󰄱"
              color: modelData.done || parent.isNext ? Commons.Color.accent : root.muted
              font.pixelSize: Style.font.body
            }
            Line {
              width: parent.width - root.checkWidth - parent.spacing
              text: modelData.title + (modelData.forced !== null && modelData.forced !== undefined ? "  (override)" : "")
              color: parent.isNext ? Commons.Color.accent : modelData.done ? root.muted : root.fg
              font.bold: parent.isNext
            }
          }
        }
        Line {
          visible: root.pending.length > 3
          leftPadding: root.checkWidth + Style.space(8)
          color: root.muted
          font.pixelSize: Style.font.caption
          text: "+" + (root.pending.length - 3) + " more to go"
        }
        Line {
          readonly property var w: root.campaign ? root.campaign.weather : null
          visible: text !== ""
          width: parent.width
          topPadding: Style.space(4)
          color: root.muted
          font.pixelSize: Style.font.caption
          text: !root.campaign ? "" : root.join([
            w && w.temp_c !== null && w.temp_c !== undefined ? "Starbase " + Math.round(w.temp_c) + "°C" : "",
            w && w.summary ? w.summary : "",
            w && w.wind_kmh !== null && w.wind_kmh !== undefined ? "wind " + Math.round(w.wind_kmh) + " km/h" : "",
            root.campaign.closures.length ? root.campaign.closures.length + " road closure" + (root.campaign.closures.length > 1 ? "s" : "") : "",
            root.campaign.tfrs.length ? root.campaign.tfrs.length + " TFR" + (root.campaign.tfrs.length > 1 ? "s" : "") : ""])
        }
      }

      PanelSeparator { visible: root.later.length > 0; foreground: root.fg }

      // Then: a compact schedule with the date, the launch and a coarse countdown in columns.
      Column {
        visible: root.later.length > 0
        width: column.width
        spacing: Style.space(6)
        PanelSectionHeader { text: "COMING UP"; foreground: root.fg }
        Repeater {
          model: root.later
          Row {
            required property var modelData
            width: column.width
            spacing: Style.space(10)
            Column {
              width: Style.space(54)
              // A launch without a fixed time shows its NET date ("NET" over "17 Dec") instead.
              Line { text: modelData.net !== "" ? "NET" : root.localTime(modelData.t0, "ddd d"); color: root.muted; font.pixelSize: Style.font.caption }
              Line { text: modelData.net !== "" ? modelData.net.replace("NET ", "").replace(/ \d{4}$/, "") : root.localTime(modelData.t0, "HH:mm") }
            }
            Column {
              width: parent.width - Style.space(54) - Style.space(64) - parent.spacing * 2
              Line { width: parent.width; text: (modelData.pinned ? "󰐃 " : "") + modelData.name; font.bold: true }
              Line { width: parent.width; text: root.join([modelData.rocket, modelData.status !== "Go" ? modelData.status : ""]); color: root.muted; font.pixelSize: Style.font.caption }
            }
            Line {
              width: Style.space(64)
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.net === "" ? Countdown.short(Date.parse(modelData.t0), root.now) : ""
              color: root.muted
            }
          }
        }
      }

      PanelSeparator { foreground: root.fg }

      RowLayout {
        width: column.width
        spacing: Style.space(6)
        Button {
          iconText: "󰆏"
          text: "Checklist"
          tooltipText: "Copy the campaign checklist"
          Layout.fillWidth: true
          bordered: true
          fontSize: Style.font.bodySmall
          foreground: root.fg
          enabled: !!root.campaign
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.run(["checklist", "--copy"])
        }
        Button {
          iconText: "󰃭"
          text: "Weekend"
          tooltipText: "Copy launches through Sunday"
          Layout.fillWidth: true
          bordered: true
          fontSize: Style.font.bodySmall
          foreground: root.fg
          enabled: !!root.feed
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.run(["weekend", "--copy"])
        }
        Button {
          iconText: "󱎯"
          text: "Mission Control"
          Layout.fillWidth: true
          bordered: true
          fontSize: Style.font.bodySmall
          foreground: root.fg
          onClicked: { root.popupOpen = false; root.run(["open"]) }
        }
      }
    }
  }
}
