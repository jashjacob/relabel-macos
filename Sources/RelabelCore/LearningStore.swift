import Foundation
import NaturalLanguage

/// One time the user changed a name Relabel gave. Stored only on this Mac.
public struct Correction: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID            // the history record it came from, so a second edit updates it
    public var time: Date
    public var kind: FileKind
    public var summary: String     // short text summary of the file's contents
    public var relabelName: String // without extension
    public var userName: String    // without extension
    public var appName: String?

    public init(id: UUID = UUID(), time: Date = Date(), kind: FileKind, summary: String, relabelName: String,
                userName: String, appName: String? = nil) {
        self.id = id; self.time = time; self.kind = kind; self.summary = summary
        self.relabelName = relabelName; self.userName = userName; self.appName = appName
    }
}

public enum StyleProfile {
    public static let minimumCorrections = 3

    /// "Your names tend to be one word, with the app name". Nil until there are enough corrections.
    public static func describe(_ corrections: [Correction]) -> String? {
        guard corrections.count >= minimumCorrections else { return nil }
        let names = corrections.map(\.userName)
        let wordCounts = names.map { $0.split(separator: " ").count }
        let mean = Double(wordCounts.reduce(0, +)) / Double(names.count)
        var parts: [String] = []
        switch mean {
        case ..<1.5: parts.append("one word")
        case ..<3.5: parts.append("two or three words")
        case ..<5.5: parts.append("a few words")
        default: parts.append("long and descriptive")
        }
        let half = Double(corrections.count) / 2
        if Double(corrections.filter { c in c.appName.map { c.userName.localizedCaseInsensitiveContains($0) } ?? false }.count) >= half {
            parts.append("with the app name")
        }
        if Double(names.filter { $0.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil }.count) >= half {
            parts.append("with the date")
        }
        let lower = names.filter { $0.first?.isLowercase == true }.count
        if Double(lower) >= Double(names.count) * 0.7 { parts.append("in lower case") }
        let relabelMean = Double(corrections.map { $0.relabelName.split(separator: " ").count }.reduce(0, +)) / Double(corrections.count)
        if mean <= relabelMean * 0.7 { parts.append("shorter than Relabel's") }
        else if mean >= relabelMean * 1.4 { parts.append("longer than Relabel's") }
        return "Your names tend to be " + parts.joined(separator: ", ")
    }
}

/// Keeps corrections (JSON in Application Support) and finds the most similar past ones with on-device embeddings.
public final class LearningStore: @unchecked Sendable {
    private let storeURL: URL
    private let lock = NSLock()
    private var items: [Correction] = []
    private let embedding: NLEmbedding?
    public static let maxItems = 1000

    public init(storeURL: URL = AppSupport.directory.appendingPathComponent("learning.json"),
                embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)) {
        self.storeURL = storeURL
        self.embedding = embedding
        if let d = try? Data(contentsOf: storeURL) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            items = (try? dec.decode([Correction].self, from: d)) ?? []
        }
    }

    public var hasEmbeddings: Bool { embedding != nil }
    public var all: [Correction] { lock.withLock { items } }
    public var count: Int { lock.withLock { items.count } }
    public var styleDescription: String? { StyleProfile.describe(all) }

    /// Returns true when this is the very first correction ever learned.
    @discardableResult
    public func add(_ c: Correction) -> Bool {
        lock.withLock {
            let first = items.isEmpty
            if let i = items.firstIndex(where: { $0.id == c.id }) { items[i] = c } else { items.append(c) }
            if items.count > Self.maxItems { items.removeFirst(items.count - Self.maxItems) }
            saveLocked()
            return first && items.count == 1
        }
    }

    /// Builds a correction from a history record the user renamed. Nil if there's nothing to learn.
    public static func correction(from r: HistoryRecord) -> Correction? {
        guard let user = r.userName else { return nil }
        let u = (user as NSString).deletingPathExtension
        let rel = (r.relabelName as NSString).deletingPathExtension
        guard !u.isEmpty, u != rel, u != (r.oldName as NSString).deletingPathExtension else { return nil }
        return Correction(id: r.id, time: Date(), kind: r.kind, summary: r.summary, relabelName: rel, userName: u, appName: r.appName)
    }

    public func forgetAll() {
        lock.withLock { items.removeAll(); saveLocked() }
    }

    public func remove(id: UUID) {
        lock.withLock { items.removeAll { $0.id == id }; saveLocked() }
    }

    /// The `limit` past corrections most like this file's text (3 to 5 is plenty for the prompt).
    public func similar(to summary: String, kind: FileKind, limit: Int = 4) -> [Correction] {
        let pool = lock.withLock { Array(items.suffix(300)) }.filter { $0.kind == kind }
        guard !pool.isEmpty else { return [] }
        let query = String(summary.prefix(300))
        let scored: [(Correction, Double)] = pool.map { c in (c, distance(query, c.summary)) }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    /// Prompt lines for the model, plus the style hint once there are enough corrections.
    public func promptHelp(for ctx: FileContext) -> (examples: [String], style: String?) {
        let near = similar(to: ctx.text, kind: ctx.kind)
        let lines = near.map { c in
            "Text like \"\(String(c.summary.replacingOccurrences(of: "\n", with: " ").prefix(70)))\" was named \"\(c.userName)\" (Relabel had suggested \"\(c.relabelName)\")"
        }
        return (lines, styleDescription.map { $0.replacingOccurrences(of: "Your names tend to be ", with: "") })
    }

    // MARK: Similarity

    /// Smaller is closer. Uses on-device sentence embeddings, or word overlap when they aren't available.
    func distance(_ a: String, _ b: String) -> Double {
        if let e = embedding {
            let d = e.distance(between: a, and: b, distanceType: .cosine)
            if d.isFinite && d <= 2 { return d }
        }
        let ta = Set(tokens(a)), tb = Set(tokens(b))
        guard !ta.isEmpty, !tb.isEmpty else { return 2 }
        return 1 - Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
    }

    private func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
    }

    private func saveLocked() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(items) { try? d.write(to: storeURL, options: .atomic) }
    }
}
