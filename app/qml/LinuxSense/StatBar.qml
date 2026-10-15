import QtQuick
import QtQuick.Layouts

// riga etichetta + valore + barra
ColumnLayout {
    id: root
    property string icon: ""
    property string label
    property string valueText
    property real fraction: 0
    property color color: Theme.accent
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 9
        Icon { visible: root.icon !== ""; name: root.icon; size: 16; color: Theme.textDim }
        Label { text: root.label; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
        Label { text: root.valueText; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 17 }
    }
    Rectangle {
        Layout.fillWidth: true
        height: 5
        radius: 3
        color: Theme.surfaceHover
        Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.max(0, Math.min(1, root.fraction))
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.alpha(root.color, 0.45) }
                GradientStop { position: 1.0; color: root.color }
            }
        }
    }
}
