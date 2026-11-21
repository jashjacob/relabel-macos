import Foundation

/// Facts pulled out of recognized text with plain rules, before the model sees it. Right now: travel listings
/// (flight results) where the model tends to name the brand and miss the route and price.
public struct ListingFacts: Sendable, Equatable {
    public var carrier: String?
    public var from: String
    public var to: String
    public var fromCity: String?
    public var toCity: String?
    public var cheapest: String?        // with currency symbol, e.g. "₹10,487"

    var routeText: String { "\(fromCity ?? from) to \(toCity ?? to)" }

    /// One line for the prompt.
    public var promptLine: String {
        var s = "Facts found in the text: route \(routeText) (\(from) to \(to))"
        if let carrier { s += ", airline \(carrier)" }
        if let cheapest { s += ", cheapest price \(cheapest)" }
        return s + ". Use them in the title."
    }

    /// A name built only from the facts, for when the model leaves them out.
    public func title(length: NameLength) -> String {
        let who = carrier.map { $0 + " " } ?? ""
        switch length {
        case .short: return "\(who)flights \(from) to \(to)"
        case .standard: return "\(who)flights \(routeText)" + (cheapest.map { " from \($0)" } ?? "")
        case .detailed: return "\(who)flights \(routeText) (\(from) to \(to))" + (cheapest.map { " from \($0)" } ?? "")
        }
    }

    /// True when the title mentions the route (codes or city names).
    public func isReflected(in title: String) -> Bool {
        let t = title.lowercased()
        return t.contains(from.lowercased()) && t.contains(to.lowercased())
            || (fromCity.map { t.contains($0.lowercased()) } ?? false) && (toCity.map { t.contains($0.lowercased()) } ?? false)
    }

    // MARK: Extraction

    public static func extract(from text: String) -> ListingFacts? {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        let hasTimes = text.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
        let isCode: (String) -> Bool = { $0.count == 3 && $0.allSatisfy { $0.isUppercase && $0.isLetter } }

        // Route: rows whose first and last cell are airport codes (ISK | 1 stop BLR | MAA); the most common pair wins.
        var pairs: [String: Int] = [:]
        for l in lines {
            let cells = l.components(separatedBy: OCRRows.separator).map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count >= 2, isCode(cells[0]), isCode(cells[cells.count - 1]), cells[0] != cells[cells.count - 1] {
                pairs[cells[0] + ">" + cells[cells.count - 1], default: 0] += 1
            }
        }
        var from: String?, to: String?, fromCity: String?, toCity: String?
        if hasTimes, let best = pairs.max(by: { $0.value < $1.value }) {
            let p = best.key.split(separator: ">").map(String.init); from = p[0]; to = p[1]
        }
        // Header form: "Nashik (ISK) - Chennai (MAA)".
        if let re = try? NSRegularExpression(pattern: #"([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)?)\s*\(([A-Z]{3})\)"#) {
            for l in lines.prefix(6) {
                let ns = l as NSString
                let m = re.matches(in: l, range: NSRange(location: 0, length: ns.length))
                if m.count >= 2 {
                    let a = (ns.substring(with: m[0].range(at: 1)), ns.substring(with: m[0].range(at: 2)))
                    let b = (ns.substring(with: m[1].range(at: 1)), ns.substring(with: m[1].range(at: 2)))
                    if from == nil || (from == a.1 && to == b.1) { from = a.1; to = b.1; fromCity = a.0; toCity = b.0 }
                    break
                }
            }
        }
        guard let from, let to else { return nil }

        // Cheapest price: an amount with a currency mark. OCR often reads the rupee sign as a hryvnia sign or a dot.
        var best: (value: Double, text: String)?
        var symbols: [String: Int] = [:]
        if let re = try? NSRegularExpression(pattern: #"([₹₴€£$¥·•])\s?(\d{1,3}(?:,\d{3})+|\d{3,6})(?!\d)"#) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let sym = ns.substring(with: m.range(at: 1)), num = ns.substring(with: m.range(at: 2))
                guard let v = Double(num.replacingOccurrences(of: ",", with: "")) else { continue }
                if !"·•".contains(sym) { symbols[sym == "₴" ? "₹" : sym, default: 0] += 1 }
                if best == nil || v < best!.value { best = (v, num) }
            }
        }
        let symbol = symbols.max(by: { $0.value < $1.value })?.key ?? ""
        let cheapest = best.map { symbol + $0.text }

        // Carrier: the first short, letters-only line (before the first row of times).
        var carrier: String?
        for l in lines.prefix(4) {
            let words = l.split(separator: " ")
            if (1...3).contains(words.count), l.allSatisfy({ $0.isLetter || $0 == " " }), !isCode(l),
               !["select", "sort", "stops", "best", "cheapest", "fastest", "direct"].contains(l.lowercased()) { carrier = l; break }
            if l.contains(":") { break }
        }
        return ListingFacts(carrier: carrier, from: from, to: to, fromCity: fromCity, toCity: toCity, cheapest: cheapest)
    }
}
