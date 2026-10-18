// Renders the Soprano Cast app icon as a 1024×1024 PNG.
// Usage: swift scripts/render-app-icon.swift <output.png>
//
// Family look of Soprano's icon: a dark #2a2a2a rounded square, cream #8a8270 tiles and
// strokes, and exactly one glowing orange #ff7f1a "lamp". The motif is a launcher: a
// square search field outlined by the lamp, a slanted cream magnifier inside it, and a
// small cream ⌘ keycap resting on the field's lower-right corner.
import AppKit

let canvasSize = 1024
let canvas = CGFloat(canvasSize)

// Same body as Soprano's app-icon.png so the family sits equally in the Dock: the rounded
// square fills the whole canvas (corner radius measured from that icon) and carries a 4 px
// lighter rim.
let bodyRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let bodyRadius: CGFloat = 228
let rimWidth: CGFloat = 4

let background = CGColor(srgbRed: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255, alpha: 1)
let rim = CGColor(srgbRed: 0x36 / 255, green: 0x35 / 255, blue: 0x32 / 255, alpha: 1)
let cream = CGColor(srgbRed: 0x8a / 255, green: 0x82 / 255, blue: 0x70 / 255, alpha: 1)
let dimCream = CGColor(srgbRed: 0x8a / 255, green: 0x82 / 255, blue: 0x70 / 255, alpha: 0.55)
let orange = CGColor(srgbRed: 1, green: 0x7f / 255, blue: 0x1a / 255, alpha: 1)

// Geometry in top-left coordinates on the 1024 canvas. The field spans 212…812 so it
// carries the same visual weight as Soprano's tiles; the keycap overlaps its corner.
let fieldRect = CGRect(x: 212, y: 212, width: 600, height: 600)
let fieldRadius: CGFloat = 96
let fieldStroke: CGFloat = 44
let lensCenter = CGPoint(x: 462, y: 462)
let lensRadius: CGFloat = 118
let lensStroke: CGFloat = 44
let handleLength: CGFloat = 150
let keycapRect = CGRect(x: 612, y: 612, width: 232, height: 232)
let keycapRadius: CGFloat = 48
let commandStroke: CGFloat = 16

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: render-app-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

guard
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("render-app-icon: could not create a bitmap context.\n".utf8))
    exit(1)
}

// Draw in top-left coordinates so the geometry above reads like a screen layout.
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Body, then its rim, as on Soprano's icon.
let bodyPath = roundedPath(bodyRect, radius: bodyRadius)
context.addPath(bodyPath)
context.setFillColor(rim)
context.fillPath()
context.addPath(roundedPath(bodyRect.insetBy(dx: rimWidth, dy: rimWidth), radius: bodyRadius - rimWidth))
context.setFillColor(background)
context.fillPath()

// Everything else stays inside the body.
context.addPath(bodyPath)
context.clip()

// The search field: the single glowing orange lamp, drawn as a thick outline.
let field = roundedPath(
    fieldRect.insetBy(dx: fieldStroke / 2, dy: fieldStroke / 2),
    radius: fieldRadius - fieldStroke / 2
)
for (blur, alpha) in [(CGFloat(90), CGFloat(0.55)), (28, 0.45)] {
    context.saveGState()
    context.setShadow(offset: .zero, blur: blur, color: CGColor(srgbRed: 1, green: 0x7f / 255, blue: 0x1a / 255, alpha: alpha))
    context.addPath(field)
    context.setStrokeColor(orange)
    context.setLineWidth(fieldStroke)
    context.strokePath()
    context.restoreGState()
}

// The magnifier: a cream lens with its handle slanting down-right at 45°.
context.setLineCap(.round)
context.setLineJoin(.round)
context.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
    width: lensRadius * 2, height: lensRadius * 2
))
let diagonal = CGFloat(2).squareRoot() / 2
let handleStart = CGPoint(x: lensCenter.x + lensRadius * diagonal, y: lensCenter.y + lensRadius * diagonal)
context.move(to: handleStart)
context.addLine(to: CGPoint(x: handleStart.x + handleLength * diagonal, y: handleStart.y + handleLength * diagonal))
context.setStrokeColor(cream)
context.setLineWidth(lensStroke)
context.strokePath()

// The ⌘ keycap: a body-coloured gap ring so it reads as sitting on the field, a cream cap,
// then a dark ⌘ — a square whose corners carry three-quarter loops.
let keycap = roundedPath(keycapRect, radius: keycapRadius)
context.addPath(roundedPath(keycapRect.insetBy(dx: -24, dy: -24), radius: keycapRadius + 24))
context.setFillColor(background)
context.fillPath()
context.addPath(keycap)
context.setFillColor(cream)
context.fillPath()

let commandCenter = CGPoint(x: keycapRect.midX, y: keycapRect.midY)
let commandHalf: CGFloat = 34
let loopRadius: CGFloat = 30
let command = CGMutablePath()
command.addRect(CGRect(
    x: commandCenter.x - commandHalf, y: commandCenter.y - commandHalf,
    width: commandHalf * 2, height: commandHalf * 2
))
// Each loop starts on the square's edge after the inner quadrant and sweeps 270° outside.
for (dx, dy, start) in [(-1.0, -1.0, 0.5), (1.0, -1.0, 1.0), (1.0, 1.0, 1.5), (-1.0, 1.0, 0.0)] {
    let corner = CGPoint(x: commandCenter.x + commandHalf * dx, y: commandCenter.y + commandHalf * dy)
    let startAngle = CGFloat(start) * .pi
    let begin = CGPoint(x: corner.x + loopRadius * cos(startAngle), y: corner.y + loopRadius * sin(startAngle))
    command.move(to: begin)
    command.addArc(
        center: corner, radius: loopRadius,
        startAngle: startAngle, endAngle: startAngle + .pi * 1.5, clockwise: false
    )
}
context.addPath(command)
context.setStrokeColor(background)
context.setLineWidth(commandStroke)
context.strokePath()

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("render-app-icon: could not finish the bitmap.\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("render-app-icon: could not encode the PNG.\n".utf8))
    exit(1)
}
do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("render-app-icon: could not write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
