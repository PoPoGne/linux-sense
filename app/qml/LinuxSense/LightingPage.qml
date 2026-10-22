import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var remote: backend.state.keyboard || null

    // local editable copy: realigns with the daemon when you are not editing
    property var kb: ({ effect: "static", zones: ["ff2e4d", "ff2e4d", "ff2e4d", "ff2e4d"],
                        brightness: 75, speed: 3, direction: 1, color: "ff2e4d" })
    property bool dirty: false
    property int zone: -1              // -1 = all zones
    property int lastBrightness: 75

    onRemoteChanged: if (remote && !dirty) kb = JSON.parse(JSON.stringify(remote))
    Component.onCompleted: if (remote) kb = JSON.parse(JSON.stringify(remote))

    Timer {
        id: sendTimer
        interval: 140
        onTriggered: { backend.setKeyboard(page.kb); settle.restart() }
    }
    Timer { id: settle; interval: 1500; onTriggered: page.dirty = false }

    function change(changes) {
        var n = JSON.parse(JSON.stringify(kb))
        for (var k in changes) n[k] = changes[k]
        if (n.brightness > 0) lastBrightness = n.brightness
        kb = n
        dirty = true
        sendTimer.restart()
    }

    readonly property var effects: [
        { id: "static", name: "Static", icon: "square", color: false, dir: false, speed: false },
        { id: "breathing", name: "Breathing", icon: "activity", color: true, dir: false, speed: true },
        { id: "neon", name: "Neon", icon: "palette", color: false, dir: false, speed: true },
        { id: "wave", name: "Wave", icon: "waves", color: false, dir: true, speed: true },
        { id: "shifting", name: "Shifting", icon: "arrow-left-right", color: true, dir: true, speed: true },
        { id: "zoom", name: "Zoom", icon: "circle-gauge", color: true, dir: false, speed: true },
        { id: "meteor", name: "Meteor", icon: "zap", color: true, dir: true, speed: true },
        { id: "twinkling", name: "Twinkling", icon: "sparkles", color: true, dir: false, speed: true }
    ]
    function effectInfo(id) {
        for (var i = 0; i < effects.length; i++) if (effects[i].id === id) return effects[i]
        return effects[0]
    }
    readonly property var fx: effectInfo(kb.effect)
    readonly property bool usesColor: kb.effect === "static" || fx.color
    readonly property string currentColor: kb.effect === "static"
        ? kb.zones[zone >= 0 ? zone : 0] : kb.color

    function setColor(hex) {
        hex = hex.toLowerCase()
        if (kb.effect === "static") {
            var z = kb.zones.slice()
            if (zone >= 0) z[zone] = hex
            else z = [hex, hex, hex, hex]
            change({ zones: z })
        } else {
            change({ color: hex })
        }
    }

    readonly property var swatches: ["ff2e4d", "ff6a2b", "ffb020", "f5e642", "2fe39b", "22d3ee",
                                    "3b82f6", "7c5cff", "d946ef", "ff4fa3", "ffffff"]

    PageHeader {
        Layout.fillWidth: true
        title: "Lighting"
        subtitle: "4-zone RGB keyboard"
        Row {
            spacing: 12
            Label {
                text: page.kb.brightness > 0 ? "On" : "Off"
                color: Theme.textDim
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: page.kb.brightness > 0
                onToggled: (v) => page.change({ brightness: v ? Math.max(10, page.lastBrightness) : 0 })
            }
        }
    }

    Card {
        Layout.fillWidth: true
        padding: 24
        KeyboardPreview {
            Layout.fillWidth: true
            zones: page.kb.zones
            effect: page.kb.effect
            effectColor: page.kb.color
            brightness: Math.max(page.kb.brightness, 0)
            speed: page.kb.speed
            direction: page.kb.direction
            selectedZone: page.zone
            onZoneClicked: (z) => page.zone = (page.zone === z ? -1 : z)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            title: "Effect"
            subtitle: page.fx.id === "static" ? "A fixed color for each zone." : "Animation handled by the keyboard."
            icon: "sparkles"
            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 10
                columnSpacing: 10
                Repeater {
                    model: page.effects
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 76
                        radius: 12
                        readonly property bool active: page.kb.effect === modelData.id
                        color: active ? Theme.alpha(Theme.accent, 0.12) : (ema.containsMouse ? Theme.surfaceHover : Theme.bg)
                        border.color: active ? Theme.alpha(Theme.accent, 0.7) : Theme.border
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: modelData.icon; size: 20
                                color: parent.parent.active ? Theme.accentRaw : Theme.textDim
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.pixelSize: 12
                                font.weight: parent.parent.active ? Font.DemiBold : Font.Normal
                                color: parent.parent.active ? Theme.text : Theme.textDim
                            }
                        }
                        MouseArea {
                            id: ema
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.change({ effect: modelData.id })
                        }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            title: "Color"
            subtitle: !page.usesColor ? "This effect uses the whole color spectrum."
                      : page.kb.effect === "static"
                        ? (page.zone >= 0 ? "You are editing zone " + (page.zone + 1) + ". Click the keyboard to change it."
                                          : "You are editing all zones. Click a zone to select it.")
                        : "Effect color."
            icon: "palette"

            // zone selector
            RowLayout {
                visible: page.kb.effect === "static"
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [-1, 0, 1, 2, 3]
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        readonly property bool active: page.zone === modelData
                        color: active ? Theme.surfaceHover : Theme.bg
                        border.color: active ? Theme.alpha(Theme.accent, 0.7) : Theme.border
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                visible: modelData >= 0
                                width: 12; height: 12; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData >= 0 ? "#" + page.kb.zones[modelData] : "transparent"
                            }
                            Label {
                                text: modelData < 0 ? "All" : "Zone " + (modelData + 1)
                                font.pixelSize: 12
                                color: parent.parent.active ? Theme.text : Theme.textDim
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.zone = modelData }
                    }
                }
            }

            // palette
            Flow {
                Layout.fillWidth: true
                spacing: 8
                opacity: page.usesColor ? 1 : 0.35
                enabled: page.usesColor
                Repeater {
                    model: page.swatches
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: "#" + modelData
                        border.width: page.currentColor === modelData ? 3 : 1
                        border.color: page.currentColor === modelData ? Theme.text : Qt.rgba(1, 1, 1, 0.12)
                        scale: sma.containsMouse ? 1.1 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: page.setColor(modelData) }
                    }
                }
            }

            // hue + hex
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                opacity: page.usesColor ? 1 : 0.35
                enabled: page.usesColor
                Rectangle {
                    width: 40; height: 40; radius: 10
                    color: "#" + page.currentColor
                    border.color: Qt.rgba(1, 1, 1, 0.15)
                }
                LsSlider {
                    id: hue
                    Layout.fillWidth: true
                    from: 0; to: 1
                    value: Qt.color("#" + page.currentColor).hsvHue < 0 ? 0 : Qt.color("#" + page.currentColor).hsvHue
                    trackGradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#ff0000" }
                        GradientStop { position: 0.17; color: "#ffff00" }
                        GradientStop { position: 0.33; color: "#00ff00" }
                        GradientStop { position: 0.50; color: "#00ffff" }
                        GradientStop { position: 0.67; color: "#0000ff" }
                        GradientStop { position: 0.83; color: "#ff00ff" }
                        GradientStop { position: 1.00; color: "#ff0000" }
                    }
                    onMoved: page.setColor(Theme.hex(Qt.hsva(value, 1, 1, 1)))
                }
                Rectangle {
                    width: 104; height: 40; radius: 10
                    color: Theme.bg
                    border.color: hexField.activeFocus ? Theme.alpha(Theme.accent, 0.7) : Theme.border
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        Label { text: "#"; color: Theme.textMute; font.family: "JetBrains Mono"; font.pixelSize: 13 }
                        TextInput {
                            id: hexField
                            width: 64
                            text: page.currentColor.toUpperCase()
                            color: Theme.text
                            font.family: "JetBrains Mono"
                            font.pixelSize: 13
                            maximumLength: 6
                            selectByMouse: true
                            validator: RegularExpressionValidator { regularExpression: /[0-9a-fA-F]{0,6}/ }
                            onEditingFinished: if (text.length === 6) page.setColor(text)
                        }
                    }
                }
            }
        }
    }

    Card {
        Layout.fillWidth: true
        title: "Adjustments"
        icon: "sliders-horizontal"
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 32
            rowSpacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    Icon { name: "sun"; size: 16; color: Theme.textDim }
                    Label { text: "Brightness"; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
                    Label { text: page.kb.brightness + "%"; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 18 }
                }
                LsSlider {
                    Layout.fillWidth: true
                    from: 0; to: 100; stepSize: 5
                    value: page.kb.brightness
                    onMoved: page.change({ brightness: Math.round(value) })
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                opacity: page.fx.speed ? 1 : 0.35
                enabled: page.fx.speed
                RowLayout {
                    Layout.fillWidth: true
                    Icon { name: "gauge"; size: 16; color: Theme.textDim }
                    Label { text: "Speed"; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
                    Label { text: page.kb.speed; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 18 }
                }
                LsSlider {
                    Layout.fillWidth: true
                    from: 0; to: 9; stepSize: 1
                    value: page.kb.speed
                    onMoved: page.change({ speed: Math.round(value) })
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 8
                opacity: page.fx.dir ? 1 : 0.35
                RowLayout {
                    Icon { name: "arrow-left-right"; size: 16; color: Theme.textDim }
                    Label { text: "Direction"; color: Theme.textDim; font.pixelSize: 13 }
                }
                Segmented {
                    enabledState: page.fx.dir
                    value: page.kb.direction
                    options: [
                        { value: 1, label: "Rightward" },
                        { value: 2, label: "Leftward" }
                    ]
                    onPicked: (v) => page.change({ direction: v })
                }
            }
        }
    }
}
