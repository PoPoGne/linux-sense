import QtQuick
import QtQuick.Shapes

// indicatore ad arco 270°
Item {
    id: root
    property real value: 0
    property real from: 0
    property real to: 100
    property string valueText: Math.round(value).toString()
    property string unit: ""
    property string label: ""
    property string sublabel: ""
    property color color: Theme.accent
    property bool active: true
    property real thickness: 9

    implicitWidth: 168
    implicitHeight: 168

    readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))
    property real shown: active ? frac : 0
    Behavior on shown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    readonly property real r: Math.min(width, height) / 2 - thickness

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // traccia
        ShapePath {
            strokeColor: Theme.surfaceHover
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.r; radiusY: root.r
                startAngle: 135; sweepAngle: 270
            }
        }
        // valore
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.r; radiusY: root.r
                startAngle: 135; sweepAngle: Math.max(0.01, 270 * root.shown)
            }
        }
    }

    // tacche
    Repeater {
        model: 28
        Rectangle {
            readonly property real ang: (135 + 270 * index / 27) * Math.PI / 180
            readonly property real rr: root.r - root.thickness - 6
            x: root.width / 2 + Math.cos(ang) * rr - width / 2
            y: root.height / 2 + Math.sin(ang) * rr - height / 2
            width: 2; height: 2; radius: 1
            color: index / 27 <= root.shown ? Theme.alpha(root.color, 0.8) : Theme.borderHi
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 4
        spacing: -2
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Label {
                id: valueLabel
                text: root.active ? root.valueText : "—"
                font.family: Theme.display
                font.weight: Font.Bold
                font.pixelSize: 38
            }
            Label {
                visible: root.active && root.unit !== ""
                text: root.unit
                color: Theme.textDim
                font.family: Theme.display
                font.weight: Font.DemiBold
                font.pixelSize: 16
                anchors.baseline: valueLabel.baseline
            }
        }
        Caption {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.textDim
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: root.sublabel
        color: Theme.textMute
        font.pixelSize: 11
    }
}
