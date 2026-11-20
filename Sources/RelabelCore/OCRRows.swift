import Foundation

/// A piece of recognized text with its box. Coordinates are normalised, origin bottom left (Vision's convention).
public struct TextBox: Sendable, Equatable {
    public var text: String
    public var minX: Double, maxX: Double, minY: Double, maxY: Double
    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.text = text; self.minX = minX; self.maxX = maxX; self.minY = minY; self.maxY = maxY
    }
    var midY: Double { (minY + maxY) / 2 }
    var height: Double { maxY - minY }
}

/// Turns scattered OCR fragments into reading lines: pieces on the same row are joined left to right
/// with " | ", and short UI labels that repeat (Select, Select, Select) are kept once.
public enum OCRRows {
    public static let separator = " | "

    public static func lines(_ boxes: [TextBox]) -> [String] {
        let items = boxes.map { TextBox(text: $0.text.trimmingCharacters(in: .whitespaces), minX: $0.minX, maxX: $0.maxX, minY: $0.minY, maxY: $0.maxY) }
            .filter { !$0.text.isEmpty }
        var rows: [[TextBox]] = []
        for b in items.sorted(by: { $0.midY > $1.midY }) {            // top of the image first
            if let i = rows.lastIndex(where: { row in
                let ref = row[0]
                return abs(ref.midY - b.midY) < 0.5 * min(ref.height, b.height)
            }) { rows[i].append(b) } else { rows.append([b]) }
        }
        let lines = rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: separator) }
        return dropRepeatedLabels(lines)
    }

    /// A short label with no digits that shows up three or more times is interface chrome; keep the first.
    static func dropRepeatedLabels(_ lines: [String]) -> [String] {
        func key(_ s: String) -> String? {
            let cells = s.components(separatedBy: separator)
            guard cells.count == 1 else { return nil }
            let l = s.lowercased()
            let letters = l.filter(\.isLetter).count
            guard letters >= 2, s.count <= 24, !l.contains(where: \.isNumber) else { return nil }
            return l.filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces)
        }
        var counts: [String: Int] = [:]
        for l in lines { if let k = key(l) { counts[k, default: 0] += 1 } }
        var seen = Set<String>()
        return lines.filter { l in
            guard let k = key(l), counts[k, default: 0] >= 3 else { return true }
            return seen.insert(k).inserted
        }
    }
}
