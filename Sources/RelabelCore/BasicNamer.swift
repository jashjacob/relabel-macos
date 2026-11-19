import Foundation

/// Naming without the model: picks the most informative line of recognized text, else a label.
/// Every length gives the same name.
public enum BasicNamer {
    public static func name(for ctx: FileContext, prefs: NamingPreferences) -> NamingResult {
        var title: String?
        switch ctx.kind {
        case .pdf:
            if let t = ctx.pdfTitle, isUsefulTitle(t) { title = t }
            title = title ?? bestLines(in: ctx.text, maxWords: 8)
            title = title ?? "PDF document"
        case .screenshot:
            title = bestLines(in: ctx.text, maxWords: 8)
            if title == nil {
                title = ctx.labels.first(where: { !["screenshot", "document", "text"].contains($0) }).map { "Screenshot of \($0)" } ?? "Screenshot"
            }
        }
        var out = title ?? "Untitled"
        let category = guessCategory(ctx)
        if ctx.kind == .pdf, ["invoice", "statement", "contract", "report", "manual"].contains(category),
           !out.localizedCaseInsensitiveContains(category) {
            out += " \(category)"
        }
        if ctx.kind == .screenshot, prefs.includeAppName, let app = ctx.appName, !out.localizedCaseInsensitiveContains(app) {
            out += " in \(app)"
        }
        return NamingResult(title: out, category: category, source: .fallback)
    }

    static func isUsefulTitle(_ t: String) -> Bool {
        let l = t.lowercased()
        if l.count < 4 || l.hasPrefix("untitled") || l.hasPrefix("microsoft word") || l.hasPrefix("document") && l.count < 12 { return false }
        if l.hasSuffix(".pdf") || l.hasSuffix(".docx") || l.hasSuffix(".indd") { return false }
        return true
    }

    /// First line (or two) that reads like a heading or sentence, not a date, URL, number or UI fragment.
    static func bestLines(in text: String, maxWords: Int) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let good = lines.filter(isMeaningful)
        guard let first = good.first else { return nil }
        var words = first.split(separator: " ").map(String.init)
        if words.count < 3, good.count > 1 { words += good[1].split(separator: " ").map(String.init) }
        return words.prefix(maxWords).joined(separator: " ")
    }

    static func isMeaningful(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard words.count >= 2, line.count >= 8, line.count <= 90 else { return false }
        let letters = line.filter(\.isLetter).count
        guard Double(letters) / Double(line.count) > 0.65 else { return false }
        let l = line.lowercased()
        if l.contains("http") || l.contains("www.") || l.contains("@") { return false }
        if l.range(of: #"^\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4}"#, options: .regularExpression) != nil { return false }
        if l.hasPrefix("page ") { return false }
        return true
    }

    static func guessCategory(_ ctx: FileContext) -> String {
        let t = (ctx.text + " " + ctx.labels.joined(separator: " ")).lowercased()
        let table: [(String, [String])] = [
            ("invoice", ["invoice", "amount due", "bill to"]), ("statement", ["statement", "account balance"]),
            ("contract", ["agreement", "contract", "hereinafter"]), ("error", ["error", "failed", "exception"]),
            ("code", ["func ", "import ", "def ", "class "]), ("chart", ["chart", "graph"]),
            ("report", ["report", "summary", "quarter"]), ("manual", ["manual", "instructions", "installation"]),
        ]
        for (cat, keys) in table where keys.contains(where: t.contains) { return cat }
        return ctx.kind == .pdf ? "document" : "website"
    }
}
