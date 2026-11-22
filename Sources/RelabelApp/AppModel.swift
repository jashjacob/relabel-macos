import SwiftUI
import UserNotifications
import ServiceManagement
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
    let thumbnails = ThumbnailCache()
    var editingID: UUID?
    var editText = ""
    private(set) var rowErrors: [UUID: String] = [:]
    private var queueState: QueueState = .idle
    private(set) var aiAvailability: ModelAvailability = .available
    private(set) var hold: HoldReason?
    private(set) var warming = false
    private(set) var launchAtLogin = false
    var loginMessage: String?
    var settingsTab = 0
    private(set) var learned: [Correction] = []
    var showLearned = false
    var confirmForget = false
    enum HoldReason { case lowPower, hot }
    var prefs = NamingPreferences() {
        didSet {
            engine.prefs = prefs
            if oldValue.automaticNaming != prefs.automaticNaming { applyWatching() }
            updateHold()
            if let d = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(d, forKey: "namingPrefs") }
        }
    }
    private(set) var screenshotsFolder: ResolvedFolder?
    private(set) var pdfFolders: [ResolvedFolder] = []
    var folderError: String?

    /// Set by the app delegate so views can open windows.
    var openSettings: () -> Void = {}
    var openWelcome: () -> Void = {}
    var openTidyWindow: () -> Void = {}
    @ObservationIgnored private(set) lazy var tidy = TidyModel(app: self)
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
        learned = engine.learning.all
        refreshAI()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.updateHold() } }
        }
        updateHold()
        refreshFolders()
        // The first text recognition on a Mac loads a model (about a minute once): do it now, and say so if it's slow.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !TextExtractor.isWarm { self?.warming = true; self?.updateStatus() }
        }
        Task { [weak self] in
            await TextExtractor.warmUp()
            self?.warming = false
            self?.updateStatus()
        }
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
        if !isPaused && prefs.automaticNaming { engine.sync(watchedFolders()) }
        updateStatus()
    }

    private func watchedFolders() -> [RelabelEngine.WatchedFolder] {
        ([screenshotsFolder].compactMap { $0 } + pdfFolders).compactMap { f in
            guard f.isReachable, let url = f.url else { return nil }
            return .init(id: f.id, url: url, kind: f.entry.kind)
        }
    }

    // MARK: Power, thermal and Apple Intelligence

    func updateHold() {
        let info = ProcessInfo.processInfo
        let new: HoldReason? = (info.thermalState == .serious || info.thermalState == .critical) ? .hot
            : (prefs.pauseInLowPowerMode && info.isLowPowerModeEnabled ? .lowPower : nil)
        guard new != hold else { return }
        hold = new
        engine.setHold(new != nil)
        updateStatus()
    }

    func refreshAI() {
        let a = NamingModel.availability()
        if a != aiAvailability { aiAvailability = a; updateStatus() }
    }

    func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            loginMessage = "Couldn't change this: \(error.localizedDescription)"
        }
        let st = SMAppService.mainApp.status
        launchAtLogin = st == .enabled
        if on, st == .requiresApproval { loginMessage = "Allow Relabel in System Settings > General > Login Items." }
    }

    private func updateStatus() {
        if isPaused { status = .paused; return }
        if hold == .lowPower { status = .lowPowerPaused; return }
        if hold == .hot { status = .coolingDown; return }
        switch queueState {
        case .one: status = .namingOne; return
        case .batch: status = .namingBatch; return
        case .idle: break
        }
        if !prefs.automaticNaming { status = .automaticNamingOff; return }
        if warming, hasAnyFolder { status = .gettingReady; return }
        if aiAvailability == .stillLoading, screenshotsFolder?.isReachable == true || !pdfFolders.isEmpty {
            status = .waitingForAppleIntelligence
        } else if let s = screenshotsFolder {
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
        applyWatching()
    }

    /// Watchers run only when Relabel isn't paused and automatic naming is on. Files saved while off are left alone.
    private func applyWatching() {
        engine.setPaused(isPaused || !prefs.automaticNaming, folders: watchedFolders())
        updateStatus()
    }

    private func handle(_ job: RenameJob, _ outcome: JobOutcome) {
        switch outcome {
        case .renamed(let r):
            lastRename = r
            reloadHistory()
            pill.showRenamed(r)
            if prefs.notifications { notify("\(r.oldName) → \(r.newName)") }
            if prefs.copyScreenshotsToClipboard, r.kind == .screenshot, job.source == .auto, let img = NSImage(contentsOf: r.newURL) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([img])
            }
        case .failed(let why):
            if job.source != .tidy { pill.showFailure(job, why) }
        case .kept(let why):
            // Say so when nothing better was found or the file can't be read; stay quiet about files that are already fine.
            if job.source == .drop || why == NamingPipeline.noBetterName || why == ExtractionError.notAnImage.localizedDescription {
                pill.showMessage("\(job.url.lastPathComponent): \(why). It keeps its name.")
            }
        case .skipped(let why):
            if job.source == .drop { pill.showMessage(why) }
        }
    }

    /// Returns an error message, or nil when the undo worked.
    func undo(_ r: HistoryRecord) -> String? {
        defer { reloadHistory() }
        do { try engine.history.undo(id: r.id); return nil } catch { return error.localizedDescription }
    }

    // MARK: Tidy Up and drops

    func historyChanged() { reloadHistory() }

    func startTidyUp() {
        closePanel()
        guard let url = FolderPicker.choose(message: "Choose a folder to tidy up",
                                            startingAt: screenshotsFolder?.url ?? SuggestedFolders.downloads()) else { return }
        openTidy(url)
    }

    func openTidy(_ folder: URL) {
        tidy.open(folder: folder)
        openTidyWindow()
    }

    /// Files dropped on the panel, the menu bar icon, the app icon, or "Open With". Folders are tidied.
    func handleDrop(_ urls: [URL]) {
        isDraggingFile = false
        var rejected = 0, accepted = 0
        var folder: URL?
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { folder = folder ?? u; continue }
            if let kind = FileEligibility.kindForDropped(u) {
                accepted += 1
                engine.enqueue(RenameJob(url: u, kind: kind, source: .drop))
            } else {
                rejected += 1
            }
        }
        if accepted > 0 { pill.showMessage(accepted == 1 ? "Naming it…" : "Naming \(accepted) files…") }
        if let folder { closePanel(); openTidy(folder) }
        if rejected > 0 { pill.showMessage("Relabel can name images and PDFs. \(rejected == 1 ? "That file was" : "\(rejected) files were") skipped.") }
    }

    // MARK: Learning from the user's own renames

    /// Stores a correction when the user changed a name Relabel gave (inline edit, or a rename in Finder).
    func learn(_ record: HistoryRecord) {
        guard prefs.learnFromRenames, let c = LearningStore.correction(from: record) else { return }
        let first = engine.learning.add(c)
        learned = engine.learning.all
        if first, !UserDefaults.standard.bool(forKey: "learnNoticeShown") {
            UserDefaults.standard.set(true, forKey: "learnNoticeShown")
            pill.showMessage("Relabel learned from your rename and will use it next time. It stays on your Mac.")
        }
    }

    /// Looks for files the user renamed in Finder since Relabel named them.
    func checkExternalRenames() {
        guard prefs.learnFromRenames else { return }
        let history = engine.history
        Task.detached(priority: .utility) { [weak self] in
            let changed = history.detectExternalRenames()
            guard !changed.isEmpty else { return }
            await MainActor.run { [weak self] in
                for r in changed { self?.learn(r) }
                self?.reloadHistory()
            }
        }
    }

    func forgetEverything() {
        engine.learning.forgetAll()
        learned = []
    }

    func forget(_ id: UUID) {
        engine.learning.remove(id: id)
        learned = engine.learning.all
    }

    var styleDescription: String? { StyleProfile.describe(learned) }

    // MARK: Recent renames rows

    func undoRow(_ r: HistoryRecord) { run(r) { try self.engine.history.undo(id: r.id) } }
    func redoRow(_ r: HistoryRecord) { run(r) { try self.engine.history.redo(id: r.id) } }

    func showInFinder(_ r: HistoryRecord) {
        let url = r.state == .applied ? r.newURL : r.oldURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            setRowError(r.id, "Couldn't find the file. It was moved or renamed.")
        }
    }

    func beginEdit(_ r: HistoryRecord) {
        editingID = r.id
        editText = (r.newName as NSString).deletingPathExtension
    }

    func cancelEdit() { editingID = nil }

    func commitEdit(_ r: HistoryRecord) {
        let text = editText
        editingID = nil
        guard text != (r.newName as NSString).deletingPathExtension else { return }
        run(r) {
            let rec = try self.engine.history.userRename(id: r.id, to: text)
            self.learn(rec)
            return rec
        }
    }

    private func run(_ r: HistoryRecord, _ action: () throws -> HistoryRecord) {
        rowErrors[r.id] = nil
        do { _ = try action() } catch { setRowError(r.id, error.localizedDescription) }
        thumbnails.forget(r.id)
        reloadHistory()
    }

    private func setRowError(_ id: UUID, _ text: String) {
        rowErrors[id] = text
        Task { try? await Task.sleep(for: .seconds(6)); rowErrors[id] = nil }
    }

    static func milestoneNote(_ n: Int) -> String? {
        let marks: [(Int, String)] = [(1000, "1,000 files named. That's a lot of tidy."), (500, "500 files named. Your folders thank you."),
                                      (100, "100 files named. Nice."), (50, "50 files named."), (10, "10 files named. Off to a good start."),
                                      (1, "First one named.")]
        return marks.first { n >= $0.0 }?.1
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

    func notify(_ text: String) {
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
