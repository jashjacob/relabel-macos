import Foundation

public enum NameQuality {
    /// True for names a camera, scanner, browser or screenshot tool made ("IMG_2041", "scan0001", "Document (3)").
    /// Everything else is treated as a name a person already chose and is left alone unless asked.
    public static func looksGenerated(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        let l = stem.lowercased()
        if l.isEmpty { return true }
        if FileEligibility.isScreenshotName(fileName) { return true }
        let rest = #"[\d()\-_ .:]*"#
        let patterns = [
            #"^(img|dsc|dscn|dscf|pxl|mvimg|image|photo|picture|scan|scanned|document|doc|untitled|download|file|new document|whatsapp image|screen shot|screenshot)[ _\-]*"# + rest + #"( at "# + rest + #"[ap]?m?)?$"#,
            #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            #"^[0-9a-f]{16,}$"#,
            #"^[\d\-_ ().]+$"#,
        ]
        for p in patterns where l.range(of: p, options: .regularExpression) != nil { return true }
        let letters = stem.filter(\.isLetter).count
        if Double(letters) / Double(stem.count) < 0.4 { return true }
        return false
    }
}

/// Dates inside names (YYYY-MM-DD at the start or end), so they can be moved or removed in one go.
public enum DateTokens {
    private static let startRE = #"^(\d{4}-\d{2}-\d{2})[ _\-]+(.+)$"#
    private static let endRE = #"^(.+?)[ _\-]+(\d{4}-\d{2}-\d{2})$"#

    public static func split(_ stem: String) -> (date: String, rest: String)? {
        if let m = stem.firstMatch(startRE) { return (m[1], m[2]) }
        if let m = stem.firstMatch(endRE) { return (m[2], m[1]) }
        return nil
    }

    /// The same name with its date moved to `style`'s place, or nil if the name has no date or is already right.
    public static func restyle(stem: String, to style: DateStyle) -> String? {
        guard let (date, rest) = split(stem) else { return nil }
        let new: String
        switch style {
        case .none: new = Sanitizer.cleanTitle(rest)
        case .atStart: new = date + " " + Sanitizer.cleanTitle(rest, maxLength: Sanitizer.maxLength - 11)
        case .atEnd: new = Sanitizer.cleanTitle(rest, maxLength: Sanitizer.maxLength - 11) + " " + date
        }
        return new == stem || new.isEmpty ? nil : new
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { String(self[Range(m.range(at: $0), in: self)!]) }
    }
}
