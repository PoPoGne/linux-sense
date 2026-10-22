import QtQuick
import QtQuick.Controls.Basic

Slider {
    id: control
    property color accentColor: Theme.accent
    property var trackGradient: null   // optional track gradient
    implicitHeight: 28
    hoverEnabled: true

    background: Item {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: 6
        Rectangle {
            anchors.fill: parent
            radius: 3
            color: Theme.surfaceHover
            gradient: control.trackGradient
        }
        Rectangle {
            visible: control.trackGradient === null
            width: control.visualPosition * parent.width
            height: parent.height
            radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.alpha(control.accentColor, 0.35) }
                GradientStop { position: 1.0; color: control.accentColor }
            }
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 18; height: 18; radius: 9
        color: "#f4f5f8"
        border.width: 3
        border.color: control.trackGradient === null ? control.accentColor : "#0b0d10"
        scale: control.pressed ? 1.15 : (control.hovered ? 1.07 : 1)
        Behavior on scale { NumberAnimation { duration: 120 } }
    }
}
