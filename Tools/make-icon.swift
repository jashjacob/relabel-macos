import AppKit
// usage: swift make-icon.swift <out.iconset dir>
// Dark tile, a cream page with a folded corner, and an orange scan line. Same artwork as docs/icon.svg.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: true) { r in
        // Artwork is drawn on a 64 x 64 grid (y down) inside the standard icon margin.
        let m = s * 0.06, k = (s - 2 * m) / 64
        func X(_ v: CGFloat) -> CGFloat { m + v * k }
        func Y(_ v: CGFloat) -> CGFloat { m + v * k }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: X(x), y: Y(y), width: w * k, height: h * k), xRadius: rad * k, yRadius: rad * k)
        }
        NSColor(srgbRed: 0.09, green: 0.094, blue: 0.11, alpha: 1).setFill()
        rect(0, 0, 64, 64, 15).fill()

        let page = NSBezierPath()
        page.move(to: NSPoint(x: X(19), y: Y(12))); page.line(to: NSPoint(x: X(39), y: Y(12)))
        page.line(to: NSPoint(x: X(48), y: Y(21))); page.line(to: NSPoint(x: X(48), y: Y(52)))
        page.appendArc(withCenter: NSPoint(x: X(46), y: Y(52)), radius: 2 * k, startAngle: 0, endAngle: 90)
        page.line(to: NSPoint(x: X(19), y: Y(54)))
        page.appendArc(withCenter: NSPoint(x: X(19), y: Y(52)), radius: 2 * k, startAngle: 90, endAngle: 180)
        page.line(to: NSPoint(x: X(17), y: Y(14)))
        page.appendArc(withCenter: NSPoint(x: X(19), y: Y(14)), radius: 2 * k, startAngle: 180, endAngle: 270)
        page.close()
        NSColor(srgbRed: 0.96, green: 0.945, blue: 0.91, alpha: 1).setFill(); page.fill()

        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: X(39), y: Y(12))); fold.line(to: NSPoint(x: X(39), y: Y(21))); fold.line(to: NSPoint(x: X(48), y: Y(21))); fold.close()
        NSColor(srgbRed: 0.85, green: 0.82, blue: 0.75, alpha: 1).setFill(); fold.fill()

        NSColor(srgbRed: 0.604, green: 0.588, blue: 0.541, alpha: 1).setFill()
        rect(23, 27, 20, 3, 1.5).fill(); rect(23, 41, 14, 3, 1.5).fill()
        NSColor(srgbRed: 1, green: 0.353, blue: 0.212, alpha: 1).setFill()
        rect(13, 33, 38, 3.5, 1.75).fill()
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for (n, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let file = "icon_\(n)x\(n)" + (scale == 2 ? "@2x" : "") + ".png"
    try! render(n * scale).write(to: URL(fileURLWithPath: "\(out)/\(file)"))
}
