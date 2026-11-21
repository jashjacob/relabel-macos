import Foundation

/// Rule-based names for error screens: Python tracebacks, Xcode build errors, JavaScript, Rust and shell errors.
extension RuleNamer {
    static func error(_ text: String, length: NameLength) -> String? {
        let flat = text.replacingOccurrences(of: OCRRows.separator, with: " ")
        let lines = flat.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        func tidy(_ s: String) -> String {
            let cleaned = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\u{2018}", with: "").replacingOccurrences(of: "\u{2019}", with: "")
                .replacingOccurrences(of: "\u{201C}", with: "").replacingOccurrences(of: "\u{201D}", with: "")
                .replacingOccurrences(of: "`", with: "")
            return limitWords(cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .:;,")), length == .short ? 6 : 9)
        }
        func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

        // Python: a traceback ending in "KeyError: 'amount'".
        if flat.contains("Traceback (most recent call last)"),
           let errLine = lines.last(where: { $0.range(of: #"^[A-Z][A-Za-z]*(?:Error|Exception)\b"#, options: .regularExpression) != nil }) {
            let parts = errLine.split(separator: ":", maxSplits: 1).map(String.init)
            let type = parts[0].trimmingCharacters(in: .whitespaces)
            let message = parts.count > 1 ? tidy(parts[1]) : ""
            var title = "Python \(type)" + (message.isEmpty ? "" : " \(message)")
            if length != .short, let file = firstMatch(#"File "([^"]+?)(?:\.py)?",\s*line"#, in: flat) {
                title += " in " + (file as NSString).lastPathComponent
            }
            return title
        }
        // Xcode / Swift compiler messages.
        let swiftErrors = #"^(Cannot find|Use of unresolved identifier|No such module|Value of type|Missing argument|Cannot convert|Type '.*' has no member|Undefined symbol|Expected|Call can throw|Initializer|Extra argument)"#
        if let msg = lines.first(where: { $0.range(of: swiftErrors, options: .regularExpression) != nil }),
           flat.contains("Xcode") || flat.contains(".swift") || flat.contains("Build Failed") {
            return "Xcode error " + lowerFirst(tidy(msg))
        }
        // JavaScript / Node.
        if let line = lines.first(where: { $0.range(of: #"^(?:Uncaught )?(?:Type|Reference|Syntax|Range)Error\s*:"#, options: .regularExpression) != nil }) {
            return "JavaScript " + tidy(line.replacingOccurrences(of: "Uncaught ", with: "")).replacingOccurrences(of: ":", with: "")
        }
        // Rust: error[E0382]: borrow of moved value.
        if let line = lines.first(where: { $0.range(of: #"^error\[E\d{4}\]:"#, options: .regularExpression) != nil }) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            return "Rust error " + (parts[0].dropFirst(6).dropLast(1)) + " " + lowerFirst(tidy(parts.count > 1 ? parts[1] : ""))
        }
        // Shell: "zsh: command not found: pnpm".
        if let cmd = firstMatch(#"(?:zsh|bash|sh): command not found: (\S+)"#, in: flat) ?? firstMatch(#"(?:zsh|bash|sh): (\S+): command not found"#, in: flat) {
            return "Terminal error command not found \(cmd)"
        }
        return nil
    }
}

/// A chat window: the contact's name is found by rules, the topic is left to the model.
public enum ChatFacts {
    /// "Priya Nair" above "online" (or "last seen today", "typing...").
    public static func contact(in text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).components(separatedBy: OCRRows.separator)[0].trimmingCharacters(in: .whitespaces) }
        let status = #"^(online|last seen.*|typing\.*|tap here for contact info|click here for contact info|active now|active \d+ \w+ ago)$"#
        for i in 0..<max(0, min(lines.count, 6) - 1) {
            let name = lines[i]
            let words = name.split(separator: " ")
            guard (1...3).contains(words.count), words.allSatisfy({ $0.first?.isUppercase == true && $0.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "-" } }),
                  lines[i + 1].range(of: status, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            return name
        }
        return nil
    }

    public static func hint(contact: String) -> String {
        "This is a chat conversation with \(contact). Name it \"Chat with \(contact) about\" followed by the topic in a few words.\n"
    }

    /// Makes sure the title starts with the contact; otherwise falls back to "Chat with <name>".
    public static func finalTitle(_ title: String, contact: String) -> String {
        for name in [contact, contact.split(separator: " ").first.map(String.init) ?? contact] {
            if let r = title.range(of: name, options: .caseInsensitive) { return title.replacingCharacters(in: r, with: name) }   // exact capitals
        }
        return "Chat with \(contact)"
    }
}
