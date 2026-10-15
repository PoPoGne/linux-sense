import QtQuick

Item {
    id: root
    property string icon
    property string text
    property bool active: false
    signal clicked()
    implicitHeight: 46
    width: parent ? parent.width : 200

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.active ? Theme.surfaceHi : (ma.containsMouse ? Theme.alpha(Theme.surfaceHi, 0.6) : "transparent")
        border.color: root.active ? Theme.border : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
    }
    Rectangle {
        width: 3; height: root.active ? 20 : 0
        radius: 2
        anchors.verticalCenter: parent.verticalCenter
        x: -1
        color: Theme.accent
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        spacing: 13
        Icon {
            name: root.icon
            size: 19
            color: root.active ? Theme.accentRaw : Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            text: root.text
            font.pixelSize: 14
            font.weight: root.active ? Font.DemiBold : Font.Medium
            color: root.active ? Theme.text : Theme.textDim
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
