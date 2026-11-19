import AppKit
import RelabelCore

enum IconStyle: String, CaseIterable {
    case scanLine, face
    var label: String { self == .scanLine ? "Scan line" : "Face" }
    var blurb: String { self == .scanLine ? "A plain frame with a line that sweeps while naming." : "A small face whose eyes blink while naming and look at a dragged file." }
}

/// Draws the menu bar icon as a template image. Face eyes blink while naming and look sleepy when paused.
enum MenuBarFace {
    static func image(style: IconStyle, state: IconState, frame: Int, dragging: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke(); NSColor.black.setFill()
            switch style {
            case .face: drawFace(rect, state, frame, dragging)
            case .scanLine: drawScan(rect, state, frame, dragging)
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func drawFace(_ r: NSRect, _ state: IconState, _ frame: Int, _ dragging: Bool) {
        let body = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2.5), xRadius: 4.5, yRadius: 4.5)
        body.lineWidth = 1.5; body.stroke()
        let eyeY = r.midY + 1.2
        let blink = state == .naming && frame % 4 == 3
        for x in [r.midX - 3.2, r.midX + 3.2] {
            switch state {
            case .paused:   // sleepy: flat lines
                let p = NSBezierPath(); p.move(to: NSPoint(x: x - 1.5, y: eyeY)); p.line(to: NSPoint(x: x + 1.5, y: eyeY))
                p.lineWidth = 1.3; p.lineCapStyle = .round; p.stroke()
            case .error:
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - 1.3, y: eyeY - 1.3)); p.line(to: NSPoint(x: x + 1.3, y: eyeY + 1.3))
                p.move(to: NSPoint(x: x - 1.3, y: eyeY + 1.3)); p.line(to: NSPoint(x: x + 1.3, y: eyeY - 1.3))
                p.lineWidth = 1.2; p.lineCapStyle = .round; p.stroke()
            default:
                let h: CGFloat = blink ? 0.8 : 3
                let shift: CGFloat = dragging ? -1.2 : (state == .naming ? CGFloat((frame % 4) - 1) * 0.5 : 0)   // looks toward a dragged file
                NSBezierPath(ovalIn: NSRect(x: x - 1.1 + shift, y: eyeY - h / 2, width: 2.2, height: h)).fill()
            }
        }
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: r.midX - 2.5, y: r.midY - 3.5)); mouth.line(to: NSPoint(x: r.midX + 2.5, y: r.midY - 3.5))
        mouth.lineWidth = 1.2; mouth.lineCapStyle = .round; mouth.stroke()
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
