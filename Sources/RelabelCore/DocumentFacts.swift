import Foundation
import NaturalLanguage

/// Rule-based names for equipment nameplates, invoices and company documents with an upper-case heading.
extension RuleNamer {
    // MARK: Nameplates

    /// "Kestrel DRIVE UNIT+FAN KIT-B SN 880044556677112" from a photo of a label with MODEL and SN lines.
    static func nameplate(_ text: String, length: NameLength) -> String? {
        let flat = text.replacingOccurrences(of: OCRRows.separator, with: " ")
        guard let serial = firstMatch(#"(?:\bS/?N\b|Serial(?: No\.?| Number)?)\s*[:#.]?\s*(?:\(SN\)\s*)?([A-Z0-9][A-Z0-9\-]{3,}(?: \d{4,})?)"#, in: flat, options: [.caseInsensitive]),
              serial.filter(\.isNumber).count >= 6 else { return nil }
        let serialText = serial.uppercased()
        let model = firstMatch(#"(?:\bMODEL|\bTYPE|\bM)\s*:\s*([A-Z0-9][A-Z0-9 +/\-\.]{3,40}?)\s*(?:\n|$|\bSN\b|\bVERS)"#, in: flat)
            .map { limitWords(cleanName($0.replacingOccurrences(of: "/", with: " ")), 6) }
        let hasVersion = flat.range(of: #"\bVERS(?:ION)?\b"#, options: .regularExpression) != nil
        guard model != nil || hasVersion else { return nil }
        var brand: String?
        if let first = flat.split(whereSeparator: \.isNewline).first {
            let token = String(first.split(separator: " ").first ?? "").filter(\.isLetter)
            let ok = token.count >= 3 && token.count <= 12 && (token == token.uppercased() || token == token.capitalized)
            if ok { brand = token == token.uppercased() && token.count > 4 ? token.capitalized : token }
        }
        let head = [brand, model].compactMap { $0 }.joined(separator: " ")
        let base = head.isEmpty ? "Nameplate" : head
        return length == .short ? base : "\(base) SN \(serialText)"
    }

    // MARK: Invoices

    static let companyWords = #"\b(?:Ltd|LTD|Limited|LIMITED|LLC|Inc|INC|Corp|Corporation|Pvt|PVT|GmbH|Co|Company|Services|Plumbing|Industries|Enterprises)\b"#

    /// "ACME Plumbing invoice INV-20481": a company line, the word invoice (or quotation, receipt) and its number.
    static func invoice(_ text: String) -> String? {
        let kinds = "Invoice|Tax Invoice|Quotation|Quote|Receipt|Purchase Order|PO|Delivery Note|DELIVERY NOTE|Delivery Challan|DELIVERY CHALLAN"
        // A letter that merely mentions a purchase order is named by its subject, not by the order number.
        if text.range(of: #"(?im)^\s*(?:Sub|Subject)\s*:"#, options: .regularExpression) != nil { return nil }
        guard let re = try? NSRegularExpression(pattern: "\\b(\(kinds))\\s*(?:(?i:No\\.?|Nr\\.?|Number)|#)?\\s*[:#]?\\s*((?=[A-Z0-9\\-/]*\\d)[A-Z0-9][A-Z0-9\\-/]{2,})"),
              let company = companyLine(in: text) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var kind = ns.substring(with: m.range(at: 1)).lowercased()
        if kind == "po" { kind = "PO" }
        let id = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "/", with: "-")
        return "\(company) \(kind) \(id)"
    }

    // MARK: Tenders

    /// "Tender TW202400731905" from a line like "Tender No: ORG/UNIT/TW202400731905 dated 29-11-2022".
    static func tender(_ text: String) -> String? {
        // A letter that only refers to a tender is not the tender; and the number has letters ("TW2024...", not "2024-25").
        guard text.range(of: #"(?i)\bDear\s+(?:Sir|Madam|Mr|Ms|Sirs)"#, options: .regularExpression) == nil,
              let line = firstMatch(#"Tender\s*(?:No\.?|Number)\s*:?\s*([^\n]+)"#, in: text, options: [.caseInsensitive]) else { return nil }
        let head = line.components(separatedBy: " dated").first ?? line
        let ids = head.split(whereSeparator: { $0 == "/" || $0 == " " }).map(String.init)
            .filter { $0.filter(\.isNumber).count >= 6 && $0.contains(where: \.isLetter) && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
        return ids.last.map { "Tender \($0)" }
    }

    // MARK: Letters

    /// "Northfield Aero site visit request for engineers": a letter with a "Dear Sir" greeting and a Sub: line.
    static func letter(_ text: String, length: NameLength) -> String? {
        guard text.range(of: #"(?i)\bDear\s+(?:Sir|Madam|Mr|Ms|Sirs)"#, options: .regularExpression) != nil,
              var subject = firstMatch(#"(?im)^\s*(?:Sub|Subject)\s*[:\-]\s*(.+)$"#, in: text) else { return nil }
        subject = subject.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let words = subject.split(separator: " ").count
        guard subject.range(of: #"(?i)^ref\b|\bno\s*:"#, options: .regularExpression) == nil else { return nil }
        guard (2...25).contains(words) else { return nil }
        let plain = subject.replacingOccurrences(of: "/", with: " and ")
        let short = limitWords(cleanName(plain), length == .short ? 5 : 8)
        // "Site Visit Request For Engineers" in Title Case reads better as a sentence: lower the Capitalised words.
        let body = short.split(separator: " ").map { w -> String in
            let x = String(w)
            return x.count > 1 && x == x.capitalized ? x.lowercased() : x
        }.joined(separator: " ")
        let line = text.split(whereSeparator: \.isNewline).prefix(10).joined(separator: "\n")
        let company = text.range(of: #"(?m)^\s*(?:M/s|Messrs)"#, options: .regularExpression) != nil ? companyLine(in: line) : nil
        return company.map { "\($0) \(body)" } ?? Sanitizer.sentenceCased(body)
    }

    // MARK: Headings

    /// "Orbit Automation payment terms": a company name followed by an upper-case heading made of real words.
    static func heading(_ text: String) -> String? {
        let all = text.split(whereSeparator: \.isNewline).map { String($0).components(separatedBy: OCRRows.separator).last(where: { !$0.isEmpty }) ?? "" }
        let first = Array(all.prefix(7))
        func isCaps(_ l: String) -> Bool { l.contains(where: \.isLetter) && l == l.uppercased() && l.allSatisfy { $0.isLetter || $0 == " " || $0 == "&" } }
        func headingLike(_ l: String) -> Bool {
            let w = l.split(separator: " ")
            return isCaps(l) && (2...6).contains(w.count) && w.allSatisfy { $0.count >= 2 }
        }
        // "ORBIT AUTOMATION" directly above "PAYMENT TERMS": an upper-case company then an upper-case heading.
        for i in 0..<max(0, first.count - 1) where isCaps(first[i]) && first[i].split(separator: " ").count <= 3 && headingLike(first[i + 1]) {
            guard knownWords(first[i + 1]) else { return nil }
            return "\(titleCase(first[i])) \(first[i + 1].lowercased())"
        }
        // An upper-case heading plus a company line with Limited, Ltd, Inc...
        guard let h = first.first(where: headingLike), knownWords(h), let company = companyLine(in: first.joined(separator: "\n")) else { return nil }
        return "\(company) \(h.lowercased())"
    }

    // MARK: Helpers

    /// A line like "Riverbend Water Works Limited, ELMSTEAD" becomes "Riverbend Water Works".
    static func companyLine(in text: String) -> String? {
        for l in text.split(whereSeparator: \.isNewline).prefix(8).map(String.init) {
            let cell = l.components(separatedBy: OCRRows.separator).last(where: { $0.range(of: companyWords, options: .regularExpression) != nil }) ?? ""
            guard !cell.isEmpty, let r = cell.range(of: companyWords, options: .regularExpression) else { continue }
            var name = String(cell[..<r.lowerBound]).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if let m = name.range(of: #"^(?i:M/s|Messrs)\.?\s+"#, options: .regularExpression) { name.removeSubrange(m) }
            if name.isEmpty { continue }
            // Services/Plumbing/Industries are part of the name; legal suffixes are not.
            let w = String(cell[r])
            if ["Services", "Plumbing", "Industries", "Enterprises"].contains(w) { name += " " + w }
            let words = name.split(separator: " ")
            guard (1...5).contains(words.count), let f = name.first, f.isUppercase, !name.contains(where: \.isNumber) else { continue }
            return name == name.uppercased() ? titleCase(name) : name
        }
        return nil
    }

    static func titleCase(_ s: String) -> String {
        s.split(separator: " ").map { w -> String in
            let x = String(w)
            return x.count <= 3 ? x : x.prefix(1) + x.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Every word of 4+ letters is a real English word, so a cropped "SPECTION AND REPAIRS" is not trusted.
    static func knownWords(_ line: String) -> Bool {
        guard let emb = NLEmbedding.wordEmbedding(for: .english) else { return true }
        return line.lowercased().split(separator: " ").filter { $0.count >= 4 }.allSatisfy { emb.contains(String($0)) }
    }

    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1,
              m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
}
