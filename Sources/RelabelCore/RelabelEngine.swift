import Foundation

/// Owns the watchers, queue and stores. The app and the command line tool both drive this.
public final class RelabelEngine: @unchecked Sendable {
    public struct WatchedFolder: Sendable, Equatable { public var id: UUID; public var url: URL; public var kind: FolderKind
        public init(id: UUID, url: URL, kind: FolderKind) { self.id = id; self.url = url; self.kind = kind } }

    public let history: RenameHistory
    public let markers: ProcessedMarkers
    private let lock = NSLock()
    private var prefsValue = NamingPreferences()
    private var watchers: [UUID: (folder: WatchedFolder, watcher: FolderWatcher)] = [:]
    private var paused = false
    private var held = false
    private var deferred: [RenameJob] = []
    private var queue: RenameQueue!
    private let stableFor: TimeInterval
    private let screenshotDelay: TimeInterval

    public init(history: RenameHistory = RenameHistory(), markers: ProcessedMarkers = ProcessedMarkers(),
                stableFor: TimeInterval = 1.0, screenshotDelay: TimeInterval = 4.0,
                namer: NamerFunction? = nil,
                onState: @escaping @Sendable (QueueState) -> Void = { _ in },
                onOutcome: @escaping @Sendable (RenameJob, JobOutcome) -> Void = { _, _ in }) {
        self.history = history; self.markers = markers
        self.stableFor = stableFor; self.screenshotDelay = screenshotDelay
        let pipeline = NamingPipeline(history: history, markers: markers, prefs: { [unowned self] in self.prefs },
                                      namer: namer ?? { ctx, p in await NamingModel.name(for: ctx, prefs: p) })
        queue = RenameQueue(pipeline: pipeline, onState: onState, onOutcome: onOutcome)
    }

    public var prefs: NamingPreferences {
        get { lock.withLock { prefsValue } }
        set { lock.withLock { prefsValue = newValue } }
    }

    public var isPaused: Bool { lock.withLock { paused } }

    /// Starts watchers for reachable folders and stops the rest. Safe to call often.
    public func sync(_ folders: [WatchedFolder]) {
        lock.withLock {
            let wanted = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
            for (id, entry) in watchers where wanted[id] != entry.folder { entry.watcher.stop(); watchers[id] = nil }
            guard !paused else { return }
            for f in folders where watchers[f.id] == nil { startWatcherLocked(f, since: markers.watchStart(for: f.id.uuidString)) }
        }
    }

    /// While paused nothing is watched. Files saved during the pause are left alone.
    public func setPaused(_ p: Bool, folders: [WatchedFolder]) {
        lock.withLock {
            paused = p
            for (_, e) in watchers { e.watcher.stop() }
            watchers.removeAll()
            if !p { for f in folders { startWatcherLocked(f, since: Date()) } }
        }
    }

    /// Low Power Mode or a hot Mac: new files wait (and are named later) instead of being dropped.
    /// Files the user dropped on Relabel on purpose are never held.
    public func setHold(_ on: Bool) {
        let release: [RenameJob] = lock.withLock {
            held = on
            if on { return [] }
            defer { deferred.removeAll() }
            return deferred
        }
        for job in release { enqueue(job) }
    }

    public var isHeld: Bool { lock.withLock { held } }

    public func enqueue(_ job: RenameJob) {
        let defer_ = lock.withLock { () -> Bool in
            guard held, job.source == .auto else { return false }
            if !deferred.contains(where: { $0.url == job.url }) { deferred.append(job) }
            return true
        }
        if defer_ { return }
        Task { await queue.enqueue(job) }
    }

    private func startWatcherLocked(_ f: WatchedFolder, since: Date) {
        let w = FolderWatcher(url: f.url, kind: f.kind, since: since, markers: markers,
                              stableFor: stableFor, screenshotDelay: screenshotDelay) { [weak self] job in
            self?.enqueue(job)
        }
        watchers[f.id] = (f, w)
        w.start()
    }
}
