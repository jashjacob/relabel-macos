import Foundation

public enum SuggestedFolders {
    /// The folder macOS saves screenshots to (`defaults read com.apple.screencapture location`), else ~/Desktop.
    public static func screenshotLocation(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.screencapture"),
                                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let raw = defaults?.string(forKey: "location"), !raw.isEmpty {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return home.appendingPathComponent("Desktop")
    }

    public static func downloads(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Downloads")
    }
}
