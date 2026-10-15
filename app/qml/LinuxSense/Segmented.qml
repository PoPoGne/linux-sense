import QtQuick

// controllo segmentato con indicatore scorrevole
Rectangle {
    id: root
    property var options: []          // [{value, label, icon?}]
    property var value
    property bool enabledState: true
    signal picked(var value)

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 8
    radius: 12
    color: Theme.bg
    border.color: Theme.border
    opacity: enabledState ? 1 : 0.45

    readonly property int currentIndex: {
        for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
        return -1
    }

    Rectangle {
        id: pill
        visible: root.currentIndex >= 0
        y: 4
        height: parent.height - 8
        radius: 9
        color: Theme.alpha(Theme.accent, 0.16)
        border.color: Theme.alpha(Theme.accent, 0.55)
        property Item target: root.currentIndex >= 0 ? rep.itemAt(root.currentIndex) : null
        x: target ? target.x + row.x : 0
        width: target ? target.width : 0
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: rep
            model: root.options
            delegate: Item {
                width: Math.max(72, content.implicitWidth + 28)
                height: root.height - 8
                property bool active: index === root.currentIndex
                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 7
                    Icon {
                        visible: !!modelData.icon
                        name: modelData.icon || ""
                        size: 15
                        color: active ? Theme.accentRaw : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: modelData.label
                        font.pixelSize: 13
                        font.weight: active ? Font.DemiBold : Font.Normal
                        color: active ? Theme.text : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.enabledState
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(modelData.value)
                }
            }
        }
    }
}
