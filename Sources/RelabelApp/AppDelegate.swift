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
    private var style: IconStyle = .scanLine   // generic for now; the face is an optional style later
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
        model.openTidyWindow = { [unowned self] in tidyWindow.show() }
        model.openSettings = { [unowned self] in settingsWindow.show() }
        model.openWelcome = { [unowned self] in welcomeWindow.show() }
        model.closePanel = { [unowned self] in panel.close() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            let drop = StatusDropView(frame: b.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.onClick = { [unowned self] in togglePanel() }
            drop.onDragState = { [unowned self] on in model.isDraggingFile = on; refreshIcon() }
            drop.onDrop = { [unowned self] urls in model.handleDrop(urls); refreshIcon() }
            b.addSubview(drop)
            b.target = self; b.action = #selector(togglePanel)
            b.setAccessibilityLabel(model.status.accessibilityLabel)
        }
        refreshIcon()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.tick += 1
                if self.model.tick % 20 == 0 { self.model.refreshFolders() }   // notice moved/deleted folders within ~5s
                self.refreshIcon()
            }
        }
        // Dev hook: RELABEL_STATE=naming|paused|error previews icon states; RELABEL_STYLE=scan.
        let env = ProcessInfo.processInfo.environment
        if env["RELABEL_STYLE"] == "face" { style = .face }
        if !UserDefaults.standard.bool(forKey: Self.welcomeKey) || env["RELABEL_WELCOME"] == "1" {
            DispatchQueue.main.async { [self] in welcomeWindow.show() }
        }
        switch env["RELABEL_STATE"] {
        case "naming": model.status = .namingOne
        case "paused": model.status = .paused
        case "idle": model.status = .idle
        default: break
        }
    }

    private func refreshIcon() {
        guard let b = statusItem.button else { return }
        b.image = MenuBarFace.image(style: style, state: model.status.iconState, frame: model.tick, dragging: model.isDraggingFile)
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { onDragState(true); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragState(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onDragState(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDragState(false)
        onDrop(urls)
        return !urls.isEmpty
    }
}
