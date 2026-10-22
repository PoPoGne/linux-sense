import QtQuick
import QtQuick.Effects

// 4-zone keyboard preview with effect simulation
Item {
    id: root
    property var zones: ["ff2e4d", "ff2e4d", "ff2e4d", "ff2e4d"]
    property string effect: "static"
    property string effectColor: "ff2e4d"
    property int brightness: 100
    property int speed: 3
    property int direction: 1
    property int selectedZone: -1          // highlights one zone (static mode)
    property bool animate: true
    signal zoneClicked(int zone)

    implicitHeight: boardH + 66

    property real phase: 0
    Timer {
        interval: 33
        repeat: true
        running: root.animate && root.visible && root.effect !== "static"
        onTriggered: root.phase += 0.033 * (0.35 + root.speed * 0.22)
    }

    // layout: [width in units] per row; 0.5 = half-height stacked key
    readonly property var rows: [
        { h: 0.62, keys: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1] },
        { h: 1, keys: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2] },
        { h: 1, keys: [1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5] },
        { h: 1, keys: [1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25] },
        { h: 1, keys: [2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.75] },
        { h: 1, keys: [1, 1, 1, 1.25, 5.5, 1.25, 1, 1, "ud", 1] }
    ]
    readonly property var keyList: {
        var list = [], y = 0, idx = 0
        for (var r = 0; r < rows.length; r++) {
            var x = 0, row = rows[r]
            for (var k = 0; k < row.keys.length; k++) {
                var w = row.keys[k]
                if (w === "ud") {
                    list.push({ x: x, y: y + row.h / 2, w: 1, h: row.h / 2, i: idx++, wasd: false })
                    list.push({ x: x, y: y, w: 1, h: row.h / 2, i: idx++, wasd: false })
                    x += 1
                    continue
                }
                // W A S D (transparent keys on the Nitro 14)
                var wasd = (r === 2 && k === 2) || (r === 3 && (k === 1 || k === 2 || k === 3))
                list.push({ x: x, y: y, w: w, h: row.h, i: idx++, wasd: wasd })
                x += w
            }
            y += row.h
        }
        return list
    }
    readonly property real unitsW: 15
    readonly property real unitsH: 5.62
    readonly property real gap: Math.max(3, width * 0.0045)
    readonly property real unit: (width - 40) / unitsW
    readonly property real boardH: unit * unitsH

    function hexColor(h) { return Qt.color("#" + h) }
    function rainbow(h) { h = h - Math.floor(h); return Qt.hsva(h, 0.95, 1, 1) }
    function hash(n) { var s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s) }

    // returns [color, intensity 0..1] for one key
    function keyLight(fx, fy, idx) {
        var t = phase, dir = direction === 2 ? -1 : 1
        var base = hexColor(effectColor)
        switch (effect) {
        case "static":
            return [hexColor(zones[Math.min(3, Math.floor(fx * 4))]), 1]
        case "breathing":
            return [base, 0.12 + 0.88 * (0.5 + 0.5 * Math.sin(t * 2.4))]
        case "neon":
            return [rainbow(t * 0.18), 1]
        case "wave":
            return [rainbow(fx * 0.9 - t * 0.35 * dir), 1]
        case "shifting": {
            var p = (t * 0.45 * dir) % 1; if (p < 0) p += 1
            var d = Math.abs(fx - p); d = Math.min(d, 1 - d)
            return [base, Math.max(0.12, 1 - d * 3.2)]
        }
        case "zoom": {
            var z = (t * 0.6) % 1
            var dist = Math.abs(fx - 0.5) * 2
            return [base, Math.max(0.1, 1 - Math.abs(dist - z) * 4)]
        }
        case "meteor": {
            var m = (t * 0.55 * dir) % 1.4; if (m < 0) m += 1.4
            var dm = (m - 0.2) - fx
            var tail = dir > 0 ? dm : -dm
            return [base, tail >= 0 && tail < 0.35 ? 1 - tail / 0.35 : 0.08]
        }
        case "twinkling":
            return [base, hash(idx + Math.floor(t * 3) * 97) > 0.72 ? 1 : 0.1]
        }
        return [base, 1]
    }

    // glow under the keyboard
    Item {
        id: glowSrc
        anchors.fill: board
        visible: false
        Row {
            anchors.fill: parent
            anchors.margins: parent.height * 0.12
            Repeater {
                model: 4
                Rectangle {
                    width: parent.width / 4
                    height: parent.height
                    color: {
                        var l = root.keyLight((index + 0.5) / 4, 0.5, index * 17)
                        return Qt.rgba(l[0].r, l[0].g, l[0].b, l[1] * root.brightness / 100)
                    }
                }
            }
        }
    }
    MultiEffect {
        anchors.fill: glowSrc
        anchors.margins: -40
        source: glowSrc
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        opacity: 0.75
    }

    // chassis
    Rectangle {
        id: board
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        width: root.width - 20
        height: root.boardH + 20
        radius: 14
        color: "#08090c"
        border.color: Theme.border

        Repeater {
            model: root.keyList
            delegate: Rectangle {
                id: key
                readonly property real fx: (modelData.x + modelData.w / 2) / root.unitsW
                readonly property real fy: (modelData.y + modelData.h / 2) / root.unitsH
                readonly property int zone: Math.min(3, Math.floor(fx * 4))
                readonly property var light: root.keyLight(fx, fy, modelData.i)
                readonly property real lit: light[1] * root.brightness / 100
                readonly property bool dimmed: root.selectedZone >= 0 && zone !== root.selectedZone && root.effect === "static"

                x: 10 + modelData.x * root.unit + root.gap / 2
                y: 10 + modelData.y * root.unit + root.gap / 2
                width: modelData.w * root.unit - root.gap
                height: modelData.h * root.unit - root.gap
                radius: Math.max(3, root.unit * 0.12)
                color: Theme.mix(Qt.color("#13151a"), light[0], (modelData.wasd ? 0.16 : 0.03) + 0.11 * lit)
                border.width: 1
                border.color: Qt.rgba(light[0].r, light[0].g, light[0].b, (0.12 + 0.75 * lit) * (dimmed ? 0.35 : 1))
                opacity: dimmed ? 0.55 : 1

                // key light mark
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.32, root.unit * 0.3)
                    height: 2
                    radius: 1
                    color: key.light[0]
                    opacity: 0.25 + 0.75 * key.lit
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.effect === "static"
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: (m) => root.zoneClicked(Math.min(3, Math.floor((m.x - 10) / (root.unit * root.unitsW) * 4)))
        }
    }

    // zone labels
    Row {
        anchors.top: board.bottom
        anchors.topMargin: 10
        x: board.x + 10
        visible: root.effect === "static"
        Repeater {
            model: 4
            Item {
                width: root.unit * root.unitsW / 4
                height: 20
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6 }
                    height: 2
                    radius: 1
                    color: index === root.selectedZone ? Theme.accent : Theme.borderHi
                }
                Caption {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 7
                    text: tr.fmt("Zone {zone}", {"zone": index + 1})
                    color: index === root.selectedZone ? Theme.text : Theme.textMute
                }
            }
        }
    }
}
