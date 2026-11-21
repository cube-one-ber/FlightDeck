import QtQuick

// Renders a monochrome symbolic theme icon tinted to `color` via
// SymbolicIconProvider so Papirus and Breeze icons always honor live themes.
Image {
    id: icon

    property string name: ""
    property color color: theme.fg

    readonly property string encodedColor: encodeURIComponent(Qt.color(icon.color).toString())

    source: name !== "" ? ("image://symbolic/" + name + "?color=" + encodedColor) : ""
    sourceSize.width: Math.max(12, Math.round(width || implicitWidth || 16))
    sourceSize.height: Math.max(12, Math.round(height || implicitHeight || 16))
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: false
}
