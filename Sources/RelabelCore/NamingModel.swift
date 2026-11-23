import Foundation
import FoundationModels

public struct NamingResult: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case model, fallback }
    public var title: String
    public var category: String
    public var source: Source
    public init(title: String, category: String, source: Source) {
        self.title = title; self.category = category; self.source = source
    }
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
    /// True when the on-device model on this Mac can take pictures.
    public static var supportsImages: Bool { SystemLanguageModel.default.capabilities.contains(.vision) }

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
        - Keep acronyms and reference numbers exactly as written in the text (CNC stays CNC).
        - Write company, person and product names with normal capitals even when the text shouts them (ACME AUTOMATION SYSTEMS becomes Acme Automation Systems). Other words are lower case, except the first word.
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

    static func imageHint(_ ctx: FileContext) -> String {
        ctx.image == nil ? "" : "A picture of it is attached. Use the picture to see what app, website, brand or document it is and what it is about. Use the text for exact names and numbers.\n"
    }

    public static func prompt(for ctx: FileContext, prefs: NamingPreferences, examples: [String] = [], styleHint: String? = nil) -> String {
        var p = "Name this \(ctx.kind == .pdf ? "PDF" : "screenshot").\n\(imageHint(ctx))Length: \(prefs.length.instruction)\n\(example(for: prefs.length))\n"
        if ctx.kind == .screenshot {
            if let app = ctx.appName { p += "Frontmost app when captured: \(app)\n" }
            if prefs.includeAppName, ctx.appName != nil { p += "End the title with the app name, like \"Quarterly budget in Excel\".\n" }
            if !ctx.labels.isEmpty { p += "Image labels: \(ctx.labels.joined(separator: ", "))\n" }
        } else {
            if let t = ctx.pdfTitle, BasicNamer.isUsefulTitle(t) { p += "PDF title metadata: \(t)\n" }
            if let a = ctx.pdfAuthor { p += "PDF author metadata: \(a)\n" }
            if ctx.text.range(of: #"(?im)^\s*(?:Dear\s|Sub(?:ject)?\s*:)"#, options: .regularExpression) != nil {
                p += "This looks like a letter. Name it by its subject, not by a year or reference number.\n"
            }
            if (ctx.originalName + " " + ctx.text.prefix(600)).range(of: "catalog", options: .caseInsensitive) != nil {
                p += "This looks like a product catalogue. Call it a catalogue, not a manual.\n"
            }
            let custom = prefs.customPDFInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { p += "Extra instruction from the user: \(custom)\n" }
        }
        if !examples.isEmpty {
            p += "Corrections this user made to earlier names for similar files. Follow their style:\n" + examples.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        if let styleHint { p += "The user's usual naming style: \(styleHint). Follow it unless the text clearly needs more.\n" }
        if ctx.kind == .screenshot, let contact = ChatFacts.contact(in: ctx.text) { p += ChatFacts.hint(contact: contact) }
        p += "\nText on the \(ctx.kind == .pdf ? "first pages" : "screen"), top to bottom:\n\(ctx.promptText())"
        return p
    }

    /// Names a file with the on-device model. Falls back to basic naming (and says why in `note`).
    public static func name(for ctx: FileContext, prefs: NamingPreferences, examples: [String] = [], styleHint: String? = nil,
                            useModel: Bool = true, forceTextOnly: Bool = false) async -> (result: NamingResult, note: String?) {
        let basic = BasicNamer.name(for: ctx, prefs: prefs)
        // Flight lists, hotel results and product pages have a clear pattern. Plain rules name them better than the model, and instantly.
        if prefs.customPDFInstruction.trimmingCharacters(in: .whitespaces).isEmpty || ctx.kind == .screenshot,
           let named = RuleNamer.name(for: ctx.text, length: prefs.length) {
            return (NamingResult(title: named.title, category: named.category, source: .model), nil)
        }
        guard useModel else { return (basic, "Model skipped") }
        let avail = availability()
        guard avail == .available else { return (basic, avail.explanation) }
        let withImage = prefs.useImage && !forceTextOnly && supportsImages && ctx.image != nil
        guard withImage || ctx.text.count >= 3 || !ctx.labels.isEmpty else { return (basic, "No text found to name it from.") }
        var lastError: Error?
        var best: (title: String, category: String)?
        var feedback: String?
        for attempt in 0..<3 {
            do {
                var c = ctx
                if !withImage { c.image = nil }
                var text = prompt(for: c, prefs: prefs, examples: examples, styleHint: styleHint)
                if let feedback { text += "\n\n" + feedback }
                let session = LanguageModelSession(instructions: rules)
                let full: Prompt
                if let img = c.image { full = Prompt { text; Attachment(img.image) } } else { full = Prompt { text } }
                let response = try await session.respond(to: full, generating: GeneratedName.self,
                                                         options: GenerationOptions(sampling: .greedy))
                var title = Sanitizer.restoreAcronyms(Sanitizer.sentenceCased(Sanitizer.cleanTitle(response.content.title)), source: ctx.text)
                title = Sanitizer.restoreProperNames(TitleCheck.stripped(title), source: ctx.text)
                title = Sanitizer.restoreIdentifiers(Sanitizer.calmCaps(title), source: ctx.text)
                if ctx.kind == .pdf, title.lowercased().hasSuffix(" manual"),
                   (ctx.originalName + " " + ctx.text).range(of: "catalog", options: .caseInsensitive) != nil,
                   ctx.text.range(of: "manual", options: .caseInsensitive) == nil {
                    title = String(title.dropLast(6)) + "catalogue"
                }
                if ctx.kind == .screenshot, let contact = ChatFacts.contact(in: ctx.text) { title = ChatFacts.finalTitle(title, contact: contact) }
                guard !title.isEmpty else { return (basic, "No better name found. Used basic naming.") }
                let problem = TitleCheck.problem(title, length: prefs.length, sourceText: ctx.text)
                if best == nil || problem == nil { best = (title, response.content.category) }
                guard let problem, attempt == 0 else { break }              // one corrective retry only
                feedback = "Your previous title \"\(title)\" was rejected because \(problem). Write a better one from the same facts."
            } catch {
                lastError = error
                if ProcessInfo.processInfo.environment["RELABEL_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("model error: \(String(reflecting: error))\n".utf8))
                }
                // Sampling is greedy, so the same prompt fails the same way: only a busy model is worth asking again.
                guard isTransient(error) else { break }
                if attempt == 0 { try? await Task.sleep(for: .seconds(1.5)) }     // busy? give it a moment, then once more
            }
        }
        if let best {
            return (NamingResult(title: TitleCheck.trimmed(best.title, length: prefs.length), category: best.category, source: .model), nil)
        }
        return (basic, failureNote(lastError))
    }

    enum Failure { case busy, refused, tooLong, language, other }

    /// Sorts a model error. macOS 27 throws `LanguageModelError`, `LanguageModelSession.Error` and
    /// `SystemLanguageModel.Error`; the older `GenerationError` is still matched in case it turns up.
    static func failure(_ error: Error?) -> Failure {
        switch error {
        case let e as LanguageModelError:
            switch e {
            case .rateLimited, .timeout: return .busy
            case .guardrailViolation, .refusal: return .refused
            case .contextSizeExceeded: return .tooLong
            case .unsupportedLanguageOrLocale: return .language
            default: return .other
            }
        case is LanguageModelSession.Error, is SystemLanguageModel.Error: return .busy
        case let e as LanguageModelSession.GenerationError:
            switch e {
            case .rateLimited, .concurrentRequests, .assetsUnavailable: return .busy
            case .guardrailViolation, .refusal: return .refused
            case .exceededContextWindowSize: return .tooLong
            case .unsupportedLanguageOrLocale: return .language
            default: return .other
            }
        default: return .busy
        }
    }

    static func isTransient(_ error: Error?) -> Bool { failure(error) == .busy }

    /// What the menu shows when the model gave no name, in plain words.
    static func failureNote(_ error: Error?) -> String {
        switch failure(error) {
        case .busy: "Apple Intelligence is busy, try again. Used basic naming this time."
        case .refused: "Apple Intelligence wouldn't name this file. Used basic naming."
        case .tooLong: "This file has too much text for Apple Intelligence. Used basic naming."
        case .language: "Apple Intelligence doesn't support this language yet. Used basic naming."
        case .other: "Apple Intelligence couldn't name this file. Used basic naming."
        }
    }
}
