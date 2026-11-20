import Foundation
import Vision
import PDFKit
import ImageIO
import AppKit

public enum ExtractionError: Error, LocalizedError, Sendable {
    case notAnImage, timedOut, unreadablePDF, lockedPDF, recognitionFailed

    public var errorDescription: String? {
        switch self {
        case .notAnImage: "Not an image Relabel can open"
        case .timedOut: "Text recognition took too long"
        case .unreadablePDF: "Relabel can't read this PDF"
        case .lockedPDF: "This PDF is locked"
        case .recognitionFailed: "Text recognition hit a problem. Try again in a moment."
        }
    }
}

/// Vision (OCR + image labels) and PDFKit text extraction. Everything runs on device.
public enum TextExtractor {
    nonisolated(unsafe) public static var ocrTimeout: TimeInterval = 20
    /// The first accurate recognition on a Mac loads the text model, which can take about a minute once.
    nonisolated(unsafe) public static var firstRunTimeout: TimeInterval = 240
    public static let pdfPagesToRead = 3
    private static let warmFlag = WarmFlag()
    private static let gate = RecognitionGate()

    /// True once Vision's text model has loaded (the first run on a Mac can take about a minute).
    public static var isWarm: Bool { warmFlag.isWarm }

    /// Loads Vision's text model in the background so the first real file isn't slow. Safe to call repeatedly.
    public static func warmUp() async {
        guard !warmFlag.isWarm else { return }
        await gate.acquire()
        defer { Task { await gate.release() } }
        guard !warmFlag.isWarm else { return }
        let size = 200
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let img = ctx.makeImage(), let tmp = writeTempPNG(img) else { return }
        defer { try? FileManager.default.removeItem(at: tmp) }
        if (try? await OCRHelper.run(imageURL: tmp, fast: false, classify: false, timeout: firstRunTimeout)) != nil {
            warmFlag.isWarm = true
        }
    }

    // MARK: Screenshots

    public static func screenshotContext(url: URL, appName: String? = nil) async throws -> FileContext {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ExtractionError.notAnImage }
        let (text, labels) = try await recognize(fileAt: url, classify: true)
        var ctx = FileContext(kind: .screenshot, originalName: url.lastPathComponent, text: text, labels: labels,
                              appName: appName, usedOCR: true, fileDate: creationDate(url))
        ctx.image = downscaled(src).map(ImageBox.init)
        return ctx
    }

    // MARK: PDFs

    public static func pdfContext(url: URL) async throws -> FileContext {
        guard let doc = PDFDocument(url: url) else { throw ExtractionError.unreadablePDF }
        if doc.isLocked { throw ExtractionError.lockedPDF }
        var parts: [String] = []
        var usedOCR = false
        for i in 0..<min(pdfPagesToRead, doc.pageCount) {
            guard let page = doc.page(at: i) else { continue }
            let layer = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if layer.count >= 25 { parts.append(layer); continue }
            // No usable text layer: render the page and OCR it.
            if let cg = render(page) {
                let (t, _) = try await recognize(cg, classify: false)
                if !t.isEmpty { parts.append(t); usedOCR = true }
            }
        }
        let attrs = doc.documentAttributes ?? [:]
        let title = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var ctx = FileContext(kind: .pdf, originalName: url.lastPathComponent, text: parts.joined(separator: "\n\n"),
                              pdfTitle: title?.isEmpty == false ? title : nil,
                              pdfAuthor: author?.isEmpty == false ? author : nil,
                              pdfCreated: attrs[PDFDocumentAttribute.creationDateAttribute] as? Date,
                              usedOCR: usedOCR, fileDate: creationDate(url))
        if let first = doc.page(at: 0), let cg = render(first, maxSide: CGFloat(modelImageSide)) { ctx.image = ImageBox(cg) }
        return ctx
    }

    // MARK: Vision

    /// Recognizes an in-memory image (a rendered PDF page) by writing it to a temporary file first.
    static func recognize(_ image: CGImage, classify: Bool) async throws -> (String, [String]) {
        guard let tmp = writeTempPNG(image) else { throw ExtractionError.recognitionFailed }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await recognize(fileAt: tmp, classify: classify)
    }

    /// OCR text ordered top to bottom, plus top image labels.
    ///
    /// The work runs in a short-lived helper process (see `OCRHelper`). Apple's text recognition can wedge
    /// inside Vision, and one stuck request blocks every later one in the same process. A helper that
    /// doesn't answer in time is killed, so a hang costs one file a delay and nothing more.
    /// One recognition at a time; if the accurate model errors, retry once, then use the fast level.
    static func recognize(fileAt url: URL, classify: Bool) async throws -> (String, [String]) {
        await gate.acquire()
        defer { Task { await gate.release() } }
        let timeout = warmFlag.isWarm ? ocrTimeout : firstRunTimeout

        var out: OCRHelper.Output
        do {
            out = try await OCRHelper.run(imageURL: url, fast: false, classify: classify, timeout: timeout)
        } catch ExtractionError.timedOut {
            out = try await fastFallback(url, classify, timeout)             // accurate hung: skip it
        } catch {
            try? await Task.sleep(for: .seconds(0.7))
            do { out = try await OCRHelper.run(imageURL: url, fast: false, classify: classify, timeout: timeout) }
            catch ExtractionError.timedOut { out = try await fastFallback(url, classify, timeout) }
            catch { out = try await fastFallback(url, classify, timeout) }
        }
        warmFlag.isWarm = true
        return (out.text, out.labels)
    }

    private static func fastFallback(_ url: URL, _ classify: Bool, _ timeout: TimeInterval) async throws -> OCRHelper.Output {
        do { return try await OCRHelper.run(imageURL: url, fast: true, classify: classify, timeout: timeout) }
        catch ExtractionError.timedOut { throw ExtractionError.timedOut }
        catch { throw ExtractionError.recognitionFailed }
    }

    static func writeTempPNG(_ image: CGImage) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relabel-\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    /// Vision's boxes use a bottom-left origin. Text on the same row is joined into one line (see `OCRRows`).
    static func orderTopToBottom(_ observations: [VNRecognizedTextObservation]) -> [String] {
        OCRRows.lines(observations.compactMap { o in
            guard let t = o.topCandidates(1).first?.string else { return nil }
            let b = o.boundingBox
            return TextBox(text: t, minX: b.minX, maxX: b.maxX, minY: b.minY, maxY: b.maxY)
        })
    }

    static func topLabels(_ results: [VNClassificationObservation]) -> [String] {
        results.filter { $0.confidence > 0.2 }.prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    /// Longest side of the picture shown to the model. Smaller is faster.
    public static let modelImageSide = 1024

    static func downscaled(_ src: CGImageSource, maxSide: Int = modelImageSide) -> CGImage? {
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSide,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func render(_ page: PDFPage, maxSide: CGFloat = 2200) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = min(2.0, maxSide / max(box.width, box.height))
        let size = NSSize(width: box.width * scale, height: box.height * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }
}

/// Lets one text recognition run at a time; the rest wait their turn.
private actor RecognitionGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

private final class WarmFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isWarm: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Runs blocking work off the caller and gives up after `seconds`.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
        let once = Once(cont)
        DispatchQueue.global(qos: .userInitiated).async { once.finish(Result { try work() }) }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.finish(.failure(ExtractionError.timedOut)) }
    }
}

private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { cont = c }
    func finish(_ r: Result<T, Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(with: r)
    }
}
