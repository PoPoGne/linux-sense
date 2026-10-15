import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var st: backend.state
    readonly property var b: (backend.telemetry || {}).battery || {}
    readonly property var feat: st.battery || {}
    readonly property int pct: b.percent || 0
    readonly property color levelColor: pct <= 15 ? Theme.danger : (pct <= 35 ? Theme.warning : Theme.success)
    property bool confirmCalibration: false

    function fmt(v, d, suffix) { return v === undefined || v === null ? "—" : Number(v).toFixed(d) + (suffix || "") }
    function duration(h) {
        if (h === undefined || h === null || h <= 0 || h > 48) return "—"
        var m = Math.round(h * 60)
        return Math.floor(m / 60) + " h " + (m % 60 < 10 ? "0" : "") + (m % 60) + " min"
    }
    readonly property string statusText: ({ "Charging": "In carica", "Discharging": "In uso a batteria",
                                            "Full": "Carica completa", "Not charging": "Collegata, non in carica" })[b.status] || "Sconosciuto"

    PageHeader {
        Layout.fillWidth: true
        title: "Batteria"
        subtitle: "Stato, salute e protezione della batteria"
        Chip { icon: b.status === "Charging" ? "battery-charging" : (page.st.ac ? "plug" : "battery"); text: page.statusText; tint: page.levelColor }
    }

    Card {
        Layout.fillWidth: true
        padding: 28
        RowLayout {
            Layout.fillWidth: true
            spacing: 40

            // batteria grafica
            ColumnLayout {
                spacing: 16
                Item {
                    width: 250; height: 112
                    Rectangle {
                        id: shell
                        width: 236; height: 112; radius: 20
                        color: Theme.bg
                        border.color: Theme.borderHi
                        border.width: 2
                        Rectangle {
                            x: 8; y: 8
                            height: parent.height - 16
                            width: Math.max(10, (parent.width - 16) * page.pct / 100)
                            radius: 13
                            Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Theme.alpha(page.levelColor, 0.55) }
                                GradientStop { position: 1.0; color: page.levelColor }
                            }
                            // riflesso
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                                height: parent.height * 0.3
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.12)
                            }
                        }
                        Icon {
                            visible: page.b.status === "Charging"
                            anchors.centerIn: parent
                            name: "zap"; size: 40; color: "#ffffff"
                            SequentialAnimation on opacity {
                                running: page.b.status === "Charging"
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.35; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Rectangle { x: 238; y: 38; width: 10; height: 36; radius: 4; color: Theme.borderHi }
                }
                Row {
                    spacing: 4
                    Label { id: big; text: page.pct; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 64 }
                    Label { text: "%"; color: Theme.textDim; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 26; anchors.baseline: big.baseline }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 26
                columnSpacing: 20
                Repeater {
                    model: [
                        { icon: "activity", label: "Stato", value: page.statusText },
                        { icon: "zap", label: page.b.status === "Charging" ? "Potenza in ingresso" : "Consumo attuale",
                          value: page.fmt(page.b.power, 1, " W") },
                        { icon: "rotate-ccw", label: page.b.status === "Charging" ? "Carica completa tra" : "Autonomia stimata",
                          value: page.duration(page.b.hours) },
                        { icon: "shield-check", label: "Salute", value: page.fmt(page.b.health, 0, "%") },
                        { icon: "battery-full", label: "Capacità attuale", value: page.fmt(page.b.energy_full, 1, " Wh") + "  /  " + page.fmt(page.b.energy_design, 0, " Wh") },
                        { icon: "rotate-ccw", label: "Cicli di carica", value: page.b.cycles !== undefined && page.b.cycles !== null && page.b.cycles > 0 ? page.b.cycles : "—" }
                    ]
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        RowLayout {
                            spacing: 7
                            Icon { name: modelData.icon; size: 14; color: Theme.textMute }
                            Caption { text: modelData.label }
                        }
                        Label { text: modelData.value; font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 22 }
                    }
                }
            }
        }
    }

    Card {
        Layout.fillWidth: true
        title: "Protezione"
        icon: "shield-check"
        spacing: 22

        SettingRow {
            visible: page.feat.battery_limiter !== undefined
            Layout.fillWidth: true
            icon: "battery-charging"
            title: "Limita la carica all'80%"
            description: "Ferma la ricarica all'80% per rallentare l'usura. Consigliato se il portatile resta spesso collegato alla corrente."
            Toggle {
                checked: page.feat.battery_limiter === 1
                onToggled: (v) => backend.setBatteryLimiter(v)
            }
        }
        Rectangle { visible: page.feat.usb_charging !== undefined; Layout.fillWidth: true; height: 1; color: Theme.border }
        SettingRow {
            visible: page.feat.usb_charging !== undefined
            Layout.fillWidth: true
            icon: "usb"
            title: "Ricarica USB a portatile spento"
            description: "Le porte USB continuano a ricaricare i dispositivi a PC spento, finché la batteria non scende alla soglia scelta."
            Segmented {
                value: page.feat.usb_charging
                options: [
                    { value: 0, label: "No" },
                    { value: 10, label: "10%" },
                    { value: 20, label: "20%" },
                    { value: 30, label: "30%" }
                ]
                onPicked: (v) => backend.setUsbCharging(v)
            }
        }
    }

    Card {
        visible: page.feat.battery_calibration !== undefined
        Layout.fillWidth: true
        title: "Calibrazione"
        subtitle: "Ricalibra l'indicatore di carica quando la percentuale non è affidabile."
        icon: "gauge"

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Label {
                Layout.fillWidth: true
                text: page.feat.battery_calibration === 1
                      ? "Calibrazione in corso. Tieni l'alimentatore collegato: la batteria verrà caricata, scaricata completamente e ricaricata."
                      : page.confirmCalibration
                        ? "Serve l'alimentatore collegato e richiede alcune ore. La batteria verrà portata al 100%, scaricata fino a 0% e ricaricata. Confermi?"
                        : "Da eseguire raramente, al massimo una volta ogni qualche mese."
                color: page.feat.battery_calibration === 1 || page.confirmCalibration ? Theme.text : Theme.textDim
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.2
            }
            LsButton {
                visible: page.feat.battery_calibration !== 1 && !page.confirmCalibration
                text: "Avvia calibrazione"
                icon: "rotate-ccw"
                enabledState: !!page.st.ac
                onClicked: page.confirmCalibration = true
            }
            LsButton {
                visible: page.confirmCalibration && page.feat.battery_calibration !== 1
                text: "Annulla"
                onClicked: page.confirmCalibration = false
            }
            LsButton {
                visible: page.confirmCalibration && page.feat.battery_calibration !== 1
                text: "Avvia"
                primary: true
                onClicked: { backend.setBatteryCalibration(true); page.confirmCalibration = false }
            }
            LsButton {
                visible: page.feat.battery_calibration === 1
                text: "Interrompi"
                danger: true
                onClicked: backend.setBatteryCalibration(false)
            }
        }
    }
}
