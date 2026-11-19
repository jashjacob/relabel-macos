import SwiftUI
import RelabelCore

/// Live name previews for Settings: a built-in sample, and any file the user drops on the preview.
@MainActor
@Observable
final class NamingPreview {
    struct Result: Equatable { var length: NameLength; var name: String; var viaModel: Bool }

    private(set) var sample: [Result] = []
    private(set) var samplePDF: Result?
    private(set) var sampleBusy = false
    private(set) var note: String?

    var targeted = false
    private(set) var droppedName: String?
    private(set) var dropped: [Result] = []
    private(set) var dropBusy = false
    private(set) var dropError: String?

    private static let sampleDate = Date(timeIntervalSince1970: 1_795_000_000)   // 2026-11-18, only for the date style demo

    private static var sampleScreenshot: FileContext {
        FileContext(kind: .screenshot, originalName: "Screenshot.png",
                    text: "Quarterly Budget Forecast 2027\nDepartment Q1 Q2 Q3 Q4\nMarketing 42,000 45,500 39,000 51,200\nEngineering 118,400 121,900 125,000 130,300\nOperations 36,750 37,100 38,900 40,000\nTotal 197,150 204,500 202,900 221,500",
                    labels: ["document", "printed page"], appName: "Excel", usedOCR: true, fileDate: sampleDate)
    }

    private static var samplePDFContext: FileContext {
        FileContext(kind: .pdf, originalName: "scan0001.pdf",
                    text: "ACME Plumbing Ltd\nINVOICE\nInvoice number INV-20481\nInvoice date 2 November 2026\nBill to Harbour Street Dental Practice\nEmergency pipe repair and boiler service\nAmount due 1,284.50 payable within 30 days",
                    pdfAuthor: "ACME Plumbing Ltd", fileDate: sampleDate)
    }

    private func display(_ r: NamingResult, _ ctx: FileContext, ext: String, _ p: NamingPreferences) -> String {
        Sanitizer.baseName(title: r.title, date: ctx.fileDate, style: p.dateStyle) + "." + ext
    }

    /// Names the built-in sample at all three lengths (text only, so it's quick).
    func refreshSample(_ prefs: NamingPreferences) async {
        DropDebug.log("sample start")
        sampleBusy = true
        defer { sampleBusy = false }
        var p = prefs; p.useImage = false
        var out: [Result] = []
        note = NamingModel.availability().explanation.map { _ in "Apple Intelligence isn't available, so every length gives the same name." }
        for length in NameLength.allCases {
            if Task.isCancelled { return }
            p.length = length
            let r = await NamingModel.name(for: Self.sampleScreenshot, prefs: p)
            DropDebug.log("sample \(length) -> \(r.result.title) \(r.note ?? "")")
            out.append(Result(length: length, name: display(r.result, Self.sampleScreenshot, ext: "png", p), viaModel: r.result.source == .model))
        }
        sample = out
        if !prefs.customPDFInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            p.length = prefs.length
            let r = await NamingModel.name(for: Self.samplePDFContext, prefs: p)
            samplePDF = Result(length: p.length, name: display(r.result, Self.samplePDFContext, ext: "pdf", p), viaModel: r.result.source == .model)
        } else {
            samplePDF = nil
        }
    }

    /// Reads a dropped image or PDF and shows what it would be called. Nothing is renamed.
    func preview(url: URL, prefs: NamingPreferences) async {
        guard let kind = FileEligibility.kindForDropped(url) else {
            dropError = "Drop an image or a PDF."; dropped = []; droppedName = nil; return
        }
        dropBusy = true; dropError = nil; droppedName = url.lastPathComponent; dropped = []
        defer { dropBusy = false }
        do {
            let ctx = kind == .pdf ? try await TextExtractor.pdfContext(url: url) : try await TextExtractor.screenshotContext(url: url)
            var out: [Result] = []
            var p = prefs
            for length in NameLength.allCases {
                p.length = length
                let r = await NamingModel.name(for: ctx, prefs: p)
                out.append(Result(length: length, name: display(r.result, ctx, ext: url.pathExtension, p), viaModel: r.result.source == .model))
                dropped = out
            }
        } catch {
            dropError = error.localizedDescription
        }
    }
}
