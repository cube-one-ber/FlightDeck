import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// GNOME boxed-list / elevated card surface backed by Kirigami.ShadowedRectangle
// so cards respect Omarchy's live palette and Hyprland corner rounding cleanly.
Kirigami.ShadowedRectangle {
    id: card

    property int padding: 0
    property bool accented: false
    default property alias content: body.data

    color: theme.cardBg
    radius: theme.cardRadius
    border.width: 1
    border.color: accented ? Qt.rgba(theme.accentText.r, theme.accentText.g, theme.accentText.b, theme.isDark ? 0.26 : 0.30) : theme.border

    shadow.size: theme.isDark ? 10 : 12
    shadow.yOffset: 2
    shadow.color: theme.isDark ? Qt.rgba(0, 0, 0, 0.24) : Qt.rgba(0, 0, 0, 0.06)

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: card.padding
    }
}
