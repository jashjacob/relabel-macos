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
        for x in [0.36, 0.64] { NSBezierPath(ovalIn: NSRect(x: s*(x-0.05), y: s*0.52, width: s*0.10, height: s*0.16)).fill() }
        let m = NSBezierPath(); m.move(to: NSPoint(x: s*0.38, y: s*0.36)); m.line(to: NSPoint(x: s*0.62, y: s*0.36))
        m.lineWidth = s*0.04; m.lineCapStyle = .round; m.stroke()
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (n, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let file = "icon_\(n)x\(n)" + (scale == 2 ? "@2x" : "") + ".png"
    try! render(n * scale).write(to: URL(fileURLWithPath: "\(out)/\(file)"))
}
