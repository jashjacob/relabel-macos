import Foundation
import AppKit

public struct RenameJob: Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var url: URL
    public var kind: FileKind
    public var source: RenameSource
    public var appName: String?
    public init(url: URL, kind: FileKind, source: RenameSource, appName: String? = nil) {
        self.url = url; self.kind = kind; self.source = source; self.appName = appName
    }
}

public enum FrontmostApp {
    /// Name of the app in front, ignoring Relabel itself and the screenshot tool.
    public static func current() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier, Bundle.main.bundleIdentifier != nil { return nil }
        if ["Screenshot", "screencaptureui", "Relabel"].contains(name) { return nil }
        return name
    }
}

/// Watches one folder with a DispatchSource (plus a slow heartbeat) and reports new, finished files.
public final class FolderWatcher: @unchecked Sendable {
    private struct Pending { var firstSeen: Date; var size: Int; var changedAt: Date; var app: String? }

    private let url: URL
    private let folderKind: FolderKind
    private let since: Date
    private let markers: ProcessedMarkers
    private let frontmost: @Sendable () -> String?
    private let onReady: @Sendable (RenameJob) -> Void
    private let stableFor: TimeInterval
    private let screenshotDelay: TimeInterval
    private let queue = DispatchQueue(label: "relabel.watcher")
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var pending: [String: Pending] = [:]       // path -> state
    private var emitted: Set<String> = []              // inode keys already handed over
    private var heartbeat = 0

    public init(url: URL, kind: FolderKind, since: Date, markers: ProcessedMarkers,
                stableFor: TimeInterval = 1.0, screenshotDelay: TimeInterval = 4.0,
                frontmost: @escaping @Sendable () -> String? = { FrontmostApp.current() },
                onReady: @escaping @Sendable (RenameJob) -> Void) {
        self.url = url; self.folderKind = kind; self.since = since; self.markers = markers
        self.stableFor = stableFor; self.screenshotDelay = screenshotDelay
        self.frontmost = frontmost; self.onReady = onReady
    }

    public func start() {
        queue.async { [self] in
            guard source == nil else { return }
            let fd = open(url.path, O_EVTONLY)
            if fd >= 0 {
                let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
                s.setEventHandler { [weak self] in self?.scan() }
                s.setCancelHandler { close(fd) }
                s.resume()
                source = s
            }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 0.5, repeating: 0.5)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
            scan()
        }
    }

    public func stop() {
        queue.async { [self] in
            source?.cancel(); source = nil
            timer?.cancel(); timer = nil
            pending.removeAll()
        }
    }

    /// Looks for new candidate files. Called on directory events and every ~5 seconds.
    private func scan() {
        let keys: [URLResourceKey] = [.creationDateKey, .addedToDirectoryDateKey, .isRegularFileKey, .fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return }
        for item in items {
            let path = item.path
            guard pending[path] == nil,
                  FileEligibility.kind(forFileNamed: item.lastPathComponent, in: folderKind) != nil,
                  let v = try? item.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let added = v.addedToDirectoryDate ?? v.creationDate, added >= since,   // "date added" also catches files moved or copied in
                  !markers.isProcessed(item),
                  let id = FileIdentity.key(item), !emitted.contains(id) else { continue }
            let now = Date()
            pending[path] = Pending(firstSeen: now, size: v.fileSize ?? 0, changedAt: now, app: frontmost())
        }
    }

    /// Moves pending files forward once their size has been stable (and, for screenshots, the preview has gone).
    private func tick() {
        heartbeat += 1
        if heartbeat % 10 == 0 { scan() }
        let now = Date()
        for (path, var p) in pending {
            let item = URL(fileURLWithPath: path)
            guard let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                pending[path] = nil; continue          // moved or deleted before we got to it
            }
            if size != p.size { p.size = size; p.changedAt = now; pending[path] = p; continue }
            let kind = FileEligibility.kind(forFileNamed: item.lastPathComponent, in: folderKind)!
            let settled = now.timeIntervalSince(p.changedAt) >= stableFor
            let previewGone = kind != .screenshot || now.timeIntervalSince(p.firstSeen) >= screenshotDelay
            guard size > 0, settled, previewGone else { continue }
            pending[path] = nil
            if let id = FileIdentity.key(item) { emitted.insert(id) }
            onReady(RenameJob(url: item, kind: kind, source: .auto, appName: kind == .screenshot ? p.app : nil))
        }
    }
}
