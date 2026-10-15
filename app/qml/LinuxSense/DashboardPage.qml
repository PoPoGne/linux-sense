import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var st: backend.state
    readonly property var tm: backend.telemetry
    readonly property var prof: st.profile || {}
    readonly property var bat: tm.battery || {}
    signal navigate(int index)

    function fmt(v, d) { return v === undefined || v === null ? "—" : Number(v).toFixed(d) }

    PageHeader {
        Layout.fillWidth: true
        title: "Panoramica"
        subtitle: (page.st.model || "Acer") + " · stato del sistema in tempo reale"
        Chip {
            icon: page.st.ac ? "plug" : "battery"
            text: page.st.ac ? "Alimentatore" : "Batteria " + (page.bat.percent !== undefined ? page.bat.percent + "%" : "")
            tint: Theme.textDim
        }
        Chip { icon: Theme.profileInfo(page.prof.current).icon; text: Theme.profileInfo(page.prof.current).name; tint: Theme.accentRaw }
    }

    // indicatori principali
    Card {
        Layout.fillWidth: true
        padding: 26
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Item { Layout.fillWidth: true; implicitHeight: g1.implicitHeight
                Gauge { id: g1; anchors.centerIn: parent; label: "CPU"; unit: "°C"
                    value: page.tm.cpu_temp || 0; from: 30; to: 100; active: page.tm.cpu_temp !== undefined
                    sublabel: page.tm.cpu_usage !== undefined && page.tm.cpu_usage !== null ? "Carico " + Math.round(page.tm.cpu_usage) + "%" : ""
                    color: (page.tm.cpu_temp || 0) > 88 ? Theme.danger : Theme.accent }
            }
            Item { Layout.fillWidth: true; implicitHeight: g2.implicitHeight
                Gauge { id: g2; anchors.centerIn: parent; label: "GPU"; unit: "°C"
                    value: page.tm.dgpu_temp || 0; from: 30; to: 95; active: !!page.tm.dgpu_active && page.tm.dgpu_temp !== undefined && page.tm.dgpu_temp !== null
                    sublabel: page.tm.dgpu_active ? "Carico " + Math.round(page.tm.dgpu_util || 0) + "%" : "RTX in sospensione"
                    color: (page.tm.dgpu_temp || 0) > 85 ? Theme.danger : Theme.accent }
            }
            Item { Layout.fillWidth: true; implicitHeight: g3.implicitHeight
                Gauge { id: g3; anchors.centerIn: parent; label: "Ventola CPU"; unit: ""
                    value: page.tm.fan_cpu || 0; from: 0; to: 7000
                    valueText: (page.tm.fan_cpu || 0) > 0 ? (page.tm.fan_cpu / 1000).toFixed(1) + "k" : "0"
                    sublabel: "giri al minuto" }
            }
            Item { Layout.fillWidth: true; implicitHeight: g4.implicitHeight
                Gauge { id: g4; anchors.centerIn: parent; label: "Ventola GPU"; unit: ""
                    value: page.tm.fan_gpu || 0; from: 0; to: 7000
                    valueText: (page.tm.fan_gpu || 0) > 0 ? (page.tm.fan_gpu / 1000).toFixed(1) + "k" : "0"
                    sublabel: "giri al minuto" }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        // profilo rapido
        Card {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            title: "Profilo"
            subtitle: "Cambio rapido"
            icon: "gauge"
            Repeater {
                model: Theme.profiles
                ProfileCard {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    compact: true
                    profile: modelData
                    selected: page.prof.current === modelData.id
                    available: (page.prof.available || []).indexOf(modelData.id) >= 0
                    onActivated: backend.setProfile(modelData.id)
                }
            }
        }

        // storico temperature
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "Temperature"
            subtitle: "Ultimi 90 secondi"
            icon: "thermometer"
            headerRight: Row {
                spacing: 16
                Row { spacing: 6
                    Rectangle { width: 10; height: 3; radius: 2; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: "CPU " + page.fmt(page.tm.cpu_temp, 0) + "°"; color: Theme.textDim; font.pixelSize: 12 } }
                Row { spacing: 6
                    Rectangle { width: 10; height: 3; radius: 2; color: "#c9ced8"; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: (page.tm.dgpu_active ? "RTX " + page.fmt(page.tm.dgpu_temp, 0) : "Radeon " + page.fmt(page.tm.igpu_temp, 0)) + "°"
                            color: Theme.textDim; font.pixelSize: 12 } }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 200
                Sparkline {
                    anchors.fill: parent
                    anchors.leftMargin: 34
                    minValue: 30; maxValue: 100
                    series: [
                        { data: page.tm.gpu_hist || [], color: Qt.color("#c9ced8") },
                        { data: page.tm.cpu_hist || [], color: Theme.accentRaw }
                    ]
                }
                Repeater {
                    model: [100, 82, 65, 47, 30]
                    Label {
                        y: index * (parent.height / 4) - height / 2
                        text: modelData + "°"
                        color: Theme.textMute
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    Card {
        Layout.fillWidth: true
        title: "Risorse"
        subtitle: page.tm.cpu_freq ? "Frequenza media CPU " + page.fmt(page.tm.cpu_freq, 2) + " GHz" : ""
        icon: "activity"
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 36
            rowSpacing: 20
            StatBar { Layout.fillWidth: true; icon: "cpu"; label: "Processore"
                valueText: page.fmt(page.tm.cpu_usage, 0) + "%"; fraction: (page.tm.cpu_usage || 0) / 100 }
            StatBar { Layout.fillWidth: true; icon: "memory-stick"; label: "Memoria"
                valueText: page.fmt(page.tm.ram_used, 1) + " / " + page.fmt(page.tm.ram_total, 0) + " GB"
                fraction: page.tm.ram_total ? page.tm.ram_used / page.tm.ram_total : 0 }
            StatBar { Layout.fillWidth: true; icon: "monitor-smartphone"; label: "Grafica integrata Radeon 780M"
                valueText: page.fmt(page.tm.igpu_busy, 0) + "%"; fraction: (page.tm.igpu_busy || 0) / 100 }
            StatBar { Layout.fillWidth: true; icon: page.st.ac ? "battery-charging" : "battery"
                label: page.bat.status === "Charging" ? "Batteria · in carica" : (page.st.ac ? "Batteria · alimentatore collegato" : "Batteria · consumo " + page.fmt(page.bat.power, 1) + " W")
                valueText: page.fmt(page.bat.percent, 0) + "%"; fraction: (page.bat.percent || 0) / 100
                color: (page.bat.percent || 0) < 20 ? Theme.danger : Theme.accent }
        }
    }
}
