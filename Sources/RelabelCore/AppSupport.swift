import Foundation

public enum AppSupport {
    /// ~/Library/Application Support/Relabel, or $RELABEL_SUPPORT_DIR (used by tests and the CLI).
    public static var directory: URL {
        if let o = ProcessInfo.processInfo.environment["RELABEL_SUPPORT_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Relabel", isDirectory: true)
    }
}

enum FileIdentity {
    /// "device:inode" - stable across renames on the same volume.
    static func key(_ url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let ino = a[.systemFileNumber] as? UInt64 else { return nil }
        let dev = (a[.systemNumber] as? UInt64) ?? 0
        return "\(dev):\(ino)"
    }
    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
