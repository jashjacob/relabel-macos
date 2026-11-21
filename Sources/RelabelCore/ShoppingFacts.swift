import Foundation

/// Rule-based names for screens with a clear pattern: hotel results and product pages.
/// Anything that doesn't match clearly returns nil and goes to the model as usual.
public enum RuleNamer {
    public struct Named: Sendable, Equatable { public var title: String; public var category: String }

    public static func name(for text: String, length: NameLength) -> Named? {
        if let f = ListingFacts.extract(from: text) { return Named(title: f.title(length: length), category: "listing") }
        if let t = hotel(text, length: length) { return Named(title: t, category: "listing") }
        if let t = product(text, length: length) { return Named(title: t, category: "website") }
        if let t = error(text, length: length) { return Named(title: t, category: "error") }
        if let t = nameplate(text, length: length) { return Named(title: t, category: "label") }
        if let t = invoice(text) { return Named(title: t, category: "invoice") }
        if let t = heading(text) { return Named(title: t, category: "document") }
        return nil
    }

    // MARK: Prices

    /// Lowest amount with a currency sign, as written (rupee sign misreads fixed). `.00` is dropped.
    static func cheapestPrice(in text: String, minDigits: Int = 1, firstOnly: Bool = false) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"([₹₴€£$¥·•])\s?(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+(?:\.\d{2})?)(?![\d,])"#) else { return nil }
        let ns = text as NSString
        var best: (v: Double, text: String)?
        var symbols: [String: Int] = [:]
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let sym = ns.substring(with: m.range(at: 1))
            let before = ns.substring(with: NSRange(location: max(0, m.range.location - 16), length: min(16, m.range.location))).lowercased()
            if ["over ", "above ", "under ", "save ", "off ", "min ", "minimum ", "orders "].contains(where: { before.contains($0) || before.hasSuffix($0.trimmingCharacters(in: .whitespaces)) }) { continue }   // thresholds and discounts
            var num = ns.substring(with: m.range(at: 2))
            let digits = num.filter(\.isNumber).count
            guard digits >= minDigits, let v = Double(num.replacingOccurrences(of: ",", with: "")), v > 0 else { continue }
            if num.hasSuffix(".00") { num.removeLast(3) }
            if !"·•".contains(sym) { symbols[sym == "₴" ? "₹" : sym, default: 0] += 1 }
            if best == nil || (!firstOnly && v < best!.v) { best = (v, num) }
        }
        guard let best, let sym = symbols.max(by: { $0.value < $1.value })?.key else { return nil }   // an amount needs a real currency sign
        return sym + best.text
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Hotels

    static func hotel(_ text: String, length: NameLength) -> String? {
        let lower = text.lowercased()
        guard lower.contains("per night") || lower.contains("/night") || lower.contains("a night") || lower.contains("/ night"),
              let price = cheapestPrice(in: text, minDigits: 2) else { return nil }
        let nameWords = #"\b(Hotel|Resort|Inn|Suites?|Lodge|Villa|Hostel|Spa|Residency|Homestay)\b"#
        let names = lines(text).compactMap { l -> String? in
            let first = l.components(separatedBy: OCRRows.separator)[0]
            guard first.range(of: nameWords, options: .regularExpression) != nil, first.count <= 60,
                  !first.lowercased().contains("hotels in"), !first.contains(where: \.isNumber) else { return nil }
            return cleanName(first)
        }
        var place: String?
        if let re = try? NSRegularExpression(pattern: #"(?:Hotels?|Stays|Resorts|Properties|Rooms) (?:in|near) ([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)?)"#) {
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) { place = ns.substring(with: m.range(at: 1)) }
        }
        if Set(names).count >= 2 {
            guard let place else { return nil }
            return length == .short ? "Hotels in \(place)" : "Hotels in \(place) from \(price) per night"
        }
        if let name = names.first {
            let n = limitWords(name, 7)
            return length == .short ? n : "\(n) \(price) per night"
        }
        return nil
    }

    // MARK: Products

    static func product(_ text: String, length: NameLength) -> String? {
        let lower = text.lowercased()
        let buy = ["add to cart", "add to bag", "add to basket", "buy now", "buy it now"]
        guard buy.contains(where: lower.contains), let price = cheapestPrice(in: text, firstOnly: true) else { return nil }
        let skip = ["ratings", "reviews", "delivery", "stars", "shipping", "in stock", "sold by", "free "]
        for l in lines(text).prefix(8) {
            let cell = l.components(separatedBy: OCRRows.separator)[0].trimmingCharacters(in: .whitespaces)
            let words = cell.split(separator: " ")
            let letters = cell.filter(\.isLetter).count
            guard words.count >= 2, cell.count >= 12, cell.count <= 90, Double(letters) / Double(cell.count) > 0.7,
                  !skip.contains(where: cell.lowercased().contains), !"₹₴€£$¥".contains(cell.first!) else { continue }
            let name = limitWords(cleanName(cell), 8)
            return length == .short ? name : "\(name) \(price)"
        }
        return nil
    }

    // MARK: Helpers

    /// Drops ratings, stars and other trailing junk after the name.
    static func cleanName(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "★" || ch == "☆" || ch == "(" || ch == "•" { break }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func limitWords(_ s: String, _ n: Int) -> String {
        let w = s.split(separator: " ")
        return w.count > n ? w.prefix(n).joined(separator: " ") : s
    }
}
