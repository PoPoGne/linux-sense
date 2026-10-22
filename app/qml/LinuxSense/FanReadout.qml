import QtQuick
import QtQuick.Layouts

// animated fan with real speed
Rectangle {
    id: root
    property string label
    property int rpm: 0
    property int maxRpm: 7000
    radius: 14
    color: Theme.bg
    border.color: Theme.border
    implicitHeight: 92

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        Item {
            width: 52; height: 52
            Rectangle {
                anchors.fill: parent
                radius: 26
                color: Theme.alpha(Theme.accent, 0.08)
                border.color: Theme.alpha(Theme.accent, 0.3)
            }
            Icon {
                id: fanIcon
                anchors.centerIn: parent
                name: "fan"
                size: 28
                color: root.rpm > 0 ? Theme.accentRaw : Theme.textMute
                // rotation proportional to real RPM (slowed for readability)
                property real speed: root.rpm / 60 * 360 / 40
                NumberAnimation on rotation {
                    running: root.rpm > 0 && root.visible
                    from: 0; to: 360
                    loops: Animation.Infinite
                    duration: fanIcon.speed > 0 ? 360 / fanIcon.speed * 1000 : 1000
                }
            }
        }
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Caption { text: root.label }
            Row {
                spacing: 6
                Label {
                    id: num
                    text: root.rpm > 0 ? root.rpm.toLocaleString(Qt.locale("it_IT"), "f", 0) : "Ferma"
                    font.family: Theme.display
                    font.weight: Font.Bold
                    font.pixelSize: 30
                }
                Label {
                    visible: root.rpm > 0
                    text: "RPM"
                    color: Theme.textDim
                    font.family: Theme.display
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    anchors.baseline: num.baseline
                }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 4; radius: 2
                color: Theme.surfaceHover
                Rectangle {
                    height: parent.height; radius: 2
                    width: parent.width * Math.min(1, root.rpm / root.maxRpm)
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
