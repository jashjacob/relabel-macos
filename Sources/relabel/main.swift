import Foundation
import RelabelCore

// relabel spike <file> [--app "Excel"]   -> names for all three lengths + basic fallback
func usage() -> Never {
    print("""
    usage:
      relabel spike <file.png|jpg|heic|pdf> [--app <frontmost app>] [--prompt]
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.first == "spike", args.count >= 2 else { usage() }
let url = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
var appName: String?
if let i = args.firstIndex(of: "--app"), i + 1 < args.count { appName = args[i + 1] }
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
    print("Error: \(error.localizedDescription)")
    exit(1)
}
