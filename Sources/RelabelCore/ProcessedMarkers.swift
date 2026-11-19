import Foundation

/// Remembers which files Relabel has handled, keyed by inode so a renamed file isn't picked up again.
public final class ProcessedMarkers: @unchecked Sendable {
    public enum Outcome: String, Codable, Sendable { case renamed, kept }
    struct Entry: Codable { var name: String; var time: Date; var outcome: Outcome }
    struct Store: Codable { var files: [String: Entry] = [:]; var watchStart: [String: Date] = [:] }

    private let storeURL: URL
    private let lock = NSLock()
    private var store = Store()

    public init(storeURL: URL = AppSupport.directory.appendingPathComponent("processed.json")) {
        self.storeURL = storeURL
        if let d = try? Data(contentsOf: storeURL) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(Store.self, from: d) { store = s }
        }
    }

    public func isProcessed(_ url: URL) -> Bool {
        guard let k = FileIdentity.key(url) else { return false }
        return lock.withLock { store.files[k] != nil }
    }

    public func mark(_ url: URL, _ outcome: Outcome) {
        guard let k = FileIdentity.key(url) else { return }
        lock.withLock {
            store.files[k] = Entry(name: url.lastPathComponent, time: Date(), outcome: outcome)
            saveLocked()
        }
    }

    public func unmark(_ url: URL) {
        guard let k = FileIdentity.key(url) else { return }
        lock.withLock { store.files[k] = nil; saveLocked() }
    }

    /// When Relabel started watching this folder; only files created after this are named.
    public func watchStart(for folderKey: String, now: Date = Date()) -> Date {
        lock.withLock {
            if let d = store.watchStart[folderKey] { return d }
            store.watchStart[folderKey] = now; saveLocked()
            return now
        }
    }

    private func saveLocked() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(store) { try? d.write(to: storeURL, options: .atomic) }
    }
}
