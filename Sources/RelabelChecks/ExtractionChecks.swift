import Foundation
import RelabelCore

enum ExtractionChecks {
    static func extraction() async throws {
        await TextExtractor.warmUp()
        let shot = try await TextExtractor.screenshotContext(url: URL(fileURLWithPath: "Fixtures/Screenshot 2026-11-19 at 10.15.00.png"), appName: "Excel")
        check(shot.text.contains("Quarterly Budget Forecast"), "screenshot OCR finds the heading")
        check(shot.text.split(separator: "\n").first?.contains("Quarterly") == true, "OCR text is ordered top to bottom: \(shot.text.prefix(40))")
        check(shot.appName == "Excel" && shot.usedOCR && shot.image != nil, "context carries app, OCR flag, image")

        let text = try await TextExtractor.pdfContext(url: URL(fileURLWithPath: "Fixtures/invoice-text.pdf"))
        check(!text.usedOCR && text.text.contains("INV-20481"), "text-layer PDF read with PDFKit, no OCR")
        check(text.pdfTitle == "Untitled" && text.pdfAuthor == "ACME Plumbing Ltd", "PDF metadata read")

        let scanned = try await TextExtractor.pdfContext(url: URL(fileURLWithPath: "Fixtures/invoice-scanned.pdf"))
        check(scanned.usedOCR && scanned.text.contains("INV-20481"), "image-only PDF falls back to OCR")

        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let fake = d.appendingPathComponent("fake.png"); write(fake, "not an image")
        do { _ = try await TextExtractor.screenshotContext(url: fake); check(false, "should throw") }
        catch { check(error.localizedDescription == "Not an image Relabel can open", "not-an-image message: \(error.localizedDescription)") }
        let junk = d.appendingPathComponent("junk.pdf"); write(junk, "not a pdf")
        do { _ = try await TextExtractor.pdfContext(url: junk); check(false, "should throw") }
        catch { check(error is ExtractionError, "unreadable PDF") }
    }

    static func basicNaming() async {
        let ctx = FileContext(kind: .pdf, originalName: "x.pdf", text: "ACME Plumbing Ltd\nINVOICE\nInvoice number INV-20481\nAmount due 1,284.50")
        let r = await NamingModel.name(for: ctx, prefs: NamingPreferences(), useModel: false)
        check(r.result.source == .fallback && r.result.title == "ACME Plumbing Ltd invoice", "basic name: \(r.result.title)")
        for length in NameLength.allCases {
            var p = NamingPreferences(); p.length = length
            check(BasicNamer.name(for: ctx, prefs: p).title == r.result.title, "basic naming ignores length")
        }
        let shot = FileContext(kind: .screenshot, originalName: "s.png", text: "QUARTERLY BUDGET FORECAST 2027\nDepartment Q1", appName: "Excel")
        var p = NamingPreferences(); p.includeAppName = true
        check(BasicNamer.name(for: shot, prefs: p).title == "Quarterly budget forecast 2027 in Excel", "all caps softened, app name added: \(BasicNamer.name(for: shot, prefs: p).title)")
        check(BasicNamer.name(for: FileContext(kind: .screenshot, originalName: "s.png", text: "", labels: ["landscape"]), prefs: p).title == "Screenshot of landscape", "label fallback")
    }

    static func fallbackNoteRecorded() async throws {
        let support = scratch(), folder = scratch()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: folder) }
        let h = RenameHistory(storeURL: support.appendingPathComponent("h.json"))
        let pipe = NamingPipeline(history: h, markers: ProcessedMarkers(storeURL: support.appendingPathComponent("p.json")), prefs: { NamingPreferences() },
                                  namer: { _, _ in (NamingResult(title: "Basic invoice", category: "invoice", source: .fallback), "Apple Intelligence is off. Using basic naming.") })
        let f = folder.appendingPathComponent("scan0001.pdf")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Fixtures/invoice-text.pdf"), to: f)
        let out = await pipe.process(RenameJob(url: f, kind: .pdf, source: .auto))
        guard case .renamed(let rec) = out else { check(false, "should rename, got \(out)"); return }
        check(rec.fallbackNote == "Apple Intelligence is off. Using basic naming.", "fallback reason recorded")
        // nothing readable -> kept, not endlessly retried
        let blank = folder.appendingPathComponent("blank.png")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Fixtures/Screenshot 2026-11-19 at 10.15.00.png"), to: blank)
        let pipe2 = NamingPipeline(history: h, markers: ProcessedMarkers(storeURL: support.appendingPathComponent("p2.json")), prefs: { NamingPreferences() },
                                   namer: { _, _ in (NamingResult(title: "", category: "x", source: .fallback), nil) })
        let o2 = await pipe2.process(RenameJob(url: blank, kind: .screenshot, source: .auto))
        check(o2 == .kept(NamingPipeline.noBetterName), "no better name keeps the original: \(o2)")
        let o3 = await pipe2.process(RenameJob(url: blank, kind: .screenshot, source: .auto))
        check(o3 == .skipped("Already handled."), "and is not retried: \(o3)")
    }
}
