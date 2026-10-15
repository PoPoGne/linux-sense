import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// pagina scorrevole con margini uniformi
Flickable {
    id: page
    default property alias content: col.data
    contentWidth: width
    contentHeight: col.implicitHeight + 64
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: 5; radius: 3; color: Theme.borderHi }
        background: null
    }

    ColumnLayout {
        id: col
        x: 32
        y: 18
        width: page.width - 64
        spacing: 20
    }
}
