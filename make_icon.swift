// Usage: swift make_icon.swift <output.iconset dir>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: artwork ~82% of canvas, centered. Everything below is in units of the tile width `u`.
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let u = rect.width
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: rect.minX + x * u, y: rect.minY + y * u, width: w * u, height: h * u)
    }
    func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: r, xRadius: radius * u, yRadius: radius * u)
    }
    func shadowed(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
        sh.shadowBlurRadius = blur * u
        sh.shadowOffset = NSSize(width: 0, height: -dy * u)
        sh.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Background tile: deep indigo-to-blue gradient with a soft highlight in the top-left.
    let tile = rounded(R(0, 0, 1, 1), 0.225)
    NSGradient(colors: [rgb(0.30, 0.42, 1.00), rgb(0.09, 0.10, 0.45)])!.draw(in: tile, angle: -75)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0)])!
        .draw(fromCenter: NSPoint(x: rect.minX + 0.25 * u, y: rect.minY + 0.95 * u), radius: 0,
              toCenter: NSPoint(x: rect.minX + 0.25 * u, y: rect.minY + 0.95 * u), radius: 0.75 * u, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Shift the artwork down a touch so it looks centered.
    NSGraphicsContext.saveGraphicsState()
    let shift = NSAffineTransform()
    shift.translateX(by: 0, yBy: -0.06 * u)
    shift.concat()

    // TV: stand, frame, glowing screen.
    shadowed(blur: 0.04, dy: 0.02, alpha: 0.35) {
        let neck = rounded(R(0.37, 0.38, 0.08, 0.09), 0.012)
        NSGradient(colors: [rgb(0.80, 0.83, 0.92), rgb(0.96, 0.97, 1.0)])!.draw(in: neck, angle: 0)
        let base = rounded(R(0.27, 0.335, 0.28, 0.05), 0.025)
        NSGradient(colors: [rgb(1, 1, 1), rgb(0.82, 0.85, 0.94)])!.draw(in: base, angle: -90)
    }
    let body = R(0.09, 0.45, 0.62, 0.38)
    shadowed(blur: 0.06, dy: 0.03, alpha: 0.45) {
        NSGradient(colors: [rgb(1, 1, 1), rgb(0.80, 0.83, 0.93)])!.draw(in: rounded(body, 0.06), angle: -90)
    }
    let screen = body.insetBy(dx: 0.028 * u, dy: 0.028 * u)
    let screenPath = rounded(screen, 0.035)
    NSGradient(colors: [rgb(0.10, 0.85, 0.95), rgb(0.35, 0.40, 0.98), rgb(0.55, 0.22, 0.85)])!
        .draw(in: screenPath, angle: -55)
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    let gloss = NSBezierPath()  // diagonal glare across the upper-left of the screen
    gloss.move(to: NSPoint(x: screen.minX, y: screen.maxY))
    gloss.line(to: NSPoint(x: screen.minX + 0.62 * screen.width, y: screen.maxY))
    gloss.line(to: NSPoint(x: screen.minX, y: screen.minY + 0.30 * screen.height))
    gloss.close()
    rgb(1, 1, 1, 0.16).setFill()
    gloss.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Signal arcs + dot on the screen.
    let c = NSPoint(x: screen.midX - 0.02 * u, y: screen.minY + 0.075 * u)
    shadowed(blur: 0.02, dy: 0.008, alpha: 0.30) {
        NSColor.white.setStroke()
        for r: CGFloat in [0.07, 0.125, 0.18] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r * u, startAngle: 45, endAngle: 135)
            arc.lineWidth = 0.03 * u
            arc.lineCapStyle = .round
            arc.stroke()
        }
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 0.026 * u, y: c.y - 0.026 * u, width: 0.052 * u, height: 0.052 * u)).fill()
    }

    // Remote: light body with dark buttons (high contrast on the dark tile), tilted, in front of the TV.
    NSGraphicsContext.saveGraphicsState()
    let xf = NSAffineTransform()
    xf.translateX(by: rect.minX + 0.745 * u, yBy: rect.minY + 0.375 * u)
    xf.rotate(byDegrees: -12)
    xf.concat()
    func L(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * u, y: y * u, width: w * u, height: h * u)
    }
    let remote = L(-0.105, -0.245, 0.21, 0.49)
    shadowed(blur: 0.05, dy: 0.025, alpha: 0.55) {
        NSGradient(colors: [rgb(1, 1, 1), rgb(0.78, 0.82, 0.93)])!.draw(in: rounded(remote, 0.055), angle: -90)
    }
    rgb(0.12, 0.16, 0.45, 0.55).setStroke()  // thin dark rim
    let rim = rounded(remote.insetBy(dx: 0.003 * u, dy: 0.003 * u), 0.052)
    rim.lineWidth = 0.006 * u
    rim.stroke()

    rgb(1.0, 0.27, 0.30).setFill()  // power
    NSBezierPath(ovalIn: L(-0.022, 0.155, 0.044, 0.044)).fill()
    NSGradient(colors: [rgb(0.20, 0.24, 0.52), rgb(0.10, 0.12, 0.38)])!  // d-pad ring
        .draw(in: NSBezierPath(ovalIn: L(-0.068, 0.012, 0.136, 0.136)), angle: -90)
    NSGradient(colors: [rgb(0.55, 0.62, 1.0), rgb(0.35, 0.42, 0.95)])!   // OK
        .draw(in: NSBezierPath(ovalIn: L(-0.027, 0.04, 0.054, 0.054)), angle: -90)
    for row: CGFloat in [-0.05, -0.135] {                                   // lower buttons
        for x: CGFloat in [-0.068, 0.014] {
            NSGradient(colors: [rgb(0.20, 0.24, 0.52), rgb(0.12, 0.14, 0.40)])!
                .draw(in: rounded(L(x, row, 0.054, 0.054), 0.027), angle: -90)
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
