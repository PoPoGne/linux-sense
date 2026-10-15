import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    default property alias content: inner.data
    property int padding: 22
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property alias headerRight: headerRightSlot.data
    property alias spacing: inner.spacing

    color: Theme.surface
    radius: Theme.radius
    border.color: Theme.border
    border.width: 1
    implicitHeight: col.implicitHeight + padding * 2

    // riflesso sottile in alto
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: 1
        radius: Theme.radius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.padding }
        spacing: 18

        RowLayout {
            visible: card.title !== ""
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                visible: card.icon !== ""
                width: 34; height: 34; radius: 10
                color: Theme.alpha(Theme.accent, 0.12)
                border.color: Theme.alpha(Theme.accent, 0.25)
                Icon { anchors.centerIn: parent; name: card.icon; size: 18; color: Theme.accentRaw }
            }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Label {
                    text: card.title
                    font.family: Theme.display
                    font.weight: Font.Bold
                    font.pixelSize: 19
                    font.letterSpacing: 0.4
                }
                Label {
                    visible: card.subtitle !== ""
                    text: card.subtitle
                    color: Theme.textDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            Item { id: headerRightSlot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
        }

        ColumnLayout {
            id: inner
            Layout.fillWidth: true
            spacing: 14
        }
    }
}
