import Foundation
import FoundationModels

public struct NamingResult: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case model, fallback }
    public var title: String
    public var category: String
    public var source: Source
}

/// Why the on-device model can or can't be used right now.
public enum ModelAvailability: Sendable, Equatable {
    case available
    case appleIntelligenceOff
    case notEligible
    case stillLoading

    public var explanation: String? {
        switch self {
        case .available: nil
        case .appleIntelligenceOff: "Apple Intelligence is off. Using basic naming from the text on the file."
        case .notEligible: "This Mac can't run Apple Intelligence. Using basic naming from the text on the file."
        case .stillLoading: "Waiting for Apple Intelligence. Using basic naming until it's ready."
        }
    }
}

/// `@Generable`-equivalent written by hand: the SwiftPM command line toolchain has no FoundationModels macro plugin.
struct GeneratedName: Generable {
    static let categories = ["website", "document", "chart", "error", "code", "chat", "invoice", "report",
                             "contract", "statement", "manual", "form", "email", "photo", "other"]
    var title: String
    var category: String

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: GeneratedName.self, description: "A descriptive file name and its category", properties: [
            .init(name: "title", description: "The file name without extension, no punctuation, no quotes", type: String.self),
            .init(name: "category", description: "What kind of file this is", type: String.self,
                  guides: [.anyOf(categories)]),
        ])
    }
    init(title: String, category: String) { self.title = title; self.category = category }
    init(_ content: GeneratedContent) throws {
        title = try content.value(String.self, forProperty: "title")
        category = try content.value(String.self, forProperty: "category")
    }
    var generatedContent: GeneratedContent {
        GeneratedContent(properties: ["title": title, "category": category])
    }
}

public enum NamingModel {
    public static func availability() -> ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
        case .unavailable(.deviceNotEligible): .notEligible
        case .unavailable(.modelNotReady): .stillLoading
        @unknown default: .stillLoading
        }
    }

    static let rules = """
        You name files so people can find them later. Reply with a short title and a category.
        Rules:
        - Describe what the file is, not what the user interface looks like.
        - Never invent details that are not in the text you are given.
        - No punctuation, no file extension, no quotes, no dates.
        - Keep numbers, years and reference numbers as digits, exactly as written.
        - Keep acronyms, company, person and product names and reference numbers exactly as written in the text (CNC stays CNC). Other words are lower case, except the first word.
        - Screenshots are often cropped, so words at the edges may be cut off. Ignore fragments and use the full words and the overall subject.
        - Name the whole subject of the file, not one line of it.
        - Use plain words in the same language as the text.
        - Put the most useful identifying detail first (who or what it is about), then what kind of file it is.
        """

    /// One worked example per length so the three lengths really differ.
    static func example(for length: NameLength) -> String {
        switch length {
        case .short: "Example: a spreadsheet of team budgets for 2027 -> \"Team budget 2027\""
        case .standard: "Example: a spreadsheet of team budgets for 2027 -> \"Quarterly team budget forecast 2027\""
        case .detailed: "Example: a spreadsheet of team budgets for 2027 -> \"Quarterly budget forecast 2027 by department with yearly totals\""
        }
    }

    public static func prompt(for ctx: FileContext, prefs: NamingPreferences, examples: [String] = []) -> String {
        var p = "Name this \(ctx.kind == .pdf ? "PDF" : "screenshot").\nLength: \(prefs.length.instruction)\n\(example(for: prefs.length))\n"
        if ctx.kind == .screenshot {
            if let app = ctx.appName { p += "Frontmost app when captured: \(app)\n" }
            if prefs.includeAppName, ctx.appName != nil { p += "End the title with the app name, like \"Quarterly budget in Excel\".\n" }
            if !ctx.labels.isEmpty { p += "Image labels: \(ctx.labels.joined(separator: ", "))\n" }
        } else {
            if let t = ctx.pdfTitle, BasicNamer.isUsefulTitle(t) { p += "PDF title metadata: \(t)\n" }
            if let a = ctx.pdfAuthor { p += "PDF author metadata: \(a)\n" }
            if let d = ctx.pdfCreated { p += "PDF created: \(Sanitizer.dateString(d))\n" }
            let custom = prefs.customPDFInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { p += "Extra instruction from the user: \(custom)\n" }
        }
        if !examples.isEmpty {
            p += "Names this user chose before for similar files:\n" + examples.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        p += "\nText on the \(ctx.kind == .pdf ? "first pages" : "screen"), top to bottom:\n\(ctx.promptText())"
        return p
    }

    /// Names a file with the on-device model. Falls back to basic naming (and says why in `note`).
    public static func name(for ctx: FileContext, prefs: NamingPreferences, examples: [String] = [],
                            useModel: Bool = true) async -> (result: NamingResult, note: String?) {
        let basic = BasicNamer.name(for: ctx, prefs: prefs)
        guard useModel else { return (basic, "Model skipped") }
        let avail = availability()
        guard avail == .available else { return (basic, avail.explanation) }
        guard ctx.text.count >= 3 || !ctx.labels.isEmpty else { return (basic, "No text found to name it from.") }
        do {
            let session = LanguageModelSession(instructions: rules)
            let response = try await session.respond(to: prompt(for: ctx, prefs: prefs, examples: examples),
                                                     generating: GeneratedName.self,
                                                     options: GenerationOptions(sampling: .greedy))
            let title = Sanitizer.sentenceCased(Sanitizer.restoreAcronyms(Sanitizer.cleanTitle(response.content.title), source: ctx.text))
            guard !title.isEmpty else { return (basic, "No better name found. Using basic naming.") }
            return (NamingResult(title: title, category: response.content.category, source: .model), nil)
        } catch {
            return (basic, "Apple Intelligence is busy or couldn't answer (\(error.localizedDescription)). Using basic naming.")
        }
    }
}
