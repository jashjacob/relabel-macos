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
    public static let ocrTimeout: TimeInterval = 20
    /// The first accurate recognition on a Mac loads the text model, which can take about a minute once.
    public static let firstRunTimeout: TimeInterval = 240
    private static let warmFlag = WarmFlag()
    private static let gate = RecognitionGate()

    /// True once Vision's text model has loaded (the first run on a Mac can take about a minute).
    public static var isWarm: Bool { warmFlag.isWarm }

    /// Loads Vision's text model in the background so the first real file isn't slow. Safe to call repeatedly.
    public static func warmUp() async {
        guard !warmFlag.isWarm else { return }
        let size = 200
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let img = ctx.makeImage() else { return }
        await gate.acquire()
        defer { Task { await gate.release() } }
        guard !warmFlag.isWarm else { return }
        let ok = (try? await withTimeout(firstRunTimeout) {
            let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: img, options: [:]).perform([r])
            return true
        }) ?? false
        if ok { warmFlag.isWarm = true }
    }
    public static let pdfPagesToRead = 3

    // MARK: Screenshots

    public static func screenshotContext(url: URL, appName: String? = nil) async throws -> FileContext {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ExtractionError.notAnImage }
        let (text, labels) = try await recognize(image, classify: true)
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

    /// OCR text ordered top to bottom, plus top image labels.
    /// One recognition at a time (parallel ones make the system's text model crawl or fail), and if the accurate
    /// model errors (it sometimes does under load: "E5RT ... Code 13") retry once, then use the fast level.
    static func recognize(_ image: CGImage, classify: Bool) async throws -> (String, [String]) {
        await gate.acquire()
        defer { Task { await gate.release() } }
        let timeout = warmFlag.isWarm ? ocrTimeout : firstRunTimeout

        func read(_ level: VNRequestTextRecognitionLevel) async throws -> String {
            try await withTimeout(timeout) {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = level
                req.usesLanguageCorrection = level == .accurate
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
                return orderTopToBottom(req.results ?? []).joined(separator: "\n")
            }
        }

        let text: String
        do {
            text = try await read(.accurate)
        } catch ExtractionError.timedOut {
            throw ExtractionError.timedOut
        } catch {
            try? await Task.sleep(for: .seconds(0.7))
            do { text = try await read(.accurate) }
            catch ExtractionError.timedOut { throw ExtractionError.timedOut }
            catch {
                do { text = try await read(.fast) }
                catch ExtractionError.timedOut { throw ExtractionError.timedOut }
                catch { throw ExtractionError.recognitionFailed }
            }
        }
        warmFlag.isWarm = true

        // Labels are a nice-to-have: if classification fails, carry on without them.
        var labels: [String] = []
        if classify {
            labels = (try? await withTimeout(timeout) {
                let cls = VNClassifyImageRequest()
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([cls])
                return topLabels(cls.results ?? [])
            }) ?? []
        }
        return (text, labels)
    }

    /// Vision's boxes use a bottom-left origin, so the top of the image has the largest maxY.
    static func orderTopToBottom(_ observations: [VNRecognizedTextObservation]) -> [String] {
        observations
            .sorted { a, b in
                if abs(a.boundingBox.maxY - b.boundingBox.maxY) > 0.01 { return a.boundingBox.maxY > b.boundingBox.maxY }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
