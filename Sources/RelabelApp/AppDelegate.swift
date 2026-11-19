import AppKit
import RelabelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: MenuPanelController!
    private var timer: Timer?
    private var style: IconStyle = .face

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = MenuPanelController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.target = self; b.action = #selector(togglePanel)
            b.setAccessibilityLabel(model.status.accessibilityLabel)
        }
        refreshIcon()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick += 1; self?.refreshIcon() }
        }
        // Dev hook: RELABEL_STATE=naming|paused|error previews icon states; RELABEL_STYLE=scan.
        let env = ProcessInfo.processInfo.environment
        if env["RELABEL_STYLE"] == "scan" { style = .scanLine }
        switch env["RELABEL_STATE"] {
        case "naming": model.status = .namingOne
        case "paused": model.status = .paused
        case "idle": model.status = .idle
        default: break
        }
    }

    private func refreshIcon() {
        guard let b = statusItem.button else { return }
        b.image = MenuBarFace.image(style: style, state: model.status.iconState, frame: model.tick)
        b.setAccessibilityLabel(model.status.accessibilityLabel)
    }

    @objc private func togglePanel() {
        guard let b = statusItem.button else { return }
        panel.toggle(relativeTo: b)
    }
}
