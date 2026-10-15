import QtQuick

Rectangle {
    id: root
    property string text
    property string icon: ""
    property bool primary: false
    property bool danger: false
    property bool enabledState: true
    signal clicked()

    implicitHeight: 38
    implicitWidth: row.implicitWidth + 32
    radius: 10
    opacity: enabledState ? 1 : 0.4
    readonly property color base: danger ? Theme.danger : Theme.accent
    color: primary ? (ma.containsMouse ? Qt.lighter(base, 1.1) : base)
                   : (ma.containsMouse ? Theme.surfaceHover : Theme.surfaceHi)
    border.color: primary ? "transparent" : (danger ? Theme.alpha(Theme.danger, 0.5) : Theme.borderHi)
    Behavior on color { ColorAnimation { duration: 140 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: 16
            color: root.primary ? "#0b0d10" : (root.danger ? Theme.danger : Theme.text)
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            text: root.text
            font.weight: Font.DemiBold
            font.pixelSize: 14
            color: root.primary ? "#0b0d10" : (root.danger ? Theme.danger : Theme.text)
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
