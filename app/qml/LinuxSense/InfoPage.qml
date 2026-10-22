import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var st: backend.state
    readonly property var info: backend.info
    readonly property var tm: backend.telemetry

    PageHeader {
        Layout.fillWidth: true
        title: "About"
        subtitle: "Your laptop and the Linux Sense components"
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            Layout.alignment: Qt.AlignTop
            title: "Device"
            icon: "monitor-smartphone"
            Repeater {
                model: [
                    { k: "Model", v: page.st.model || "—" },
                    { k: "BIOS", v: page.st.bios || "—" },
                    { k: "Processor", v: page.info.cpu || "—" },
                    { k: "Graphics", v: (page.info.gpus || []).join("\n") || "—" },
                    { k: "Memory", v: page.tm.ram_total ? Number(page.tm.ram_total).toFixed(1) + " GB" : "—" },
                    { k: "System", v: page.info.os || "—" },
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
                        { k: "Service", v: backend.connected ? (page.st.version || "—") + " · running" : "unreachable" },
                        { k: "Driver linuwu_sense", v: page.st.driver_version || "—" },
                        { k: "Family", v: page.st.laptop_type === "NITRO" ? "Nitro" : (page.st.laptop_type === "PREDATOR" ? "Predator" : "—") }
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
                title: "Credits"
                icon: "info"
                Label {
                    Layout.fillWidth: true
                    text: "Linux Sense is free software under the GPL-3.0 license. It uses the Linuwu-Sense driver (GPL-2.0 or later) and started from the DAMX project by PXDiv (GPL-3.0). Lucide icons (ISC), Rajdhani and Inter fonts (SIL OFL)."
                    color: Theme.textDim
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }
            }
        }
    }
}
