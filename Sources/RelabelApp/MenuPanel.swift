import SwiftUI
import AppKit
import RelabelCore

/// Custom popover window (not an NSMenu) shown under the status item.
@MainActor
final class MenuPanelController {
    private let panel: NSPanel
    private var monitor: Any?

    init(model: AppModel) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: MenuPanelView(model: model))
        host.layer?.cornerRadius = 14
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? close() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let win = button.window else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let b = win.convertToScreen(button.convert(button.bounds, to: nil))
        let x = min(max(b.midX - panel.frame.width / 2, 8), (win.screen?.visibleFrame.maxX ?? 2000) - panel.frame.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: b.minY - panel.frame.height - 6))
        panel.orderFrontRegardless()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

struct MenuPanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(model.status.title).font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.status.accessibilityLabel)

            Text("Recent renames").font(.subheadline).foregroundStyle(.secondary)
            Text("Nothing named yet.")
                .font(.callout).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 60)

            dropArea

            HStack {
                Button("Tidy Up a Folder") {}.disabled(true)
                Spacer()
                Button("Pause") {}.disabled(true)
            }
            Divider()
            HStack {
                Button("Settings") {}.disabled(true)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
            Text("Relabel has named \(model.namedCount) files for you so far")
                .font(.caption).foregroundStyle(.secondary)
            Text("All 100% privately on your Mac").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dropArea: some View {
        Text("Drag a screenshot here or onto the menu bar icon to name it")
            .font(.callout).multilineTextAlignment(.center)
            .foregroundStyle(model.isDraggingFile ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 64).padding(8)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(model.isDraggingFile ? Color.accentColor : Color.secondary.opacity(0.5)))
            .background(model.isDraggingFile ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        switch model.status.iconState {
        case .idle: .green
        case .naming: .blue
        case .paused: .orange
        case .error: .red
        }
    }
}
