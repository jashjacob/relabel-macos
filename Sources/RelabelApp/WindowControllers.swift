import SwiftUI
import AppKit

/// Owns one reusable window hosting a SwiftUI view.
@MainActor
final class SingleWindow {
    private var window: NSWindow?
    private let make: () -> NSView
    private let title: String
    private let style: NSWindow.StyleMask
    var onClose: (() -> Void)?
    private var closeObserver: Any?

    init(title: String, style: NSWindow.StyleMask = [.titled, .closable], make: @escaping () -> NSView) {
        self.title = title; self.style = style; self.make = make
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
            w.title = title
            w.contentView = make()
            w.isReleasedWhenClosed = false
            w.center()
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose?() }
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// Dev hook: writes the window's own contents to a PNG (no screen recording permission needed).
    func snapshot(to path: String) {
        guard let v = window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Dev hook: selects a tab by index when the content is a TabView-backed hosting view.
    var contentWindow: NSWindow? { window }
}
