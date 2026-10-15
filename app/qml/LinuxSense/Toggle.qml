import QtQuick

Item {
    id: root
    property bool checked: false
    property bool enabledState: true
    signal toggled(bool value)
    implicitWidth: 46
    implicitHeight: 26
    opacity: enabledState ? 1 : 0.4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.surfaceHover
        border.color: root.checked ? Theme.accent : Theme.borderHi
        Behavior on color { ColorAnimation { duration: 180 } }

        Rectangle {
            width: 20; height: 20; radius: 10
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? "#0b0d10" : Theme.textDim
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
