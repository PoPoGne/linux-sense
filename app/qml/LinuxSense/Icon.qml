import QtQuick

Item {
    id: root
    property string name
    property color color: Theme.text
    property int size: 20
    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        anchors.fill: parent
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        source: root.name ? Theme.icon(root.name, root.color) : ""
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
    }
}
