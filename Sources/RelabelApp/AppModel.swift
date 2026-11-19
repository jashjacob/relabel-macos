import SwiftUI
import UserNotifications
import RelabelCore

@MainActor
@Observable
final class AppModel {
    var status: AppStatus = .noFolder
    var isDraggingFile = false
    var namedCount = 0
    var tick = 0   // animation clock for the icon

    let bookmarks: FolderBookmarks
    @ObservationIgnored private(set) var engine: RelabelEngine!
    let pill = PillController()
    private(set) var recents: [HistoryRecord] = []
    private(set) var lastRename: HistoryRecord?
    private(set) var isPaused = false
    private var queueState: QueueState = .idle
    var prefs = NamingPreferences() {
        didSet {
            engine.prefs = prefs
            if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: "namingPrefs") }
        }
    }
    private(set) var screenshotsFolder: ResolvedFolder?
    private(set) var pdfFolders: [ResolvedFolder] = []
    var folderError: String?

    /// Set by the app delegate so views can open windows.
    var openSettings: () -> Void = {}
    var openWelcome: () -> Void = {}
    var closePanel: () -> Void = {}

    private var notifiedLost: Set<UUID> = []

    init(bookmarks: FolderBookmarks = FolderBookmarks()) {
        self.bookmarks = bookmarks
        engine = RelabelEngine(
            onState: { [weak self] state in Task { @MainActor in self?.queueState = state; self?.updateStatus() } },
            onOutcome: { [weak self] job, outcome in Task { @MainActor in self?.handle(job, outcome) } })
        if let d = UserDefaults.standard.data(forKey: "namingPrefs"), let p = try? JSONDecoder().decode(NamingPreferences.self, from: d) {
            prefs = p
        }
        engine.prefs = prefs
        pill.onUndo = { [weak self] r in self?.undo(r) }
        pill.onRetry = { [weak self] job in self?.engine.enqueue(job) }
        reloadHistory()
        refreshFolders()
        Task { await TextExtractor.warmUp() }   // first recognition on a Mac loads a model; do it now, not on the first file
    }

    /// Messages for every folder we can't reach, shown in the menu panel.
    var lostMessages: [String] {
        var out: [String] = []
        if let s = screenshotsFolder, !s.isReachable { out.append(FolderMessages.screenshotsLost) }
        for p in pdfFolders where !p.isReachable { out.append(FolderMessages.pdfLost(p.displayPath)) }
        return out
    }

    var hasAnyFolder: Bool { screenshotsFolder != nil || !pdfFolders.isEmpty }

    /// Re-checks every folder. Cheap, so it runs on a timer and after any change.
    func refreshFolders() {
        screenshotsFolder = bookmarks.resolveAll(.screenshots).first
        pdfFolders = bookmarks.resolveAll(.pdf)

        for f in [screenshotsFolder].compactMap({ $0 }) + pdfFolders {
            if f.isReachable {
                bookmarks.startAccess(f.entry)
                notifiedLost.remove(f.id)
            } else {
                bookmarks.stopAccess(id: f.id)
                if notifiedLost.insert(f.id).inserted {
                    notify(f.entry.kind == .screenshots ? FolderMessages.screenshotsLost : FolderMessages.pdfLost(f.displayPath))
                }
            }
        }
        if !isPaused { engine.sync(watchedFolders()) }
        updateStatus()
    }

    private func watchedFolders() -> [RelabelEngine.WatchedFolder] {
        ([screenshotsFolder].compactMap { $0 } + pdfFolders).compactMap { f in
            guard f.isReachable, let url = f.url else { return nil }
            return .init(id: f.id, url: url, kind: f.entry.kind)
        }
    }

    private func updateStatus() {
        if isPaused { status = .paused; return }
        switch queueState {
        case .one: status = .namingOne; return
        case .batch: status = .namingBatch; return
        case .idle: break
        }
        if let s = screenshotsFolder {
            status = s.isReachable ? .idle : .folderUnreachable
        } else if !pdfFolders.isEmpty {
            status = .idle
        } else {
            status = .noFolder
        }
    }

    // MARK: Naming results

    func togglePause() {
        isPaused.toggle()
        engine.setPaused(isPaused, folders: watchedFolders())
        updateStatus()
    }

    private func handle(_ job: RenameJob, _ outcome: JobOutcome) {
        switch outcome {
        case .renamed(let r):
            lastRename = r
            reloadHistory()
            pill.showRenamed(r)
        case .failed(let why):
            if job.source != .tidy { pill.showFailure(job, why) }
        case .kept, .skipped:
            break
        }
    }

    /// Returns an error message, or nil when the undo worked.
    func undo(_ r: HistoryRecord) -> String? {
        defer { reloadHistory() }
        do { try engine.history.undo(id: r.id); return nil } catch { return error.localizedDescription }
    }

    private func reloadHistory() {
        recents = engine.history.recent(10)
        namedCount = engine.history.namedCount
    }

    // MARK: Choosing folders

    func chooseFolder(kind: FolderKind, replacing id: UUID? = nil) {
        let start = kind == .screenshots
            ? screenshotsFolder?.url ?? SuggestedFolders.screenshotLocation()
            : SuggestedFolders.downloads()
        guard let url = FolderPicker.choose(message: "Choose your \(kind.displayName) folder", startingAt: start) else { return }
        setFolder(url, kind: kind, replacing: id)
    }

    /// Uses a folder directly (e.g. the suggested one) and touches it so macOS asks for access up front.
    func setFolder(_ url: URL, kind: FolderKind, replacing id: UUID? = nil) {
        do {
            if let id { try bookmarks.replace(id: id, with: url) } else { try bookmarks.add(url, kind: kind) }
            folderError = nil
        } catch {
            folderError = "Couldn't use that folder. Choose a different one."
        }
        refreshFolders()
        if let r = (kind == .screenshots ? screenshotsFolder : pdfFolders.first(where: { $0.url == url })), !r.isReachable {
            folderError = "Relabel can't read that folder. Allow access when macOS asks, or choose another."
        }
    }

    func removeFolder(_ id: UUID) {
        bookmarks.remove(id: id)
        refreshFolders()
    }

    func revealInFinder(_ folder: ResolvedFolder) {
        guard let url = folder.url, folder.isReachable else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens the macOS screenshot toolbar (same as Shift-Command-5), where Options shows the save location.
    func openScreenshotOptions() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Notifications

    private func notify(_ text: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            _ = try? await center.requestAuthorization(options: [.alert])
            let content = UNMutableNotificationContent()
            content.title = "Relabel"
            content.body = text
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

enum FolderPicker {
    @MainActor
    static func choose(message: String, startingAt: URL?) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = "Choose Folder"
        panel.directoryURL = startingAt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
