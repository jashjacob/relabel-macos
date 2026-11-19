import Foundation

public enum FileKind: String, Codable, Sendable { case screenshot, pdf }

/// Everything we learned about a file. Only text goes to the model, never the image.
public struct FileContext: Sendable {
    public var kind: FileKind
    public var originalName: String
    public var text: String
    public var labels: [String] = []
    public var appName: String?
    public var pdfTitle: String?
    public var pdfAuthor: String?
    public var pdfCreated: Date?
    public var usedOCR = false
    public var fileDate: Date

    public init(kind: FileKind, originalName: String, text: String, labels: [String] = [], appName: String? = nil,
                pdfTitle: String? = nil, pdfAuthor: String? = nil, pdfCreated: Date? = nil,
                usedOCR: Bool = false, fileDate: Date = Date()) {
        self.kind = kind; self.originalName = originalName; self.text = text; self.labels = labels
        self.appName = appName; self.pdfTitle = pdfTitle; self.pdfAuthor = pdfAuthor
        self.pdfCreated = pdfCreated; self.usedOCR = usedOCR; self.fileDate = fileDate
    }

    /// Text trimmed to what fits comfortably in the on-device model's context.
    public func promptText(limit: Int = 2500) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}
