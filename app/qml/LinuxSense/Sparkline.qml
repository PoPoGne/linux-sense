import QtQuick

// multi-series history chart on Canvas
Canvas {
    id: canvas
    property var series: []      // [{data: [...], color: "#..."}]
    property real minValue: 30
    property real maxValue: 100
    renderStrategy: Canvas.Cooperative
    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width, h = height
        // grid
        ctx.strokeStyle = "rgba(255,255,255,0.05)"
        ctx.lineWidth = 1
        for (var g = 0; g <= 4; g++) {
            var gy = Math.round(h * g / 4) + 0.5
            ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
        }
        for (var s = 0; s < series.length; s++) {
            var d = series[s].data || []
            if (d.length < 2) continue
            var col = series[s].color
            var pts = []
            for (var i = 0; i < d.length; i++) {
                if (d[i] === null || d[i] === undefined) continue
                var x = w * i / (d.length - 1)
                var v = Math.max(minValue, Math.min(maxValue, d[i]))
                var y = h - (v - minValue) / (maxValue - minValue) * h
                pts.push([x, y])
            }
            if (pts.length < 2) continue
            // area
            var grad = ctx.createLinearGradient(0, 0, 0, h)
            grad.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.22))
            grad.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.0))
            ctx.beginPath()
            ctx.moveTo(pts[0][0], h)
            for (var p = 0; p < pts.length; p++) ctx.lineTo(pts[p][0], pts[p][1])
            ctx.lineTo(pts[pts.length - 1][0], h)
            ctx.closePath()
            ctx.fillStyle = grad
            ctx.fill()
            // line
            ctx.beginPath()
            ctx.moveTo(pts[0][0], pts[0][1])
            for (var q = 1; q < pts.length; q++) ctx.lineTo(pts[q][0], pts[q][1])
            ctx.strokeStyle = col
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.stroke()
            // end point
            var last = pts[pts.length - 1]
            ctx.beginPath(); ctx.arc(last[0] - 3, last[1], 3.5, 0, Math.PI * 2)
            ctx.fillStyle = col; ctx.fill()
        }
    }
}
