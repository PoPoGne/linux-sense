pragma Singleton
import QtQuick

QtObject {
    id: theme

    // superfici
    readonly property color bg: "#0a0b0e"
    readonly property color sidebar: "#0c0e12"
    readonly property color surface: "#111319"
    readonly property color surfaceHi: "#171a21"
    readonly property color surfaceHover: "#1c2029"
    readonly property color border: "#1d2129"
    readonly property color borderHi: "#2a2f3a"

    // testo
    readonly property color text: "#eceef3"
    readonly property color textDim: "#a1a7b3"
    readonly property color textMute: "#646b78"

    // marchio
    readonly property color brand: "#ff2e4d"
    readonly property color brand2: "#ff8a3d"
    readonly property color danger: "#ff4d5e"
    readonly property color warning: "#ffb547"
    readonly property color success: "#2fe39b"

    readonly property string display: "Rajdhani"
    readonly property string body: "Inter"

    readonly property int radius: 16
    readonly property int radiusSm: 10

    // profili: dal più freddo al più caldo
    readonly property var profiles: [
        { id: "low-power", name: "Eco", icon: "leaf", color: "#2fe39b",
          desc: "Massima autonomia, consumi ridotti al minimo." },
        { id: "quiet", name: "Silenzioso", icon: "moon", color: "#4c9dff",
          desc: "Ventole al minimo, per lavorare in silenzio." },
        { id: "balanced", name: "Bilanciato", icon: "scale", color: "#9b7bff",
          desc: "Equilibrio tra prestazioni, calore e rumore." },
        { id: "balanced-performance", name: "Prestazioni", icon: "zap", color: "#ff8a3d",
          desc: "Più potenza per giochi e carichi pesanti." },
        { id: "performance", name: "Turbo", icon: "flame", color: "#ff2e4d",
          desc: "Tutta la potenza, ventole al massimo." }
    ]

    function profileInfo(pid) {
        for (var i = 0; i < profiles.length; i++)
            if (profiles[i].id === pid) return profiles[i]
        return profiles[2]
    }

    // colore d'accento: segue il profilo attivo
    property string profile: "balanced"
    readonly property color accentRaw: profileInfo(profile).color
    property color accent: accentRaw
    Behavior on accent { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    function hex(c) {
        function h(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
        return h(c.r) + h(c.g) + h(c.b)
    }
    function icon(name, color) {
        return "image://icon/" + name + "/" + String(color).substring(1)
    }
}
