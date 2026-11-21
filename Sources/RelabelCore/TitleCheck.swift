import Foundation

/// Sanity checks on a model-written title, so a bad one can be retried instead of used.
public enum TitleCheck {
    /// Words that describe the interface or the capture, never the content.
    static let uiWords: Set<String> = ["select", "click", "button", "menu", "screen", "screenshot", "interface", "image", "picture", "tab", "window", "deals"]
    static let genericTitles: Set<String> = ["document", "file", "untitled", "text", "page", "pdf", "screenshot", "image", "photo"]

    public static func maxWords(_ length: NameLength) -> Int {
        switch length { case .short: 8; case .standard: 10; case .detailed: 12 }
    }

    /// Why the title isn't good enough, or nil when it is.
    public static func problem(_ title: String, length: NameLength, sourceText: String = "") -> String? {
        let words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let lower = Set(title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let source = Set(sourceText.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let always: Set<String> = ["select", "click", "deals"]
        if let w = lower.first(where: { always.contains($0) || (uiWords.contains($0) && !source.contains($0)) }) {
            return "it contains \"\(w)\", which describes the interface and not the content"
        }
        if words.count < 2 || genericTitles.contains(title.lowercased()) { return "it is too generic" }
        if words.count > maxWords(length) { return "it is too long" }
        return nil
    }

    /// Removes interface words that never belong in a name ("deals", "select") instead of rejecting the whole title.
    public static func stripped(_ title: String) -> String {
        let drop: Set<String> = ["select", "click", "deals"]
        let words = title.split(separator: " ").filter { !drop.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        return words.joined(separator: " ")
    }

    private static let connectives: Set<String> = ["for", "of", "in", "on", "at", "to", "and", "with", "by", "from", "the", "a", "an", "or", "between", "about"]

    /// Cuts a title that is still too long to the word limit, at the last natural break (before "for", "of", "and"...)
    /// so it doesn't end mid-phrase.
    public static func trimmed(_ title: String, length: NameLength) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let cap = maxWords(length)
        guard words.count > cap else { return title }
        var kept = Array(words.prefix(cap))
        if let i = kept.lastIndex(where: { connectives.contains($0.lowercased()) }), i >= 3 { kept = Array(kept.prefix(i)) }
        while kept.count > 2, let l = kept.last, connectives.contains(l.lowercased()) { kept.removeLast() }
        return kept.joined(separator: " ")
    }
}
