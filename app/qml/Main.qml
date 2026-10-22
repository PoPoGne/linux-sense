import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Window
import LinuxSense

Window {
    id: win
    width: 1280
    height: 840
    minimumWidth: 1120
    minimumHeight: 720
    visible: true
    title: "Linux Sense"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property bool maximized: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property var st: backend.state
    property int current: 0

    Binding { target: Theme; property: "profile"; value: (win.st.profile || {}).current || "balanced" }

    readonly property var pages: [
        { name: tr.t("Overview"), icon: "layout-dashboard" },
        { name: tr.t("Performance"), icon: "gauge" },
        { name: tr.t("Lighting"), icon: "keyboard" },
        { name: tr.t("Battery"), icon: "battery-charging" },
        { name: tr.t("About"), icon: "info" }
    ]

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: win.maximized ? 0 : 14
        color: Theme.bg
        border.color: Theme.border
        border.width: win.maximized ? 0 : 1

        // ambient glow tinted with the profile color
        Shape {
            anchors.fill: parent
            anchors.margins: 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: frame.width * 0.78; centerY: -frame.height * 0.08
                    centerRadius: frame.width * 0.55
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0.0; color: Theme.alpha(Theme.accent, 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                startX: 232; startY: 0
                PathLine { x: frame.width - 14; y: 0 }
                PathLine { x: frame.width - 1; y: frame.height * 0.7 }
                PathLine { x: 232; y: frame.height * 0.7 }
                PathLine { x: 232; y: 0 }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: frame.border.width
            spacing: 0

            // ---------------- sidebar ----------------
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 232
                color: Theme.sidebar
                radius: frame.radius
                Rectangle { anchors.right: parent.right; width: parent.radius; height: parent.height; color: parent.color }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

                // window dragging from the sidebar too
                DragHandler {
                    target: null
                    onActiveChanged: if (active) win.startSystemMove()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.topMargin: 22
                    spacing: 6

                    // brand
                    RowLayout {
                        Layout.leftMargin: 6
                        Layout.bottomMargin: 26
                        spacing: 12
                        Image {
                            source: logoUrl
                            sourceSize: Qt.size(84, 84)
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            smooth: true
                            mipmap: true
                        }
                        ColumnLayout {
                            spacing: -4
                            Label {
                                text: "LINUX"
                                font.family: Theme.display
                                font.weight: Font.Bold
                                font.pixelSize: 21
                                font.letterSpacing: 3
                            }
                            Label {
                                text: "SENSE"
                                font.family: Theme.display
                                font.weight: Font.Bold
                                font.pixelSize: 21
                                font.letterSpacing: 3
                                color: Theme.brand
                            }
                        }
                    }

                    Caption { text: tr.t("Menu"); Layout.leftMargin: 10; Layout.bottomMargin: 6 }
                    Repeater {
                        model: win.pages
                        NavItem {
                            Layout.fillWidth: true
                            icon: modelData.icon
                            text: modelData.name
                            active: win.current === index
                            onClicked: win.current = index
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // device status
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: statusCol.implicitHeight + 28
                        radius: 14
                        color: Theme.surface
                        border.color: Theme.border
                        ColumnLayout {
                            id: statusCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 10
                            Label {
                                text: (win.st.model || "Acer").replace("Acer ", "")
                                font.family: Theme.display
                                font.weight: Font.Bold
                                font.pixelSize: 16
                            }
                            RowLayout {
                                spacing: 8
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: backend.connected ? Theme.success : Theme.danger
                                    SequentialAnimation on opacity {
                                        running: !backend.connected
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.3; duration: 600 }
                                        NumberAnimation { to: 1; duration: 600 }
                                    }
                                }
                                Label {
                                    text: backend.connected ? tr.t("Service running") : tr.t("Service not running")
                                    color: Theme.textDim
                                    font.pixelSize: 12
                                }
                            }
                            RowLayout {
                                spacing: 8
                                Icon { name: Theme.profileInfo(Theme.profile).icon; size: 14; color: Theme.accentRaw }
                                Label {
                                    text: tr.fmt("Profile {name}", {"name": tr.t(Theme.profileInfo(Theme.profile).name)})
                                    color: Theme.textDim
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- content ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // title bar
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    DragHandler {
                        target: null
                        onActiveChanged: if (active) win.startSystemMove()
                    }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onDoubleTapped: win.maximized ? win.showNormal() : win.showMaximized()
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        WindowButton { icon: "minus"; onClicked: win.showMinimized() }
                        WindowButton { icon: "square"; onClicked: win.maximized ? win.showNormal() : win.showMaximized() }
                        WindowButton { icon: "x"; danger: true; onClicked: win.close() }
                    }
                }

                // service unreachable warning
                Rectangle {
                    visible: !backend.connected
                    Layout.fillWidth: true
                    Layout.leftMargin: 32
                    Layout.rightMargin: 32
                    Layout.bottomMargin: 6
                    implicitHeight: 50
                    radius: 12
                    color: Theme.alpha(Theme.danger, 0.08)
                    border.color: Theme.alpha(Theme.danger, 0.35)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        spacing: 12
                        Icon { name: "power"; size: 18; color: Theme.danger }
                        Label {
                            text: tr.t("The Linux Sense service is not responding. Start it with:  sudo systemctl start linux-sense")
                            color: Theme.text
                            font.pixelSize: 13
                        }
                    }
                }

                // pages
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Repeater {
                        model: [dashboard, performance, lighting, battery, about]
                        delegate: Loader {
                            anchors.fill: parent
                            sourceComponent: modelData
                            readonly property bool shown: index === win.current
                            active: true
                            visible: opacity > 0
                            opacity: shown ? 1 : 0
                            transform: Translate { y: shown ? 0 : 14; Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // temporary toast notification
        Rectangle {
            id: toast
            property bool error: false
            property string text: ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: 116
            y: shown ? parent.height - height - 28 : parent.height + 10
            property bool shown: false
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            width: toastRow.implicitWidth + 36
            height: 46
            radius: 23
            color: Theme.surfaceHi
            border.color: error ? Theme.alpha(Theme.danger, 0.6) : Theme.borderHi
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 10
                Icon { name: toast.error ? "info" : "check"; size: 16; color: toast.error ? Theme.danger : Theme.success; anchors.verticalCenter: parent.verticalCenter }
                Label { text: toast.text; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            }
            Timer { id: toastTimer; interval: 3800; onTriggered: toast.shown = false }
            Connections {
                target: backend
                function onToast(message, isError) {
                    toast.text = tr.t(message)
                    toast.error = isError
                    toast.shown = true
                    toastTimer.restart()
                }
            }
        }
    }

    Component { id: dashboard; DashboardPage {} }
    Component { id: performance; PerformancePage {} }
    Component { id: lighting; LightingPage {} }
    Component { id: battery; BatteryPage {} }
    Component { id: about; InfoPage {} }

    // resize edges (frameless window)
    Repeater {
        model: win.maximized ? [] : [
            { e: Qt.LeftEdge, x: 0, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.RightEdge, x: -6, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.TopEdge, x: 8, y: 0, w: -16, h: 6, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, x: 8, y: -6, w: -16, h: 6, c: Qt.SizeVerCursor },
            { e: Qt.TopEdge | Qt.LeftEdge, x: 0, y: 0, w: 10, h: 10, c: Qt.SizeFDiagCursor },
            { e: Qt.BottomEdge | Qt.RightEdge, x: -10, y: -10, w: 10, h: 10, c: Qt.SizeFDiagCursor },
            { e: Qt.TopEdge | Qt.RightEdge, x: -10, y: 0, w: 10, h: 10, c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.LeftEdge, x: 0, y: -10, w: 10, h: 10, c: Qt.SizeBDiagCursor }
        ]
        MouseArea {
            x: modelData.x < 0 ? win.width + modelData.x : modelData.x
            y: modelData.y < 0 ? win.height + modelData.y : modelData.y
            width: modelData.w <= 0 ? win.width + modelData.w : modelData.w
            height: modelData.h <= 0 ? win.height + modelData.h : modelData.h
            cursorShape: modelData.c
            onPressed: win.startSystemResize(modelData.e)
        }
    }
}
