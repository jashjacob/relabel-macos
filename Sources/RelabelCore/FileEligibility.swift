import Foundation

public enum FileEligibility {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    /// macOS names screenshots "Screenshot 2026-11-19 at 2.03.04 PM.png". The space before AM/PM is
    /// U+202F (narrow no-break space) on recent macOS, so every kind of space is normalised first.
    public static func isScreenshotName(_ name: String) -> Bool {
        let n = name.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        let pattern = #"^(Screenshot|Screen Shot) \d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2}( ?[AP]M)?( \(\d+\))?\.(png|jpe?g|heic)$"#
        return n.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// What a new file in a watched folder counts as, or nil if it must be ignored
    /// (hidden files, partial downloads, screen recordings, anything else).
    public static func kind(forFileNamed name: String, in folder: FolderKind) -> FileKind? {
        guard !name.hasPrefix(".") else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        if partialExtensions.contains(ext) { return nil }
        switch folder {
        case .screenshots: return isScreenshotName(name) ? .screenshot : nil
        case .pdf: return ext == "pdf" ? .pdf : nil
        }
    }

    /// For files the user drops on Relabel: any image or PDF.
    public static func kindForDropped(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) || ["tiff", "tif", "gif", "webp", "bmp"].contains(ext) { return .screenshot }
        return nil
    }
}
