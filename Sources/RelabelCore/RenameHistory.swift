import Foundation

public enum RenameSource: String, Codable, Sendable { case auto, drop, tidy, manual }

public struct HistoryRecord: Codable, Identifiable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case applied, undone }
    public var id: UUID
    public var time: Date
    public var oldPath: String
    public var newPath: String
    public var source: RenameSource
    public var folder: String
    public var kind: FileKind
    public var state: State
    /// Used to detect that the file changed or was replaced before an undo.
    public var inodeKey: String
    public var modified: Date
    /// What Relabel proposed, and a short context summary, kept for learning from the user's own renames.
    public var relabelName: String
    public var summary: String
    /// Set when the user edited the name Relabel gave (used to learn from corrections).
    public var userName: String? = nil

    public var oldName: String { (oldPath as NSString).lastPathComponent }
    public var newName: String { (newPath as NSString).lastPathComponent }
    public var oldURL: URL { URL(fileURLWithPath: oldPath) }
    public var newURL: URL { URL(fileURLWithPath: newPath) }
}

public enum HistoryError: Error, LocalizedError, Equatable {
    case movedOrRenamed(verb: String), changed(verb: String), nameTaken(verb: String), emptyName, unknownRecord
    public var errorDescription: String? {
        switch self {
        case .movedOrRenamed(let v): "Couldn't \(v). The file was moved or renamed."
        case .changed(let v): "Couldn't \(v). The file has changed since."
        case .nameTaken(let v): "Couldn't \(v). A file with that name already exists."
        case .emptyName: "Couldn't rename. The name can't be empty."
        case .unknownRecord: "Couldn't find that rename."
        }
    }
}

/// Every rename Relabel makes, with undo and redo. Only filenames change, so dates are untouched.
public final class RenameHistory: @unchecked Sendable {
    private let storeURL: URL
    private let lock = NSLock()
    private var records: [HistoryRecord] = []
    public static let maxRecords = 2000

    public init(storeURL: URL = AppSupport.directory.appendingPathComponent("history.json")) {
        self.storeURL = storeURL
        if let d = try? Data(contentsOf: storeURL) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            records = (try? dec.decode([HistoryRecord].self, from: d)) ?? []
        }
    }

    /// Newest first.
    public func recent(_ n: Int = 10) -> [HistoryRecord] { lock.withLock { Array(records.suffix(n).reversed()) } }
    public func all() -> [HistoryRecord] { lock.withLock { records } }
    public func record(id: UUID) -> HistoryRecord? { lock.withLock { records.first { $0.id == id } } }
    /// Files Relabel has named for the user (undone ones don't count).
    public var namedCount: Int { lock.withLock { records.filter { $0.state == .applied }.count } }

    public func add(_ r: HistoryRecord) {
        lock.withLock {
            records.append(r)
            if records.count > Self.maxRecords { records.removeFirst(records.count - Self.maxRecords) }
            saveLocked()
        }
    }

    /// Performs the rename and records it. Never overwrites: the caller supplies a free destination.
    @discardableResult
    public func rename(from old: URL, to new: URL, source: RenameSource, kind: FileKind,
                       relabelName: String, summary: String) throws -> HistoryRecord {
        guard let key = FileIdentity.key(old) else { throw HistoryError.movedOrRenamed(verb: "rename") }
        try FileManager.default.moveItem(at: old, to: new)   // fails if `new` exists
        let rec = HistoryRecord(id: UUID(), time: Date(), oldPath: old.path, newPath: new.path, source: source,
                                folder: old.deletingLastPathComponent().path, kind: kind, state: .applied,
                                inodeKey: key, modified: FileIdentity.modified(new) ?? Date(),
                                relabelName: relabelName, summary: summary)
        add(rec)
        return rec
    }

    @discardableResult
    public func undo(id: UUID) throws -> HistoryRecord { try move(id: id, forward: false) }
    @discardableResult
    public func redo(id: UUID) throws -> HistoryRecord { try move(id: id, forward: true) }

    /// The user edited the name by hand (inline in the menu). Keeps the extension, never overwrites.
    @discardableResult
    public func userRename(id: UUID, to typed: String) throws -> HistoryRecord {
        guard var rec = record(id: id) else { throw HistoryError.unknownRecord }
        let fm = FileManager.default
        guard rec.state == .applied, fm.fileExists(atPath: rec.newPath), FileIdentity.key(rec.newURL) == rec.inodeKey else {
            throw HistoryError.movedOrRenamed(verb: "rename")
        }
        let ext = rec.newURL.pathExtension
        var text = typed
        if !ext.isEmpty, text.lowercased().hasSuffix("." + ext.lowercased()) { text.removeLast(ext.count + 1) }
        let base = Sanitizer.cleanTitle(text)
        guard !base.isEmpty else { throw HistoryError.emptyName }
        let dest = rec.newURL.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? base : base + "." + ext)
        if dest.path == rec.newPath { return rec }
        if fm.fileExists(atPath: dest.path) {
            // Same file differing only by case is fine on a case-insensitive volume; anything else is a clash.
            guard FileIdentity.key(dest) == rec.inodeKey else { throw HistoryError.nameTaken(verb: "rename") }
            let temp = rec.newURL.deletingLastPathComponent().appendingPathComponent(".relabel-\(UUID().uuidString)")
            try fm.moveItem(at: rec.newURL, to: temp)
            try fm.moveItem(at: temp, to: dest)
        } else {
            try fm.moveItem(at: rec.newURL, to: dest)
        }
        rec.newPath = dest.path
        rec.userName = dest.lastPathComponent
        rec.modified = FileIdentity.modified(dest) ?? rec.modified
        lock.withLock {
            if let i = records.firstIndex(where: { $0.id == id }) { records[i] = rec }
            saveLocked()
        }
        return rec
    }

    private func move(id: UUID, forward: Bool) throws -> HistoryRecord {
        let verb = forward ? "redo" : "undo"
        guard var rec = record(id: id) else { throw HistoryError.unknownRecord }
        let (from, to) = forward ? (rec.oldURL, rec.newURL) : (rec.newURL, rec.oldURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { throw HistoryError.movedOrRenamed(verb: verb) }
        guard FileIdentity.key(from) == rec.inodeKey,
              let m = FileIdentity.modified(from), abs(m.timeIntervalSince(rec.modified)) < 1 else {
            throw HistoryError.changed(verb: verb)
        }
        guard !fm.fileExists(atPath: to.path) else { throw HistoryError.nameTaken(verb: verb) }
        try fm.moveItem(at: from, to: to)
        rec.state = forward ? .applied : .undone
        lock.withLock {
            if let i = records.firstIndex(where: { $0.id == id }) { records[i] = rec }
            saveLocked()
        }
        return rec
    }

    private func saveLocked() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(records) { try? d.write(to: storeURL, options: .atomic) }
    }
}
