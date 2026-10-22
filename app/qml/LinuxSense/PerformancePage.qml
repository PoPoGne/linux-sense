import QtQuick
import QtQuick.Layouts

ScrollPage {
    id: page
    readonly property var st: backend.state
    readonly property var tm: backend.telemetry
    readonly property var prof: st.profile || {}
    readonly property var fan: st.fan || {}

    // local slider values (sent after a short delay)
    property int cpuPct: 50
    property int gpuPct: 50
    property bool editing: false
    onFanChanged: if (!editing) { cpuPct = fan.cpu || 50; gpuPct = fan.gpu || 50 }
    Timer {
        id: fanDebounce
        interval: 250
        onTriggered: { backend.setFan("custom", page.cpuPct, page.gpuPct); releaseEdit.restart() }
    }
    Timer { id: releaseEdit; interval: 1500; onTriggered: page.editing = false }

    PageHeader {
        Layout.fillWidth: true
        title: tr.t("Performance")
        subtitle: tr.t("Thermal profiles and fan control")
        Chip {
            icon: page.st.ac ? "plug" : "battery"
            text: page.st.ac ? tr.t("Power adapter connected") : tr.t("On battery")
            tint: Theme.textDim
        }
    }

    // battery warning
    Rectangle {
        visible: page.st.ac === false
        Layout.fillWidth: true
        implicitHeight: 52
        radius: 12
        color: Theme.alpha(Theme.warning, 0.07)
        border.color: Theme.alpha(Theme.warning, 0.3)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            Icon { name: "info"; size: 18; color: Theme.warning }
            Label {
                Layout.fillWidth: true
                text: tr.t("On battery the Acer firmware only allows Eco and Balanced. Connect the power adapter for Quiet, Performance and Turbo.")
                color: Theme.textDim
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }
    }

    Caption { text: tr.t("Thermal profile"); Layout.topMargin: 4 }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Repeater {
            model: Theme.profiles
            ProfileCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                profile: modelData
                selected: page.prof.current === modelData.id
                available: (page.prof.available || []).indexOf(modelData.id) >= 0
                onActivated: backend.setProfile(modelData.id)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 20

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            Layout.alignment: Qt.AlignTop
            title: tr.t("Fans")
            subtitle: page.fan.locked
                      ? tr.fmt("In {profile} the fans are managed automatically by the firmware.", {"profile": tr.t(Theme.profileInfo(page.prof.current).name)})
                      : tr.t("Automatic, maximum or manual control.")
            icon: "fan"
            headerRight: Segmented {
                enabledState: !page.fan.locked
                value: page.fan.locked ? "auto" : page.fan.mode
                options: [
                    { value: "auto", label: tr.t("Automatic") },
                    { value: "max", label: tr.t("Maximum") },
                    { value: "custom", label: tr.t("Manual") }
                ]
                onPicked: (v) => backend.setFan(v, page.cpuPct, page.gpuPct)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                FanReadout { Layout.fillWidth: true; label: tr.t("CPU fan"); rpm: page.tm.fan_cpu || 0 }
                FanReadout { Layout.fillWidth: true; label: tr.t("GPU fan"); rpm: page.tm.fan_gpu || 0 }
            }

            ColumnLayout {
                visible: page.fan.mode === "custom" && !page.fan.locked
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                Repeater {
                    model: [
                        { key: "cpu", label: tr.t("CPU fan speed") },
                        { key: "gpu", label: tr.t("GPU fan speed") }
                    ]
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.label; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
                            Label {
                                text: (modelData.key === "cpu" ? page.cpuPct : page.gpuPct) + "%"
                                font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 18
                            }
                        }
                        LsSlider {
                            Layout.fillWidth: true
                            from: 10; to: 100; stepSize: 5
                            value: modelData.key === "cpu" ? page.cpuPct : page.gpuPct
                            onMoved: {
                                page.editing = true
                                if (modelData.key === "cpu") page.cpuPct = value; else page.gpuPct = value
                                fanDebounce.restart()
                            }
                        }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            Layout.alignment: Qt.AlignTop
            title: tr.t("Automatic profile")
            subtitle: tr.t("Remembers one profile for the power adapter and one for battery, and applies them when you plug or unplug the cable.")
            icon: "rotate-ccw"
            headerRight: Toggle {
                checked: !!page.prof.auto
                onToggled: (v) => backend.setAutoProfile(v)
            }
            Repeater {
                model: [
                    { icon: "plug", label: tr.t("On power adapter"), key: "ac" },
                    { icon: "battery", label: tr.t("On battery"), key: "battery" }
                ]
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 12
                    color: Theme.bg
                    border.color: Theme.border
                    opacity: page.prof.auto ? 1 : 0.45
                    readonly property var p: Theme.profileInfo(page.prof[modelData.key])
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Icon { name: modelData.icon; size: 17; color: Theme.textDim }
                        Label { text: modelData.label; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
                        Icon { name: parent.parent.p.icon; size: 16; color: parent.parent.p.color }
                        Label { text: tr.t(parent.parent.p.name); font.family: Theme.display; font.weight: Font.Bold; font.pixelSize: 17 }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: tr.t("The physical profile key updates these preferences too: the app syncs by itself.")
                color: Theme.textMute
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }
}
