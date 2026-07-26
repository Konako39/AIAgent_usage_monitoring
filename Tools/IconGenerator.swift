import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: IconGenerator output.png\n", stderr)
    exit(2)
}

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(3) }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let outer = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 220,
    yRadius: 220
)
NSGraphicsContext.saveGraphicsState()
outer.addClip()
NSGradient(colors: [
    NSColor(red: 0.075, green: 0.09, blue: 0.13, alpha: 1),
    NSColor(red: 0.15, green: 0.17, blue: 0.23, alpha: 1)
])!.draw(in: outer, angle: -45)

let center = NSPoint(x: 512, y: 512)
func arc(radius: CGFloat, end: CGFloat, color: NSColor, glow: NSColor) {
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = 86
    track.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.09).setStroke()
    track.stroke()

    let value = NSBezierPath()
    value.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: end)
    value.lineWidth = 86
    value.lineCapStyle = .round
    color.setStroke()
    context.saveGState()
    context.setShadow(offset: .zero, blur: 22, color: glow.withAlphaComponent(0.65).cgColor)
    value.stroke()
    context.restoreGState()
}

arc(
    radius: 270,
    end: 322,
    color: NSColor(red: 0.05, green: 0.72, blue: 0.64, alpha: 1),
    glow: NSColor(red: 0.04, green: 0.50, blue: 0.90, alpha: 1)
)
arc(
    radius: 156,
    end: 244,
    color: NSColor(red: 0.96, green: 0.55, blue: 0.29, alpha: 1),
    glow: NSColor(red: 0.77, green: 0.30, blue: 0.22, alpha: 1)
)

let spark = NSBezierPath(ovalIn: NSRect(x: 461, y: 461, width: 102, height: 102))
NSColor.white.withAlphaComponent(0.92).setFill()
spark.fill()
NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    exit(4)
}
try png.write(to: URL(fileURLWithPath: output))
