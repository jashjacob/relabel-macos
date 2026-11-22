import AppKit
import SwiftUI
import UserNotifications
import RelabelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: MenuPanelController!
    private var timer: Timer?
    private var settingsWindow: SingleWindow!
    private var welcomeWindow: SingleWindow!
    private var tidyWindow: SingleWindow!
    private static let welcomeKey = "welcomeCompleted"

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        panel = MenuPanelController(model: model)
        settingsWindow = SingleWindow(title: "Relabel Settings") { [model] in
            NSHostingView(rootView: SettingsView(model: model))
        }
        welcomeWindow = SingleWindow(title: "Welcome to Relabel") { [model, unowned self] in
            NSHostingView(rootView: WelcomeView(model: model) { [weak self] in self?.welcomeWindow.close() })
        }
        welcomeWindow.onClose = { UserDefaults.standard.set(true, forKey: AppDelegate.welcomeKey) }
        tidyWindow = SingleWindow(title: "Tidy Up", style: [.titled, .closable, .resizable, .miniaturizable]) { [model] in
            NSHostingView(rootView: TidyView(model: model.tidy))
        }
        tidyWindow.onClose = { [model] in model.tidy.cancel() }
        model.openTidyWindow = { [unowned self] in tidyWindow.show() }
        model.openSettings = { [unowned self] in settingsWindow.show() }
        model.openWelcome = { [unowned self] in welcomeWindow.show() }
        model.closePanel = { [unowned self] in panel.close() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            // Cover the whole status item window (not just the 22pt button) so a drop near the edge still lands.
            let host: NSView = b.window?.contentView ?? b.superview ?? b
            let drop = StatusDropView(frame: host.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [unowned self] in togglePanel() }
            drop.onDragState = { [unowned self] on in model.isDraggingFile = on; refreshIcon() }
            drop.onDrop = { [unowned self] urls in model.handleDrop(urls); refreshIcon() }
            host.addSubview(drop, positioned: .above, relativeTo: nil)
            b.target = self; b.action = #selector(togglePanel)
            b.setAccessibilityLabel(model.status.accessibilityLabel)
        }
        refreshIcon()
        if let path = ProcessInfo.processInfo.environment["RELABEL_DEBUG_FRAMES"] {   // dev hook: where is the drop view?
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                let b = statusItem.button
                let d = (b?.window?.contentView ?? b)?.subviews.compactMap { $0 as? StatusDropView }.first
                let text = "button=\(String(describing: b?.frame)) bounds=\(String(describing: b?.bounds)) drop=\(String(describing: d?.frame)) window=\(String(describing: b?.window?.frame)) types=\(String(describing: d?.registeredDraggedTypes)) windowDelegate=\(String(describing: b?.window?.delegate)) windowClass=\(String(describing: b?.window.map { type(of: $0) }))"
                try? text.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.tick += 1
                if self.model.tick % 20 == 0 { self.model.refreshFolders(); self.model.refreshAI(); self.model.checkExternalRenames() }   // notice moved/deleted folders within ~5s
                self.refreshIcon()
            }
        }
        let env = ProcessInfo.processInfo.environment
        if !UserDefaults.standard.bool(forKey: Self.welcomeKey) || env["RELABEL_WELCOME"] == "1" {
            DispatchQueue.main.async { [self] in welcomeWindow.show() }
        }
        if let w = env["RELABEL_OPEN"] {   // dev hook: open a window at launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                if w == "settings" { settingsWindow.show() } else if w == "welcome" { welcomeWindow.show() } else if w == "tidy" { tidyWindow.show() }
                if let out = env["RELABEL_SNAPSHOT"] {
                    let tabs = Int(env["RELABEL_TABS"] ?? "1") ?? 1
                    let first = Int(env["RELABEL_FIRST_TAB"] ?? "0") ?? 0
                    for i in 0..<tabs {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["RELABEL_SNAP_DELAY"] ?? "") ?? 14) + Double(i) * 5) { [self] in
                            model.settingsTab = first + i
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                                (w == "settings" ? settingsWindow : w == "tidy" ? tidyWindow : welcomeWindow).snapshot(to: "\(out).\(i).png")
                            }
                        }
                    }
                }
            }
        }
        switch env["RELABEL_STATE"] {
        case "naming": model.status = .namingOne
        case "paused": model.status = .paused
        case "idle": model.status = .idle
        default: break
        }
    }

    private var lastIconKey = ""

    /// Redraws the menu bar icon only when something visible changed. Honors Reduce Motion (no sweeping or blinking).
    private func refreshIcon() {
        guard let b = statusItem.button else { return }
        let state = model.status.iconState
        let animate = state == .naming && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let frame = animate ? model.tick : 0
        let key = "\(state)|\(frame)|\(model.isDraggingFile)|\(model.status.title)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        b.image = MenuBarIcon.image(state: state, frame: frame, dragging: model.isDraggingFile)
        b.setAccessibilityLabel(model.status.accessibilityLabel)
    }

    /// Files or folders dropped on the app icon, or opened with "Open With > Relabel".
    func application(_ application: NSApplication, open urls: [URL]) {
        model.handleDrop(urls)
    }

    @objc private func togglePanel() {
        guard let b = statusItem.button else { return }
        panel.toggle(relativeTo: b)
    }
}


enum DropDebug {
    static func log(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["RELABEL_DEBUG_DROPS"] else { return }
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }
}

/// Transparent view over the status item button that takes file drops and passes clicks through to the button.
final class StatusDropView: NSView {
    var onClick: () -> Void = {}
    var onDragState: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { DropDebug.log("view entered"); onDragState(true); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragState(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onDragState(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DropDebug.log("view perform")
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDragState(false)
        onDrop(urls)
        return !urls.isEmpty
    }
}
