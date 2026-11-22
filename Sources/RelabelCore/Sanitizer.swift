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

    /// Capitalises the first letter when the model started with a lower case word.
    public static func sentenceCased(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }

    private static let shortWords: Set<String> = ["THE", "AND", "FOR", "ALL", "NEW", "OUR", "USE", "NOT", "ARE", "BUT", "YOU",
        "ANY", "CAN", "HAS", "WAS", "ONE", "TWO", "OUT", "OFF", "NOW", "MAY", "PER", "VIA", "WHO", "HOW", "WHY", "OF", "TO",
        "IN", "ON", "AT", "BY", "AN", "IS", "IT", "AS", "OR", "NO", "IF", "SO", "DO", "UP", "WE", "BE", "MY", "ME"]

    /// The model tends to lower-case acronyms ("Cnc"). Restore ones written in capitals in the source text.
    /// Inside ordinary sentences any 2-5 letter capitals count. In ALL CAPS lines (headings) only 3-letter words that
    /// aren't common words count, or words repeated at least twice, so "SCOPE OF WORK" doesn't turn "of" into "OF".
    public static func restoreAcronyms(_ title: String, source: String) -> String {
        var acronyms: [String: String] = [:]
        var capsLineCounts: [String: Int] = [:]
        for line in source.split(whereSeparator: \.isNewline) {
            let mixed = line.contains(where: \.isLowercase)
            for raw in line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let w = String(raw)
                guard (2...5).contains(w.count), w == w.uppercased(), w.filter(\.isLetter).count >= 2 else { continue }
                if mixed {
                    if !shortWords.contains(w) { acronyms[w.lowercased()] = w }
                } else {
                    capsLineCounts[w, default: 0] += 1
                }
            }
        }
        for (w, n) in capsLineCounts where !shortWords.contains(w) && (w.count == 3 || n >= 2) {
            acronyms[w.lowercased()] = acronyms[w.lowercased()] ?? w
        }
        guard !acronyms.isEmpty else { return title }
        return title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let w = String(word)
            if let a = acronyms[w.lowercased()], w != a, w == w.lowercased() || w == w.capitalized { return a }
            return w
        }.joined(separator: " ")
    }

    /// The model sometimes lower-cases place and brand names. Restore words the source writes with a capital in
    /// the middle of a line (never only at the start of a line or cell) and never in lower case.
    public static func restoreProperNames(_ title: String, source: String) -> String {
        var caps: [String: String] = [:]
        var lowers = Set<String>()
        for line in source.split(whereSeparator: \.isNewline) {
            for cell in line.components(separatedBy: " | ") {
                let words = cell.split(whereSeparator: { !$0.isLetter }).map(String.init)
                for (i, w) in words.enumerated() where w.count >= 3 {
                    if w == w.lowercased() { lowers.insert(w) }
                    else if i > 0, w == w.capitalized, !shortWords.contains(w.uppercased()) { caps[w.lowercased()] = w }
                }
            }
        }
        // Company names in ALL CAPS headings ("NORTHWIND TRADERS"): a word that follows a capitalised word in the
        // title and follows the same word in an all-caps line gets a capital too.
        var pairs = Set<String>()
        for line in source.split(whereSeparator: \.isNewline) where !line.contains(where: \.isLowercase) {
            let ws = line.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
            for k in 1..<max(ws.count, 1) where ws[k].count >= 3 { pairs.insert(ws[k - 1] + " " + ws[k]) }
        }
        guard !caps.isEmpty || !pairs.isEmpty else { return title }
        var out: [String] = []
        for (i, word) in title.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            let w = String(word)
            if i > 0, w == w.lowercased(), let c = caps[w], !lowers.contains(w) { out.append(c); continue }
            if i > 0, w == w.lowercased(), w.count >= 3, let prev = out.last, prev.first?.isUppercase == true,
               pairs.contains(prev.lowercased() + " " + w), !lowers.contains(w) { out.append(w.capitalized); continue }
            out.append(w)
        }
        return out.joined(separator: " ")
    }

    private static let keepShouting: Set<String> = ["EBITDA", "HTTPS", "GSTIN", "SWIFT", "IFSC"]

    /// ALL CAPS company and person names the model copied ("ACME AUTOMATION SYSTEMS", "LARSEN") become Title Case.
    /// Short acronyms (CNC, HVAC) stay. Legal suffixes like "PVT.LTD" are dropped.
    public static func calmCaps(_ title: String) -> String {
        let t = title.replacingOccurrences(of: #"(?i)\s*\bPvt\.?\s*Ltd\.?"#, with: "", options: .regularExpression)
        let words = t.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        func shouts(_ w: String) -> Bool { w == w.uppercased() && !w.contains(where: \.isNumber) && w.filter(\.isLetter).count >= 4 && !keepShouting.contains(w) }
        let many = words.filter(shouts).count >= 2
        return words.map { w in
            guard shouts(w), w.filter(\.isLetter).count >= 5 || many else { return w }
            return w.prefix(1) + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Codes with digits ("D0457") the model wrote in lower case get the case the source has.
    public static func restoreIdentifiers(_ title: String, source: String) -> String {
        var ids: [String: String] = [:]
        for raw in source.split(whereSeparator: { $0.isWhitespace || "#:,;()|".contains($0) }) {
            let w = String(raw)
            if w.contains(where: \.isNumber), w.contains(where: \.isLetter) { ids[w.lowercased()] = w }
        }
        guard !ids.isEmpty else { return title }
        return title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let w = String(word)
            if let id = ids[w.lowercased()], w != id { return id }
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
