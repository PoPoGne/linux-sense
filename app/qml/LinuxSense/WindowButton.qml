import QtQuick

Rectangle {
    id: root
    property string icon
    property bool danger: false
    signal clicked()
    width: 40; height: 32; radius: 8
    color: ma.containsMouse ? (danger ? "#e5384f" : Theme.surfaceHover) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: 16
        color: ma.containsMouse && root.danger ? "#ffffff" : Theme.textDim
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}
