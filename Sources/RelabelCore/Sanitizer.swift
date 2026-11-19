import Foundation

public enum Sanitizer {
    public static let maxLength = 80
    private static let forbidden = CharacterSet(charactersIn: "/:\\\"*?<>|")
        .union(.controlCharacters).union(CharacterSet(charactersIn: "\u{201C}\u{201D}\u{2018}\u{2019}"))

    /// Strips characters that are unsafe in file names, collapses whitespace, caps the length.
    public static func cleanTitle(_ raw: String, maxLength: Int = Sanitizer.maxLength) -> String {
        var s = String(raw.unicodeScalars.filter { !forbidden.contains($0) })
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while let f = s.first, f == "." || f == "-" { s.removeFirst() }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ". ,;"))
        if s.count > maxLength {
            s = String(s.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Capitalises the first letter when the model returned all lower case. Leaves mixed-case names alone.
    public static func sentenceCased(_ s: String) -> String {
        guard s == s.lowercased(), let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// The model tends to lower-case acronyms ("Cnc"). Restore ones written in capitals inside normal sentences
    /// of the source text (not from ALL CAPS headings, where every word is capitals).
    public static func restoreAcronyms(_ title: String, source: String) -> String {
        var acronyms: [String: String] = [:]
        for line in source.split(whereSeparator: \.isNewline) where line.contains(where: \.isLowercase) {
            for raw in line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let w = String(raw)
                if (2...5).contains(w.count), w == w.uppercased(), w.filter(\.isLetter).count >= 2 {
                    acronyms[w.lowercased()] = w
                }
            }
        }
        guard !acronyms.isEmpty else { return title }
        return title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let w = String(word)
            if let a = acronyms[w.lowercased()], w != a, w == w.lowercased() || w == w.capitalized { return a }
            return w
        }.joined(separator: " ")
    }

    public static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Title plus optional date (from the file's creation date), capped at 80 characters in total.
    public static func baseName(title: String, date: Date, style: DateStyle, calendar: Calendar = .current) -> String {
        let d = dateString(date, calendar: calendar)
        switch style {
        case .none: return cleanTitle(title)
        case .atStart: return d + " " + cleanTitle(title, maxLength: maxLength - d.count - 1)
        case .atEnd: return cleanTitle(title, maxLength: maxLength - d.count - 1) + " " + d
        }
    }

    /// Picks a name that doesn't exist yet: "Name.ext", then "Name 2.ext", "Name 3.ext", ...
    /// `isTaken` is case-insensitive-aware by default (macOS volumes usually are).
    public static func uniqueURL(directory: URL, base: String, ext: String,
                                 isTaken: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let suffix = ext.isEmpty ? "" : "." + ext
        var candidate = directory.appendingPathComponent(base + suffix)
        var n = 2
        while isTaken(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(n)\(suffix)")
            n += 1
        }
        return candidate
    }
}
