import Foundation
import Vision
import ImageIO

/// Text recognition in a separate process.
///
/// Why: Apple's text recognizer can hang inside Vision (seen in practice after an "E5RT" error), and every
/// later request in that process then queues behind the stuck one. In its own process a hung recognition is
/// simply killed. The helper is this same executable started with a hidden flag; each `main` calls
/// `OCRHelper.runIfRequested()` first.
public enum OCRHelper {
    public static let flag = "--relabel-ocr-helper"

    struct Output: Codable { var text: String; var labels: [String] }

    // MARK: Helper side

    /// Call first thing in `main`. If this process was started as the helper, does the work and exits.
    public static func runIfRequested() {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 4 < a.count else { return }
        let imagePath = a[i + 1], fast = a[i + 2] == "fast", classify = a[i + 3] == "1", outPath = a[i + 4]
        if ProcessInfo.processInfo.environment["RELABEL_OCR_TEST_HANG"] == "1" { while true { sleep(1000) } }   // test hook
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: imagePath) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(2) }
        do {
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = fast ? .fast : .accurate
            text.usesLanguageCorrection = !fast
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([text])
            var labels: [String] = []
            if classify {   // labels are a nice-to-have
                let cls = VNClassifyImageRequest()
                if (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([cls])) != nil {
                    labels = TextExtractor.topLabels(cls.results ?? [])
                }
            }
            let out = Output(text: TextExtractor.orderTopToBottom(text.results ?? []).joined(separator: "\n"), labels: labels)
            try JSONEncoder().encode(out).write(to: URL(fileURLWithPath: outPath))
            exit(0)
        } catch {
            exit(1)
        }
    }

    // MARK: Parent side

    static func run(imageURL: URL, fast: Bool, classify: Bool, timeout: TimeInterval) async throws -> Output {
        guard let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]) as URL? else { throw ExtractionError.recognitionFailed }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("relabel-ocr-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outURL) }

        let result: Result<Void, Error> = await withCheckedContinuation { cont in
            let process = Process()
            process.executableURL = exe
            process.arguments = [flag, imageURL.path, fast ? "fast" : "accurate", classify ? "1" : "0", outURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let once = OnceBox(cont)
            process.terminationHandler = { p in
                once.finish(p.terminationStatus == 0 ? .success(()) : .failure(ExtractionError.recognitionFailed))
            }
            do { try process.run() } catch { once.finish(.failure(ExtractionError.recognitionFailed)); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    once.finish(.failure(ExtractionError.timedOut))     // answer first, then make sure it's gone
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
                }
            }
        }
        try result.get()
        guard let data = try? Data(contentsOf: outURL), let out = try? JSONDecoder().decode(Output.self, from: data) else {
            throw ExtractionError.recognitionFailed
        }
        return out
    }
}

private final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<Result<Void, Error>, Never>?
    init(_ c: CheckedContinuation<Result<Void, Error>, Never>) { cont = c }
    func finish(_ r: Result<Void, Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: r)
    }
}
