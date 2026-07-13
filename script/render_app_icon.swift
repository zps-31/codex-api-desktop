import AppKit
import Foundation

enum IconKind: String {
    case api
    case meter
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: red / 255,
        green: green / 255,
        blue: blue / 255,
        alpha: alpha
    )
}

func stroke(
    from start: NSPoint,
    to end: NSPoint,
    color: NSColor,
    width: CGFloat,
    lineCap: NSBezierPath.LineCapStyle = .round
) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = lineCap
    color.setStroke()
    path.stroke()
}

func fillCircle(center: NSPoint, radius: CGFloat, color: NSColor) {
    let rect = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

func drawBase() {
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0, 0, alpha: 0.42)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -18)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let outer = NSBezierPath(
        roundedRect: NSRect(x: 92, y: 104, width: 840, height: 824),
        xRadius: 188,
        yRadius: 188
    )
    color(19, 21, 25).setFill()
    outer.fill()
    NSGraphicsContext.restoreGraphicsState()

    let face = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 112, width: 824, height: 808),
        xRadius: 180,
        yRadius: 180
    )
    let baseGradient = NSGradient(colors: [
        color(47, 52, 62),
        color(20, 22, 27)
    ])!
    baseGradient.draw(in: face, angle: -82)

    color(255, 255, 255, alpha: 0.10).setStroke()
    face.lineWidth = 4
    face.stroke()
}

func drawAPIIcon() {
    let left = NSPoint(x: 306, y: 512)
    let top = NSPoint(x: 512, y: 688)
    let right = NSPoint(x: 718, y: 512)
    let bottom = NSPoint(x: 512, y: 336)

    stroke(from: left, to: top, color: color(95, 215, 190), width: 46)
    stroke(from: top, to: right, color: color(81, 163, 240), width: 46)
    stroke(from: right, to: bottom, color: color(112, 133, 245), width: 46)
    stroke(from: bottom, to: left, color: color(82, 205, 152), width: 46)

    fillCircle(center: left, radius: 62, color: color(78, 207, 154))
    fillCircle(center: top, radius: 62, color: color(92, 207, 218))
    fillCircle(center: right, radius: 62, color: color(95, 139, 242))
    fillCircle(center: bottom, radius: 62, color: color(86, 189, 208))

    let center = NSBezierPath(
        roundedRect: NSRect(x: 346, y: 386, width: 332, height: 252),
        xRadius: 74,
        yRadius: 74
    )
    let centerGradient = NSGradient(colors: [
        color(35, 42, 50),
        color(17, 20, 25)
    ])!
    centerGradient.draw(in: center, angle: -90)
    color(255, 255, 255, alpha: 0.16).setStroke()
    center.lineWidth = 4
    center.stroke()

    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 428, y: 562))
    chevron.line(to: NSPoint(x: 488, y: 512))
    chevron.line(to: NSPoint(x: 428, y: 462))
    chevron.lineWidth = 31
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    color(244, 248, 250).setStroke()
    chevron.stroke()
    stroke(
        from: NSPoint(x: 528, y: 466),
        to: NSPoint(x: 604, y: 466),
        color: color(244, 248, 250),
        width: 31
    )
}

func drawMeterIcon() {
    let center = NSPoint(x: 512, y: 450)
    let gauge = NSBezierPath()
    gauge.appendArc(
        withCenter: center,
        radius: 252,
        startAngle: 205,
        endAngle: -25,
        clockwise: false
    )
    gauge.lineWidth = 66
    gauge.lineCapStyle = .round
    color(78, 89, 104).setStroke()
    gauge.stroke()

    let activeGauge = NSBezierPath()
    activeGauge.appendArc(
        withCenter: center,
        radius: 252,
        startAngle: 205,
        endAngle: 62,
        clockwise: false
    )
    activeGauge.lineWidth = 66
    activeGauge.lineCapStyle = .round
    color(74, 211, 159).setStroke()
    activeGauge.stroke()

    for angle in stride(from: 205.0, through: -25.0, by: -46.0) {
        let radians = CGFloat(angle * .pi / 180)
        let inner = NSPoint(
            x: center.x + cos(radians) * 205,
            y: center.y + sin(radians) * 205
        )
        let outer = NSPoint(
            x: center.x + cos(radians) * 276,
            y: center.y + sin(radians) * 276
        )
        stroke(
            from: inner,
            to: outer,
            color: color(241, 246, 247, alpha: 0.82),
            width: 16
        )
    }

    let needleAngle = CGFloat(58 * Double.pi / 180)
    let needleTip = NSPoint(
        x: center.x + cos(needleAngle) * 188,
        y: center.y + sin(needleAngle) * 188
    )
    stroke(
        from: center,
        to: needleTip,
        color: color(250, 188, 74),
        width: 30
    )
    fillCircle(center: center, radius: 52, color: color(245, 248, 249))
    fillCircle(center: center, radius: 25, color: color(38, 43, 51))

    let barColors = [
        color(82, 195, 225),
        color(78, 211, 159),
        color(250, 188, 74)
    ]
    let heights: [CGFloat] = [74, 116, 164]
    for index in 0..<3 {
        let rect = NSRect(
            x: 396 + CGFloat(index) * 92,
            y: 232,
            width: 58,
            height: heights[index]
        )
        barColors[index].setFill()
        NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
    }
}

guard CommandLine.arguments.count == 3,
      let kind = IconKind(rawValue: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(
        Data("usage: swift render_app_icon.swift <api|meter> <output.png>\n".utf8)
    )
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
drawBase()
switch kind {
case .api:
    drawAPIIcon()
case .meter:
    drawMeterIcon()
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
