import QtQuick
import QtQuick.Layouts

// selectable thermal profile card
Rectangle {
    id: root
    property var profile            // voce di Theme.profiles
    property bool selected: false
    property bool available: true
    property bool compact: false
    signal activated()

    readonly property color tint: profile ? profile.color : Theme.accent
    radius: 14
    implicitHeight: compact ? 64 : 196
    color: selected ? Theme.alpha(tint, 0.09) : (ma.containsMouse && available ? Theme.surfaceHover : Theme.surface)
    border.width: selected ? 1.5 : 1
    border.color: selected ? Theme.alpha(tint, 0.85) : Theme.border
    opacity: available ? 1 : 0.42
    Behavior on color { ColorAnimation { duration: 160 } }

    // glow at the top when selected
    Rectangle {
        visible: root.selected
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: parent.height * 0.6
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(root.tint, 0.16) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // full version
    ColumnLayout {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                width: 46; height: 46; radius: 13
                color: Theme.alpha(root.tint, root.selected ? 0.2 : 0.1)
                border.color: Theme.alpha(root.tint, root.selected ? 0.6 : 0.2)
                Icon { anchors.centerIn: parent; name: root.profile ? root.profile.icon : ""; size: 22; color: root.tint }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: root.selected
                width: 22; height: 22; radius: 11
                color: root.tint
                Icon { anchors.centerIn: parent; name: "check"; size: 14; color: "#0b0d10" }
            }
            Icon { visible: !root.available; name: "plug"; size: 18; color: Theme.textMute }
        }
        Item { Layout.fillHeight: true }
        Label {
            text: root.profile ? root.profile.name : ""
            font.family: Theme.display
            font.weight: Font.Bold
            font.pixelSize: 23
        }
        Label {
            Layout.fillWidth: true
            text: root.available ? (root.profile ? root.profile.desc : "") : "Only available with the power adapter connected."
            color: Theme.textDim
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            lineHeight: 1.15
            Layout.preferredHeight: 48
            verticalAlignment: Text.AlignTop
        }
    }

    // compact version (dashboard)
    RowLayout {
        visible: root.compact
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10
        Icon { name: root.profile ? root.profile.icon : ""; size: 20; color: root.selected ? root.tint : Theme.textDim }
        Label {
            text: root.profile ? root.profile.name : ""
            font.family: Theme.display
            font.weight: Font.Bold
            font.pixelSize: 17
            color: root.selected ? Theme.text : Theme.textDim
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available && !root.selected
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
