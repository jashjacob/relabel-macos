import Foundation

public enum FolderKind: String, Codable, Sendable, CaseIterable {
    case screenshots, pdf

    public var displayName: String { self == .screenshots ? "screenshots" : "PDF" }
}

/// A folder the user chose, stored as a security-scoped bookmark so access survives relaunch.
public struct FolderEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: FolderKind
    public var bookmark: Data
    public var lastKnownPath: String
}

public struct ResolvedFolder: Identifiable, Sendable, Equatable {
    public enum Problem: Sendable, Equatable { case missing, notADirectory, inTrash, noPermission, unresolvable }
    public var entry: FolderEntry
    /// Current location (bookmarks follow moves). nil when the bookmark could not be resolved.
    public var url: URL?
    public var problem: Problem?
    public var id: UUID { entry.id }
    public var isReachable: Bool { problem == nil && url != nil }
    public var displayPath: String {
        ((url?.path ?? entry.lastKnownPath) as NSString).abbreviatingWithTildeInPath
    }
}

public enum FolderBookmarksError: Error, Equatable { case notADirectory, bookmarkFailed(String) }

/// Persists chosen folders (JSON in Application Support) and manages scoped access.
public final class FolderBookmarks: @unchecked Sendable {
    private let storeURL: URL
    private let lock = NSLock()
    private var entries: [FolderEntry] = []
    private var accessed: [UUID: URL] = [:]

    public static var defaultStoreURL: URL {
        AppSupport.directory.appendingPathComponent("folders.json")
    }

    public init(storeURL: URL = FolderBookmarks.defaultStoreURL) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([FolderEntry].self, from: data) {
            entries = decoded
        }
    }

    deinit { stopAllAccess() }

    public func entries(of kind: FolderKind) -> [FolderEntry] {
        lock.withLock { entries.filter { $0.kind == kind } }
    }

    /// Adds a folder. Screenshots allow one folder (replaced); PDFs allow several (duplicates ignored).
    @discardableResult
    public func add(_ url: URL, kind: FolderKind) throws -> FolderEntry {
        let entry = try makeEntry(url, kind: kind)
        lock.withLock {
            if kind == .screenshots {
                for old in entries where old.kind == .screenshots { stopAccessLocked(old.id) }
                entries.removeAll { $0.kind == .screenshots }
            } else if let dupe = entries.firstIndex(where: { $0.kind == .pdf && $0.lastKnownPath == entry.lastKnownPath }) {
                stopAccessLocked(entries[dupe].id)
                entries.remove(at: dupe)
            }
            entries.append(entry)
            saveLocked()
        }
        return entry
    }

    /// Points an existing row at a different folder, keeping its position.
    @discardableResult
    public func replace(id: UUID, with url: URL) throws -> FolderEntry {
        let old = lock.withLock { entries.first { $0.id == id } }
        guard let old else { return try add(url, kind: .pdf) }
        var entry = try makeEntry(url, kind: old.kind)
        entry.id = id
        lock.withLock {
            stopAccessLocked(id)
            if let i = entries.firstIndex(where: { $0.id == id }) { entries[i] = entry }
            saveLocked()
        }
        return entry
    }

    public func remove(id: UUID) {
        lock.withLock {
            stopAccessLocked(id)
            entries.removeAll { $0.id == id }
            saveLocked()
        }
    }

    /// Resolves a bookmark and checks the folder is still usable. Refreshes stale bookmarks.
    public func resolve(_ entry: FolderEntry) -> ResolvedFolder {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: entry.bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return ResolvedFolder(entry: entry, url: nil, problem: .unresolvable)
        }
        let started = lock.withLock { accessed[entry.id] != nil }
        let scoped = started || url.startAccessingSecurityScopedResource()
        defer { if !started && scoped { url.stopAccessingSecurityScopedResource() } }

        var result = ResolvedFolder(entry: entry, url: url, problem: Self.check(url))
        if result.problem == nil, stale || url.path != entry.lastKnownPath,
           let fresh = try? makeEntry(url, kind: entry.kind) {
            var updated = fresh; updated.id = entry.id
            lock.withLock {
                if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = updated; saveLocked() }
            }
            result.entry = updated
        }
        return result
    }

    public func resolveAll(_ kind: FolderKind) -> [ResolvedFolder] {
        entries(of: kind).map(resolve)
    }

    /// Starts scoped access (idempotent). Returns the URL, or nil if the folder is unreachable.
    @discardableResult
    public func startAccess(_ entry: FolderEntry) -> URL? {
        let r = resolve(entry)
        guard r.isReachable, let url = r.url else { stopAccess(id: entry.id); return nil }
        lock.withLock {
            if accessed[entry.id]?.path != url.path {
                if let old = accessed[entry.id] { old.stopAccessingSecurityScopedResource() }
                _ = url.startAccessingSecurityScopedResource()
                accessed[entry.id] = url
            }
        }
        return url
    }

    public func stopAccess(id: UUID) { lock.withLock { stopAccessLocked(id) } }

    public func stopAllAccess() {
        lock.withLock { for id in Array(accessed.keys) { stopAccessLocked(id) } }
    }

    // MARK: - Internals

    private func makeEntry(_ url: URL, kind: FolderKind) throws -> FolderEntry {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderBookmarksError.notADirectory
        }
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            return FolderEntry(id: UUID(), kind: kind, bookmark: data, lastKnownPath: url.path)
        } catch {
            throw FolderBookmarksError.bookmarkFailed(error.localizedDescription)
        }
    }

    static func check(_ url: URL) -> ResolvedFolder.Problem? {
        if url.path.contains("/.Trash/") || url.path.hasSuffix("/.Trash") { return .inTrash }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return .missing }
        guard isDir.boolValue else { return .notADirectory }
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return .noPermission }
        return nil
    }

    private func stopAccessLocked(_ id: UUID) {
        if let url = accessed.removeValue(forKey: id) { url.stopAccessingSecurityScopedResource() }
    }

    private func saveLocked() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: storeURL, options: .atomic) }
    }
}
