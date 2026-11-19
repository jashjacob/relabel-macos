import Foundation
import RelabelCore

enum TidyChecks {
    static func nameQuality() {
        for n in ["IMG_2041.HEIC", "scan0001.pdf", "Document (3).pdf", "Screenshot 2026-11-19 at 4.12.08 PM.png", "untitled.png",
                  "download (12).pdf", "20261119_142233.jpg", "a1b2c3d4e5f6a7b8c9d0.png", "Untitled 2.pdf", "image.png",
                  "Screen Shot 2019-05-01 at 10.00.00 AM.png", "WhatsApp Image 2026-01-02 at 10.11.12.jpeg"] {
            check(NameQuality.looksGenerated(n), "should look generated: \(n)")
        }
        for n in ["Quarterly budget forecast 2027.pdf", "ACME Plumbing Ltd invoice INV-20481.pdf", "Holiday in Lisbon.jpg",
                  "Document control procedure.pdf", "Tax return 2025.pdf", "Resume Jash.pdf"] {
            check(!NameQuality.looksGenerated(n), "should look intentional: \(n)")
        }
    }

    static func dateTokens() {
        check(DateTokens.restyle(stem: "2026-11-02 Budget plan", to: .none) == "Budget plan", "remove from start")
        check(DateTokens.restyle(stem: "Budget plan 2026-11-02", to: .none) == "Budget plan", "remove from end")
        check(DateTokens.restyle(stem: "2026-11-02 Budget plan", to: .atEnd) == "Budget plan 2026-11-02", "start to end")
        check(DateTokens.restyle(stem: "Budget plan 2026-11-02", to: .atStart) == "2026-11-02 Budget plan", "end to start")
        check(DateTokens.restyle(stem: "2026-11-02 Budget plan", to: .atStart) == nil, "already right")
        check(DateTokens.restyle(stem: "Budget plan", to: .atStart) == nil, "no date")
        check(DateTokens.restyle(stem: "Screenshot 2026-11-19 at 4.12.08 PM", to: .none) == nil, "mid-name date left alone")
    }

    static func planner() async throws {
        let support = scratch(), folder = scratch()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: folder) }
        let history = RenameHistory(storeURL: support.appendingPathComponent("h.json"))
        let markers = ProcessedMarkers(storeURL: support.appendingPathComponent("p.json"))
        let fx = URL(fileURLWithPath: "Fixtures")
        try FileManager.default.copyItem(at: fx.appendingPathComponent("invoice-text.pdf"), to: folder.appendingPathComponent("scan0001.pdf"))
        try FileManager.default.copyItem(at: fx.appendingPathComponent("invoice-scanned.pdf"), to: folder.appendingPathComponent("Document (2).pdf"))
        try FileManager.default.copyItem(at: fx.appendingPathComponent("invoice-text.pdf"), to: folder.appendingPathComponent("Tax return 2025.pdf"))
        try FileManager.default.copyItem(at: fx.appendingPathComponent("Screenshot 2026-11-19 at 10.15.00.png"), to: folder.appendingPathComponent("IMG_0001.png"))
        write(folder.appendingPathComponent("notes.txt")); write(folder.appendingPathComponent(".hidden.pdf"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)

        let pipeline = NamingPipeline(history: history, markers: markers, prefs: { NamingPreferences() },
                                      namer: { ctx, _ in (NamingResult(title: ctx.kind == .pdf ? "Invoice from ACME" : "Budget forecast", category: "x", source: .model), nil) })
        var items = TidyPlanner.scan(folder: folder, markers: markers)
        check(items.count == 4, "scan finds 4 images/PDFs, got \(items.count)")
        check(items.filter { $0.alreadyGood }.map { $0.url.lastPathComponent } == ["Tax return 2025.pdf"], "one dimmed")
        check(items.filter(\.selected).count == 3, "good names unchecked")

        let box = Box(items)
        await TidyPlanner.proposeAll(items, includeGood: false, prefs: NamingPreferences(), pipeline: pipeline) { i, it, _, _ in box.mutate { $0[i] = it } }
        items = box.value
        check(items.filter { $0.status == .ready }.count == 3, "three proposals")
        check(items.first { $0.alreadyGood }?.status == .pending, "good name not proposed")
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("scan0001.pdf").path), "nothing renamed before apply")

        let prefs = NamingPreferences()
        let preview = TidyPlanner.previewNames(items, prefs: prefs)
        check(Set(preview.values) == ["Invoice from ACME.pdf", "Invoice from ACME 2.pdf", "Budget forecast.png"], "preview collisions \(preview.values.sorted())")

        // user unchecks one and edits another
        if let i = items.firstIndex(where: { $0.url.lastPathComponent == "Document (2).pdf" }) { items[i].selected = false }
        if let i = items.firstIndex(where: { $0.url.lastPathComponent == "IMG_0001.png" }) { items[i].editedBase = "My chart: Q1/Q2" }
        let result = TidyPlanner.apply(items, prefs: prefs, history: history, markers: markers)
        check(result.records.count == 2 && result.failures.isEmpty, "applied 2")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        check(names.contains("Invoice from ACME.pdf") && names.contains("My chart Q1Q2.png") && names.contains("Document (2).pdf"), "after apply \(names)")

        // dated names + date helper
        write(folder.appendingPathComponent("2026-03-01 Lease.pdf")); write(folder.appendingPathComponent("Receipt 2026-04-05.pdf"))
        let fixes = TidyPlanner.dateFixes(folder: folder, style: .none)
        check(Set(fixes.map(\.newName)) == ["Lease.pdf", "Receipt.pdf"], "date fixes \(fixes.map(\.newName))")
        _ = TidyPlanner.applyDateFixes(fixes, history: history, markers: markers)
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Lease.pdf").path), "date removed")

        // undo all reverts the batch
        let failures = TidyPlanner.undoAll(result.records, history: history)
        check(failures.isEmpty, "undo all clean")
        let after = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        check(after.contains("scan0001.pdf") && after.contains("IMG_0001.png"), "originals restored \(after.sorted())")
    }
}
