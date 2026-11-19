import Foundation
import RelabelCore

enum LearningChecks {
    static func corr(_ kind: FileKind, _ summary: String, _ relabel: String, _ user: String, app: String? = nil) -> Correction {
        Correction(id: UUID(), time: Date(), kind: kind, summary: summary, relabelName: relabel, userName: user, appName: app)
    }

    static func store() throws {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("l.json")
        let s = LearningStore(storeURL: url)
        check(s.add(corr(.pdf, "Invoice ACME Plumbing Ltd amount due payable within 30 days", "ACME Plumbing invoice", "Plumber INV-20481")), "first correction reported")
        check(!s.add(corr(.screenshot, "Quarterly budget forecast marketing engineering", "Quarterly budget forecast 2027", "budget", app: "Excel")), "second is not first")
        check(LearningStore(storeURL: url).count == 2, "persists")
        var c = corr(.pdf, "x", "a", "b"); _ = s.add(c); c.userName = "b2"; _ = s.add(c)
        check(s.count == 3 && s.all.last?.userName == "b2", "same record updates, not duplicates")
        s.remove(id: c.id); check(s.count == 2, "remove one")
        s.forgetAll(); check(s.count == 0 && LearningStore(storeURL: url).count == 0, "forget everything")
    }

    static func similarity() {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let s = LearningStore(storeURL: d.appendingPathComponent("l.json"))
        _ = s.add(corr(.pdf, "Invoice number 4411 amount due bill to payment terms 30 days plumbing repair", "Plumbing invoice", "Plumber 4411"))
        _ = s.add(corr(.pdf, "Employment agreement between employer and employee notice period salary", "Employment agreement", "Job contract"))
        _ = s.add(corr(.pdf, "Invoice number 9120 amount due bill to payment electrician labour", "Electrician invoice", "Electrician 9120"))
        _ = s.add(corr(.screenshot, "Invoice number 1 amount due", "should not match kind", "wrong"))
        let near = s.similar(to: "Invoice INV-20481 amount due payable within 30 days emergency pipe repair", kind: .pdf, limit: 2)
        check(near.count == 2 && near.allSatisfy { $0.kind == .pdf }, "only same kind, limit respected")
        check(near.map(\.userName).sorted() == ["Electrician 9120", "Plumber 4411"], "most similar are the invoices: \(near.map(\.userName)) embeddings=\(s.hasEmbeddings)")
    }

    static func style() {
        check(StyleProfile.describe([corr(.pdf, "a", "A long name", "x"), corr(.pdf, "b", "B", "y")]) == nil, "no profile under 3")
        let names = ["budget", "invoice", "contract"].map { corr(.screenshot, "t", "Quarterly budget forecast 2027", $0) }
        let p = StyleProfile.describe(names) ?? ""
        check(p.hasPrefix("Your names tend to be one word"), "one word: \(p)")
        check(p.contains("in lower case") && p.contains("shorter than Relabel's"), "lower case and shorter: \(p)")
        let withApp = ["Budget in Excel", "Chart in Numbers", "Memo in Pages"].enumerated().map {
            corr(.screenshot, "t", "Some long Relabel name here", $0.element, app: ["Excel", "Numbers", "Pages"][$0.offset]) }
        check((StyleProfile.describe(withApp) ?? "").contains("with the app name"), "app name: \(StyleProfile.describe(withApp) ?? "")")
        let dated = ["2026-01-01 a b", "2026-02-02 c d", "2026-03-03 e f"].map { corr(.pdf, "t", "Other thing here", $0) }
        check((StyleProfile.describe(dated) ?? "").contains("with the date"), "date")
    }

    static func detection() throws {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let h = RenameHistory(storeURL: d.appendingPathComponent("h.json"))
        let folder = d.appendingPathComponent("f"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func make(_ old: String, _ new: String) throws -> HistoryRecord {
            let u = folder.appendingPathComponent(old); write(u, old)
            return try h.rename(from: u, to: folder.appendingPathComponent(new), source: .auto, kind: .pdf, relabelName: new, summary: "s", appName: "Preview")
        }
        let a = try make("a.pdf", "Relabel A.pdf"), b = try make("b.pdf", "Relabel B.pdf"), c = try make("c.pdf", "Relabel C.pdf")
        check(h.detectExternalRenames().isEmpty, "nothing changed yet")
        try FileManager.default.moveItem(at: a.newURL, to: folder.appendingPathComponent("my own name.pdf"))     // renamed in Finder
        let other = d.appendingPathComponent("elsewhere"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: b.newURL, to: other.appendingPathComponent("b.pdf"))              // moved away: not a rename
        let changed = h.detectExternalRenames()
        check(changed.count == 1 && changed[0].id == a.id && changed[0].userName == "my own name.pdf", "detected the Finder rename")
        check(h.record(id: a.id)?.newName == "my own name.pdf", "record follows the file")
        let corr = LearningStore.correction(from: changed[0])
        check(corr?.userName == "my own name" && corr?.relabelName == "Relabel A" && corr?.appName == "Preview", "correction built")
        check(h.detectExternalRenames().isEmpty, "not reported twice")
        _ = c
        // reverting to the original name teaches nothing
        var back = changed[0]; back.userName = "a.pdf"
        check(LearningStore.correction(from: back) == nil, "no correction when reverted to original")
    }

    static func promptHelp() {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let s = LearningStore(storeURL: d.appendingPathComponent("l.json"))
        for n in ["budget", "invoice", "contract"] { _ = s.add(corr(.pdf, "Invoice amount due payable \(n)", "Long Relabel name for it", n)) }
        let ctx = FileContext(kind: .pdf, originalName: "x.pdf", text: "Invoice amount due payable within 30 days")
        let help = s.promptHelp(for: ctx)
        check(help.examples.count == 3 && help.examples[0].contains("was named"), "examples built")
        check(help.style?.hasPrefix("one word") == true, "style hint: \(help.style ?? "nil")")
        let prompt = NamingModel.prompt(for: ctx, prefs: NamingPreferences(), examples: help.examples, styleHint: help.style)
        check(prompt.contains("Corrections this user made") && prompt.contains("usual naming style"), "prompt includes learning")
        check(!NamingModel.prompt(for: ctx, prefs: NamingPreferences()).contains("Corrections this user made"), "no learning, no section")
    }
}
