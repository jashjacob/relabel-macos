import Foundation
import RelabelCore

func scratch() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("relabel-check-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
func write(_ url: URL, _ s: String = "x") { try! s.data(using: .utf8)!.write(to: url) }

enum RenameChecks {
    static func sanitizing() {
        check(Sanitizer.cleanTitle("a/b:c\\d\"e*f?g<h>i|j") == "abcdefghij", "forbidden chars")
        check(Sanitizer.cleanTitle("  many   spaces \n here ") == "many spaces here", "whitespace")
        check(Sanitizer.cleanTitle(String(repeating: "word ", count: 40)).count <= 80, "cap 80")
        check(Sanitizer.cleanTitle("\u{201C}Quoted\u{201D}.") == "Quoted", "curly quotes and trailing dot")
        check(Sanitizer.cleanTitle("...hidden") == "hidden", "leading dots")
        check(Sanitizer.cleanTitle("///") == "", "all forbidden")
        check(Sanitizer.sentenceCased("hello world") == "Hello world" && Sanitizer.sentenceCased("CNC lathe") == "CNC lathe", "sentence case")
        check(Sanitizer.restoreAcronyms("Cnc system", source: "fit a CNC with drives") == "CNC system", "acronym restore")
        check(Sanitizer.restoreAcronyms("Scope of work", source: "SCOPE OF WORK") == "Scope of work", "heading not acronym")
        check(Sanitizer.restoreAcronyms("Cnc spares reports", source: "CNC SPARES\nSPARES REPORT") == "CNC spares reports", "acronym in caps table")
        check(Sanitizer.restoreAcronyms("Of the new plan", source: "OF THE NEW PLAN") == "Of the new plan", "common words stay")
        check(Sanitizer.restoreAcronyms("Usb adapter", source: "USB ADAPTER") == "USB adapter", "3-letter acronym in caps line")
    }

    static func collisions() {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        check(Sanitizer.uniqueURL(directory: d, base: "Report", ext: "pdf").lastPathComponent == "Report.pdf", "free name")
        write(d.appendingPathComponent("Report.pdf"))
        check(Sanitizer.uniqueURL(directory: d, base: "Report", ext: "pdf").lastPathComponent == "Report 2.pdf", "second")
        write(d.appendingPathComponent("Report 2.pdf"))
        check(Sanitizer.uniqueURL(directory: d, base: "Report", ext: "pdf").lastPathComponent == "Report 3.pdf", "third")
        check(Sanitizer.uniqueURL(directory: d, base: "Readme", ext: "").lastPathComponent == "Readme", "no extension")
    }

    static func dates() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26 UTC
        let s = Sanitizer.dateString(date, calendar: cal)
        check(s == "2026-10-26", "date format \(s)")
        check(Sanitizer.baseName(title: "Budget", date: date, style: .atStart, calendar: cal) == "2026-10-26 Budget", "date at start")
        check(Sanitizer.baseName(title: "Budget", date: date, style: .atEnd, calendar: cal) == "Budget 2026-10-26", "date at end")
        check(Sanitizer.baseName(title: "Budget", date: date, style: .none, calendar: cal) == "Budget", "no date")
        check(Sanitizer.baseName(title: String(repeating: "word ", count: 40), date: date, style: .atEnd, calendar: cal).count <= 80, "cap with date")
    }

    static func screenshotNames() {
        for n in ["Screenshot 2026-11-19 at 4.12.08 PM.png", "Screenshot 2026-11-19 at 4.12.08\u{202F}PM.png",
                  "Screen Shot 2019-05-01 at 10.00.00 AM.png", "Screenshot 2026-11-19 at 14.03.04.png",
                  "Screenshot 2026-11-19 at 4.12.08 PM (2).heic", "Screenshot 2026-11-19 at 4.12.08\u{202F}PM.jpg"] {
            check(FileEligibility.isScreenshotName(n), "should match \(n)")
        }
        for n in ["Screen Recording 2026-11-19 at 4.12.08 PM.mov", "holiday.png", "Screenshot 2026-11-19 at 4.12.08 PM.png.crdownload",
                  ".Screenshot 2026-11-19 at 4.12.08 PM.png", "Screenshot notes.png"] {
            check(!FileEligibility.isScreenshotName(n) || FileEligibility.kind(forFileNamed: n, in: .screenshots) == nil, "should not match \(n)")
        }
        check(FileEligibility.kind(forFileNamed: "a.pdf", in: .pdf) == .pdf, "pdf")
        check(FileEligibility.kind(forFileNamed: "a.pdf.crdownload", in: .pdf) == nil, "crdownload")
        check(FileEligibility.kind(forFileNamed: "a.download", in: .pdf) == nil, "download")
        check(FileEligibility.kind(forFileNamed: "a.part", in: .pdf) == nil, "part")
        check(FileEligibility.kind(forFileNamed: "a.png", in: .pdf) == nil, "png in pdf folder")
        check(FileEligibility.kind(forFileNamed: "A.PDF", in: .pdf) == .pdf, "uppercase ext")
    }

    static func undoRedo() throws {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let h = RenameHistory(storeURL: d.appendingPathComponent("h.json"))
        let old = d.appendingPathComponent("a.pdf"); write(old)
        let created = try old.resourceValues(forKeys: [.creationDateKey]).creationDate!
        let rec = try h.rename(from: old, to: d.appendingPathComponent("Nice name.pdf"), source: .auto, kind: .pdf, relabelName: "Nice name.pdf", summary: "")
        check(!FileManager.default.fileExists(atPath: old.path) && FileManager.default.fileExists(atPath: rec.newPath), "renamed")
        check(try rec.newURL.resourceValues(forKeys: [.creationDateKey]).creationDate == created, "creation date preserved")
        _ = try h.undo(id: rec.id)
        check(FileManager.default.fileExists(atPath: old.path) && h.record(id: rec.id)?.state == .undone, "undo")
        _ = try h.redo(id: rec.id)
        check(FileManager.default.fileExists(atPath: rec.newPath) && h.namedCount == 1, "redo")
        // persists
        check(RenameHistory(storeURL: d.appendingPathComponent("h.json")).all().count == 1, "history persists")

        // moved/renamed since
        try FileManager.default.moveItem(at: rec.newURL, to: d.appendingPathComponent("user renamed.pdf"))
        do { _ = try h.undo(id: rec.id); check(false, "should fail") } catch {
            check(error.localizedDescription == "Couldn't undo. The file was moved or renamed.", "moved msg: \(error.localizedDescription)")
        }
        // changed since
        let f2 = d.appendingPathComponent("b.pdf"); write(f2, "one")
        let r2 = try h.rename(from: f2, to: d.appendingPathComponent("Second.pdf"), source: .auto, kind: .pdf, relabelName: "Second.pdf", summary: "")
        Thread.sleep(forTimeInterval: 1.2); write(r2.newURL, "edited later")
        do { _ = try h.undo(id: r2.id); check(false, "should fail") } catch {
            check(error.localizedDescription == "Couldn't undo. The file has changed since.", "changed msg: \(error.localizedDescription)")
        }
        // never overwrites
        let f3 = d.appendingPathComponent("c.pdf"); write(f3)
        let r3 = try h.rename(from: f3, to: d.appendingPathComponent("Third.pdf"), source: .auto, kind: .pdf, relabelName: "Third.pdf", summary: "")
        write(f3, "squatter")
        do { _ = try h.undo(id: r3.id); check(false, "should fail") } catch { check(error is HistoryError, "name taken") }
        check((try? String(contentsOf: f3, encoding: .utf8)) == "squatter", "squatter untouched")
    }

    static func userRename() throws {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let h = RenameHistory(storeURL: d.appendingPathComponent("h.json"))
        let f = d.appendingPathComponent("raw.png"); write(f)
        let r = try h.rename(from: f, to: d.appendingPathComponent("Relabel name.png"), source: .auto, kind: .screenshot, relabelName: "Relabel name.png", summary: "s")
        let e1 = try h.userRename(id: r.id, to: "My own: name?")
        check(e1.newName == "My own name.png" && e1.userName == "My own name.png", "edited, sanitized, extension kept: \(e1.newName)")
        check(try h.userRename(id: r.id, to: "Typed with ext.PNG").newName == "Typed with ext.png", "typed extension not doubled")
        let other = d.appendingPathComponent("Taken.png"); write(other)
        do { _ = try h.userRename(id: r.id, to: "Taken"); check(false, "should clash") } catch {
            check(error.localizedDescription == "Couldn't rename. A file with that name already exists.", "clash msg: \(error.localizedDescription)")
        }
        do { _ = try h.userRename(id: r.id, to: "///"); check(false, "should be empty") } catch { check((error as? HistoryError) == .emptyName, "empty name") }
        check(try h.userRename(id: r.id, to: "TYPED WITH EXT").newName == "TYPED WITH EXT.png", "case-only change")
        check(FileManager.default.fileExists(atPath: other.path), "other file untouched")
        // undo still works after an edit and restores the very first name
        _ = try h.undo(id: r.id)
        check(FileManager.default.fileExists(atPath: f.path), "undo after edit")
        // moved by user -> clear message
        _ = try h.redo(id: r.id)
        try FileManager.default.moveItem(at: h.record(id: r.id)!.newURL, to: d.appendingPathComponent("elsewhere.png"))
        do { _ = try h.userRename(id: r.id, to: "x"); check(false, "should fail") } catch {
            check(error.localizedDescription == "Couldn't rename. The file was moved or renamed.", "moved msg")
        }
    }

    static func markers() throws {
        let d = scratch(); defer { try? FileManager.default.removeItem(at: d) }
        let m = ProcessedMarkers(storeURL: d.appendingPathComponent("p.json"))
        let f = d.appendingPathComponent("one.pdf"); write(f)
        check(!m.isProcessed(f), "fresh")
        m.mark(f, .renamed)
        let moved = d.appendingPathComponent("renamed.pdf")
        try FileManager.default.moveItem(at: f, to: moved)
        check(m.isProcessed(moved), "inode survives rename")
        check(ProcessedMarkers(storeURL: d.appendingPathComponent("p.json")).isProcessed(moved), "persisted")
        let t1 = m.watchStart(for: "k"), t2 = m.watchStart(for: "k", now: Date().addingTimeInterval(100))
        check(t1 == t2, "watch start fixed")
    }

    /// Low Power / hot: new files wait, then are named when released. Dropped files are never held.
    static func hold() async throws {
        let support = scratch(), folder = scratch()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: folder) }
        let count = Box(0)
        let engine = RelabelEngine(history: RenameHistory(storeURL: support.appendingPathComponent("h.json")),
                                   markers: ProcessedMarkers(storeURL: support.appendingPathComponent("p.json")),
                                   stableFor: 0.5, screenshotDelay: 0.5,
                                   namer: { _, _ in (NamingResult(title: "Held invoice", category: "x", source: .model), nil) },
                                   onOutcome: { _, o in if case .renamed = o { count.mutate { $0 += 1 } } })
        engine.sync([RelabelEngine.WatchedFolder(id: UUID(), url: folder, kind: .pdf)])
        engine.setHold(true)
        try await Task.sleep(for: .milliseconds(300))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Fixtures/invoice-text.pdf"), to: folder.appendingPathComponent("a.pdf"))
        try await Task.sleep(for: .seconds(4))
        check(count.value == 0 && FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.pdf").path), "nothing named while held")
        let dropped = folder.appendingPathComponent("dropped.pdf")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "Fixtures/invoice-scanned.pdf"), to: dropped)
        engine.enqueue(RenameJob(url: dropped, kind: .pdf, source: .drop))
        try await Task.sleep(for: .seconds(3))
        check(count.value == 1, "dropped file is not held, got \(count.value)")
        engine.setHold(false)
        try await Task.sleep(for: .seconds(3))
        check(count.value == 2, "held file named after release, got \(count.value)")
    }

    /// Whole flow with a stand-in namer: watcher -> queue -> rename -> history, plus partial downloads ignored.
    static func endToEnd() async throws {
        let support = scratch(), folder = scratch()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: folder) }
        let outcomes = Box<[JobOutcome]>([])
        let engine = RelabelEngine(history: RenameHistory(storeURL: support.appendingPathComponent("h.json")),
                                   markers: ProcessedMarkers(storeURL: support.appendingPathComponent("p.json")),
                                   stableFor: 0.6, screenshotDelay: 0.6,
                                   namer: { _, _ in (NamingResult(title: "Invoice from ACME", category: "invoice", source: .model), nil) },
                                   onOutcome: { _, o in outcomes.mutate { $0.append(o) } })
        engine.sync([RelabelEngine.WatchedFolder(id: UUID(), url: folder, kind: .pdf)])
        try await Task.sleep(for: .milliseconds(300))
        let src = URL(fileURLWithPath: "Fixtures/invoice-text.pdf")
        try FileManager.default.copyItem(at: src, to: folder.appendingPathComponent("download (1).pdf"))
        write(folder.appendingPathComponent("partial.pdf.crdownload"))
        write(folder.appendingPathComponent("notes.txt"))
        try FileManager.default.copyItem(at: src, to: folder.appendingPathComponent("second.pdf"))
        try await Task.sleep(for: .seconds(6))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        check(names == ["Invoice from ACME 2.pdf", "Invoice from ACME.pdf", "notes.txt", "partial.pdf.crdownload"], "end result \(names)")
        check(outcomes.value.count == 2, "two outcomes, got \(outcomes.value.count)")
        check(engine.history.namedCount == 2, "history count")
        // renamed files are not picked up again
        try await Task.sleep(for: .seconds(3))
        check(outcomes.value.count == 2, "no re-processing")
    }
}

final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&v) } }
}
