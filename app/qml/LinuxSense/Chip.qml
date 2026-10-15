import QtQuick

// piccola pillola informativa
Rectangle {
    id: root
    property string text
    property string icon: ""
    property color tint: Theme.accent
    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24
    radius: 16
    color: Theme.alpha(tint, 0.10)
    border.color: Theme.alpha(tint, 0.35)
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon { visible: root.icon !== ""; name: root.icon; size: 15; color: root.tint; anchors.verticalCenter: parent.verticalCenter }
        Label { text: root.text; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
    }
}
