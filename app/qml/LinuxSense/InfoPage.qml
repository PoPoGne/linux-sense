import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var st: backend.state
    readonly property var info: backend.info
    readonly property var tm: backend.telemetry

    PageHeader {
        Layout.fillWidth: true
        title: "Informazioni"
        subtitle: "Il tuo portatile e i componenti di Linux Sense"
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            Layout.alignment: Qt.AlignTop
            title: "Dispositivo"
            icon: "monitor-smartphone"
            Repeater {
                model: [
                    { k: "Modello", v: page.st.model || "—" },
                    { k: "BIOS", v: page.st.bios || "—" },
                    { k: "Processore", v: page.info.cpu || "—" },
                    { k: "Grafica", v: (page.info.gpus || []).join("\n") || "—" },
                    { k: "Memoria", v: page.tm.ram_total ? Number(page.tm.ram_total).toFixed(1) + " GB" : "—" },
                    { k: "Sistema", v: page.info.os || "—" },
                    { k: "Kernel", v: page.info.kernel || "—" }
                ]
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: modelData.k; color: Theme.textDim; font.pixelSize: 14; Layout.preferredWidth: 130; Layout.alignment: Qt.AlignTop }
                        Label { text: modelData.v; font.pixelSize: 14; font.weight: Font.Medium; Layout.fillWidth: true; wrapMode: Text.WordWrap; lineHeight: 1.25 }
                    }
                    Rectangle { visible: index < 6; Layout.fillWidth: true; height: 1; color: Theme.border }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            Layout.alignment: Qt.AlignTop
            spacing: 20

            Card {
                Layout.fillWidth: true
                title: "Software"
                icon: "shield-check"
                Repeater {
                    model: [
                        { k: "Linux Sense", v: page.info.app_version || "—" },
                        { k: "Servizio", v: backend.connected ? (page.st.version || "—") + " · attivo" : "non raggiungibile" },
                        { k: "Driver linuwu_sense", v: page.st.driver_version || "—" },
                        { k: "Famiglia", v: page.st.laptop_type === "NITRO" ? "Nitro" : (page.st.laptop_type === "PREDATOR" ? "Predator" : "—") }
                    ]
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: modelData.k; color: Theme.textDim; font.pixelSize: 14; Layout.fillWidth: true }
                        Label { text: modelData.v; font.pixelSize: 14; font.weight: Font.Medium }
                    }
                }
            }
            Card {
                Layout.fillWidth: true
                title: "Riconoscimenti"
                icon: "info"
                Label {
                    Layout.fillWidth: true
                    text: "Linux Sense è software libero con licenza GPL-3.0. Usa il driver Linuwu-Sense (GPL-2.0 o successiva) ed è nato dal progetto DAMX di PXDiv (GPL-3.0). Icone Lucide (ISC), caratteri Rajdhani e Inter (SIL OFL)."
                    color: Theme.textDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }
            }
        }
    }
}
