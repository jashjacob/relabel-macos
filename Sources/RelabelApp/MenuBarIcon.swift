import AppKit
import RelabelCore

/// Draws the menu bar icon as a template image: a frame with a line that sweeps while naming.
enum MenuBarIcon {
    static func image(state: IconState, frame: Int, dragging: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke(); NSColor.black.setFill()
            drawScan(rect, state, frame, dragging)
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func drawScan(_ r: NSRect, _ state: IconState, _ frame: Int, _ dragging: Bool) {
        let frameRect = NSBezierPath(roundedRect: r.insetBy(dx: 2.5, dy: 2.5), xRadius: 2.5, yRadius: 2.5)
        frameRect.lineWidth = dragging ? 2.4 : 1.5; frameRect.stroke()
        var y = r.midY
        if state == .naming { y = r.minY + 4.5 + CGFloat(frame % 6) * 1.8 }
        let line = NSBezierPath(); line.move(to: NSPoint(x: 5, y: y)); line.line(to: NSPoint(x: r.maxX - 5, y: y))
        line.lineWidth = dragging ? 2.6 : 1.5; line.lineCapStyle = .round
        if state == .paused { line.setLineDash([2, 2], count: 2, phase: 0) }
        line.stroke()
        if state == .error {
            NSBezierPath(ovalIn: NSRect(x: r.maxX - 6, y: r.maxY - 6, width: 4, height: 4)).fill()
        }
    }
}
