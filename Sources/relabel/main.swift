import Foundation
import RelabelCore

OCRHelper.runIfRequested()   // OCR runs in a short-lived helper copy of this program

// relabel spike <file> [--app <name>] [--prompt]
// relabel watch <folder> [--kind screenshots|pdf] [--seconds N]
// relabel tidy <folder> [--dry-run] [--length short|standard|detailed] [--date none|start|end] [--all]
// relabel history
// relabel undo
// Set RELABEL_SUPPORT_DIR to keep history and markers somewhere other than ~/Library/Application Support/Relabel.
func usage() -> Never {
    print("""
    usage:
      relabel spike <file> [--app <frontmost app>] [--prompt]   names for all three lengths + basic fallback
      relabel watch <folder> [--kind screenshots|pdf] [--seconds N]   name new files as they arrive
      relabel tidy <folder> [--dry-run] [--length ...] [--date none|start|end] [--all]   name a whole folder
      relabel eval [cases.json] [--text-only]                   score naming on the test set (Evals/)
      relabel history                                           recent renames
      relabel undo                                              undo the latest rename
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func expand(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }

switch command {
case "spike":
    guard args.count >= 2 else { usage() }
    let url = expand(args[1])
    let appName = option("--app")
    let showPrompt = args.contains("--prompt")
    do {
        print("Warming up text recognition (first run on a Mac can take about a minute)...")
        await TextExtractor.warmUp()
        let ctx = url.pathExtension.lowercased() == "pdf"
            ? try await TextExtractor.pdfContext(url: url)
            : try await TextExtractor.screenshotContext(url: url, appName: appName)
        print("File:    \(ctx.originalName)  (\(ctx.kind))")
        print("OCR:     \(ctx.usedOCR ? "yes" : "no, text layer")   Text: \(ctx.text.count) chars")
        if !ctx.labels.isEmpty { print("Labels:  \(ctx.labels.joined(separator: ", "))") }
        if let t = ctx.pdfTitle { print("PDF title: \(t)") }
        print("Model:   \(NamingModel.availability())")
        print("--- recognized text (first 400 chars) ---\n\(ctx.text.prefix(400))\n-----------------------------------------")
        print("Vision:  model can look at images: \(NamingModel.supportsImages)")
        for mode in [(false, "text only"), (true, "text + image")] where mode.0 == false || ctx.image != nil {
            var p = NamingPreferences(length: .standard, includeAppName: appName != nil); p.useImage = mode.0
            let t0 = Date()
            let r = await NamingModel.name(for: ctx, prefs: p, forceTextOnly: !mode.0)
            print(String(format: "%@ %5.1fs  %@  [%@, %@]", mode.1.padding(toLength: 13, withPad: " ", startingAt: 0),
                         Date().timeIntervalSince(t0), r.result.title, r.result.category, "\(r.result.source)"))
            if let n = r.note { print("          note: \(n)") }
        }
        let learning = LearningStore()
        if learning.count > 0 {
            let help = learning.promptHelp(for: ctx)
            let t0 = Date()
            let r = await NamingModel.name(for: ctx, prefs: NamingPreferences(), examples: help.examples, styleHint: help.style)
            print(String(format: "with learning  %5.1fs  %@   (%d corrections; style: %@)", Date().timeIntervalSince(t0), r.result.title,
                         learning.count, help.style ?? "not enough yet"))
            for e in help.examples { print("          example: \(e)") }
        }
        for length in NameLength.allCases {
            let prefs = NamingPreferences(length: length, includeAppName: appName != nil)
            let r = await NamingModel.name(for: ctx, prefs: prefs)
            print("\(length.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(r.result.title)   [\(r.result.category), \(r.result.source)]")
            if let n = r.note { print("          note: \(n)") }
            if showPrompt && length == .standard { print("\nPROMPT:\n\(NamingModel.prompt(for: ctx, prefs: prefs))\n") }
        }
        let basic = await NamingModel.name(for: ctx, prefs: NamingPreferences(includeAppName: appName != nil), useModel: false)
        print("Basic    \(basic.result.title)   [\(basic.result.category)]   (Apple Intelligence off: same for every length)")
    } catch {
        print("Error: \(error.localizedDescription)"); exit(1)
    }

case "watch":
    guard args.count >= 2 else { usage() }
    let folder = expand(args[1])
    let kind: FolderKind = option("--kind") == "pdf" ? .pdf : .screenshots
    let seconds = Double(option("--seconds") ?? "") ?? 3600
    print("Support dir: \(AppSupport.directory.path)")
    print("Warming up text recognition...")
    await TextExtractor.warmUp()
    let engine = RelabelEngine(
        onState: { print("  [queue] \($0)") },
        onOutcome: { job, outcome in
            switch outcome {
            case .renamed(let r): print("RENAMED  \(r.oldName)  ->  \(r.newName)")
            case .kept(let why): print("KEPT     \(job.url.lastPathComponent)  (\(why))")
            case .failed(let why): print("FAILED   \(job.url.lastPathComponent)  (\(why))")
            case .skipped(let why): print("SKIPPED  \(job.url.lastPathComponent)  (\(why))")
            }
        })
    engine.sync([RelabelEngine.WatchedFolder(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, url: folder, kind: kind)])
    print("Watching \(folder.path) for new \(kind.displayName) files for \(Int(seconds))s...")
    try? await Task.sleep(for: .seconds(seconds))

case "tidy":
    guard args.count >= 2 else { usage() }
    let folder = expand(args[1])
    var prefs = NamingPreferences()
    if let l = option("--length"), let len = NameLength(rawValue: l) { prefs.length = len }
    switch option("--date") { case "start": prefs.dateStyle = .atStart; case "end": prefs.dateStyle = .atEnd; default: break }
    let dry = args.contains("--dry-run")
    let history = RenameHistory(), markers = ProcessedMarkers()
    let batchPrefs = prefs
    let pipeline = NamingPipeline(history: history, markers: markers, prefs: { batchPrefs })
    print("Warming up text recognition...")
    await TextExtractor.warmUp()
    var items = TidyPlanner.scan(folder: folder, markers: markers)
    if items.isEmpty { print("Nothing to tidy up"); exit(0) }
    let box = ItemsBox(items)
    await TidyPlanner.proposeAll(items, includeGood: args.contains("--all"), prefs: prefs, pipeline: pipeline) { i, item, done, total in
        box.set(i, item)
        if item.status != .naming { print("Naming \(done) of \(total)") }
    }
    items = box.items
    if args.contains("--all") { for i in items.indices { items[i].selected = items[i].status == .ready } }
    let preview = TidyPlanner.previewNames(items, prefs: prefs)
    for item in items {
        let note = item.alreadyGood && !args.contains("--all") ? "(already has a good name)" : ""
        switch item.status {
        case .ready: print("\(item.selected ? "✓" : " ") \(item.url.lastPathComponent)  ->  \(preview[item.id] ?? "-")")
        case .kept(let why), .failed(let why): print("  \(item.url.lastPathComponent)  (\(why))")
        default: print("  \(item.url.lastPathComponent)  \(note)")
        }
    }
    if dry { print("Dry run: nothing renamed."); exit(0) }
    let result = TidyPlanner.apply(items, prefs: prefs, history: history, markers: markers)
    print("Renamed \(result.records.count) files. Undo with: relabel undo (once per file)")
    for f in result.failures { print("FAILED \(f.name): \(f.reason)") }

case "eval":
    let casesURL = expand(args.count >= 2 && !args[1].hasPrefix("--") ? args[1] : "Evals/cases.json")
    struct EvalCase: Decodable { var match: String; var must: [[String]]; var mustNot: [String]? }
    struct EvalFile: Decodable { var ui: [String]; var cases: [EvalCase] }
    guard let data = try? Data(contentsOf: casesURL), let file = try? JSONDecoder().decode(EvalFile.self, from: data) else {
        print("Can't read \(casesURL.path)"); exit(1)
    }
    let root = casesURL.deletingLastPathComponent().deletingLastPathComponent()
    // Cases for your own files live in Samples/cases.json, which is git-ignored and never leaves your Mac.
    struct LocalFile: Decodable { var cases: [EvalCase] }
    var cases = file.cases
    if let d = try? Data(contentsOf: root.appendingPathComponent("Samples/cases.json")), let extra = try? JSONDecoder().decode(LocalFile.self, from: d) {
        cases += extra.cases
    }
    let dirs = ["Evals/images", "Samples", "Fixtures"].map { root.appendingPathComponent($0) }
    let textOnly = args.contains("--text-only")
    print("Warming up text recognition...")
    await TextExtractor.warmUp()
    var passed = 0, ran = 0
    let only = option("--only")
    for c in cases where only == nil || c.match.contains(only!) {
        let found = dirs.compactMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
            .flatMap { $0 }.first { $0.lastPathComponent.contains(c.match) }
        guard let url = found else { print("SKIP   \(c.match) (file not found)"); continue }
        do {
            let ctx = url.pathExtension.lowercased() == "pdf" ? try await TextExtractor.pdfContext(url: url)
                                                               : try await TextExtractor.screenshotContext(url: url)
            let t0 = Date()
            var prefs = NamingPreferences(); prefs.useImage = !textOnly
            let r = await NamingModel.name(for: ctx, prefs: prefs, forceTextOnly: textOnly)
            let title = r.result.title, low = title.lowercased()
            var problems: [String] = []
            for group in c.must where !group.contains(where: { low.contains($0.lowercased()) }) { problems.append("missing " + group.joined(separator: "/")) }
            let banned = Set(file.ui + (c.mustNot ?? []))
            let words = Set(low.split(whereSeparator: { !$0.isLetter }).map(String.init))
            for b in banned where words.contains(b) { problems.append("has '\(b)'") }
            if title.split(separator: " ").count > 10 { problems.append("too long") }
            if r.result.source == .fallback { problems.append("basic naming") }
            ran += 1; if problems.isEmpty { passed += 1 }
            print(String(format: "%@ %4.1fs  %@  <- %@%@", problems.isEmpty ? "PASS" : "FAIL", Date().timeIntervalSince(t0), title.padding(toLength: 52, withPad: " ", startingAt: 0), c.match,
                         problems.isEmpty ? "" : "   (" + problems.joined(separator: "; ") + ")"))
        } catch { print("ERROR  \(c.match): \(error.localizedDescription)") }
    }
    print("Score: \(passed) / \(ran)")

case "history":
    for r in RenameHistory().recent(20) {
        print("\(r.state == .applied ? "●" : "○") \(r.time.formatted(date: .abbreviated, time: .standard))  \(r.oldName)  ->  \(r.newName)  [\(r.source.rawValue)]")
    }

case "undo":
    let h = RenameHistory()
    guard let last = h.all().last(where: { $0.state == .applied }) else { print("Nothing to undo."); exit(0) }
    do { let r = try h.undo(id: last.id); print("Restored \(r.oldName)") }
    catch { print(error.localizedDescription); exit(1) }

default: usage()
}

final class ItemsBox: @unchecked Sendable {
    private let lock = NSLock(); private var v: [TidyItem]
    init(_ v: [TidyItem]) { self.v = v }
    var items: [TidyItem] { lock.withLock { v } }
    func set(_ i: Int, _ item: TidyItem) { lock.withLock { v[i] = item } }
}
