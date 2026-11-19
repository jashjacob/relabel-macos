import AppKit
// usage: swift make-icon.swift <out.iconset dir>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let bg = NSBezierPath(roundedRect: r.insetBy(dx: s*0.06, dy: s*0.06), xRadius: s*0.22, yRadius: s*0.22)
        NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.55, blue: 1, alpha: 1),
                            NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.95, alpha: 1)])!.draw(in: bg, angle: -60)
        NSColor.white.setFill(); NSColor.white.setStroke()
        // Generic "document being scanned" glyph.
        let page = NSBezierPath(roundedRect: NSRect(x: s*0.30, y: s*0.22, width: s*0.40, height: s*0.56), xRadius: s*0.04, yRadius: s*0.04)
        page.fill()
        NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.95, alpha: 0.55).setFill()
        for (i, w) in [0.26, 0.26, 0.16].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: s*0.36, y: s*(0.64 - 0.09*CGFloat(i)), width: s*w, height: s*0.03), xRadius: s*0.015, yRadius: s*0.015).fill()
        }
        NSColor.white.setStroke()
        let scan = NSBezierPath(); scan.move(to: NSPoint(x: s*0.22, y: s*0.40)); scan.line(to: NSPoint(x: s*0.78, y: s*0.40))
        scan.lineWidth = s*0.035; scan.lineCapStyle = .round; scan.stroke()
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (n, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let file = "icon_\(n)x\(n)" + (scale == 2 ? "@2x" : "") + ".png"
    try! render(n * scale).write(to: URL(fileURLWithPath: "\(out)/\(file)"))
}
