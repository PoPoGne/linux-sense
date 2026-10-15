import QtQuick
import QtQuick.Layouts

// riga impostazione: icona, titolo, descrizione, controllo a destra
RowLayout {
    id: root
    property string icon: ""
    property string title
    property string description: ""
    default property alias control: slot.data
    spacing: 16

    Rectangle {
        visible: root.icon !== ""
        Layout.alignment: Qt.AlignTop
        width: 38; height: 38; radius: 11
        color: Theme.surfaceHi
        border.color: Theme.border
        Icon { anchors.centerIn: parent; name: root.icon; size: 18; color: Theme.textDim }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Label { text: root.title; font.pixelSize: 15; font.weight: Font.DemiBold }
        Label {
            visible: root.description !== ""
            text: root.description
            color: Theme.textDim
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            Layout.fillWidth: true
        }
    }
    Item {
        id: slot
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
