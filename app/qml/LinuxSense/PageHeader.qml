import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string title
    property string subtitle
    default property alias trailing: slot.data
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 16

        ColumnLayout {
            spacing: 4
            Layout.fillWidth: true
            Label {
                text: root.title
                font.family: Theme.display
                font.weight: Font.Bold
                font.pixelSize: 34
                font.letterSpacing: 0.5
            }
            Label {
                text: root.subtitle
                color: Theme.textDim
                font.pixelSize: 14
            }
        }
        Row { id: slot; spacing: 10; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
    }
}
