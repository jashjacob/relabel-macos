import Foundation
import RelabelCore

// relabel spike <file> [--app <name>] [--prompt]
// relabel watch <folder> [--kind screenshots|pdf] [--seconds N]
// relabel history
// relabel undo
// Set RELABEL_SUPPORT_DIR to keep history and markers somewhere other than ~/Library/Application Support/Relabel.
func usage() -> Never {
    print("""
    usage:
      relabel spike <file> [--app <frontmost app>] [--prompt]   names for all three lengths + basic fallback
      relabel watch <folder> [--kind screenshots|pdf] [--seconds N]   name new files as they arrive
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
