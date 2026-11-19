import Foundation

public enum NameLength: String, Codable, Sendable, CaseIterable {
    case short, standard, detailed

    public var label: String { rawValue.capitalized }

    /// Guidance given to the model.
    public var instruction: String {
        switch self {
        case .short: "What it shows, in 2 to 6 words."
        case .standard: "What it is and the key subject, in 4 to 8 words."
        case .detailed: "With the specifics, in up to 10 words."
        }
    }
}

public enum DateStyle: String, Codable, Sendable, CaseIterable {
    case none, atStart, atEnd
}

public struct NamingPreferences: Codable, Sendable, Equatable {
    public var length: NameLength = .standard
    public var includeAppName = false
    public var dateStyle: DateStyle = .none
    /// Optional free-text instruction for PDFs, passed to the model and used by Tidy Up.
    public var customPDFInstruction = ""
    public var notifications = true

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        length = try c.decodeIfPresent(NameLength.self, forKey: .length) ?? .standard
        includeAppName = try c.decodeIfPresent(Bool.self, forKey: .includeAppName) ?? false
        dateStyle = try c.decodeIfPresent(DateStyle.self, forKey: .dateStyle) ?? .none
        customPDFInstruction = try c.decodeIfPresent(String.self, forKey: .customPDFInstruction) ?? ""
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
    }

    public init(length: NameLength = .standard, includeAppName: Bool = false,
                dateStyle: DateStyle = .none, customPDFInstruction: String = "") {
        self.length = length; self.includeAppName = includeAppName
        self.dateStyle = dateStyle; self.customPDFInstruction = customPDFInstruction
    }
}
