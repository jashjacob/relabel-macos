import Foundation

public enum JobOutcome: Sendable, Equatable {
    case renamed(HistoryRecord)
    /// Original name kept (nothing better found, or already fine). Marked so it isn't retried endlessly.
    case kept(String)
    /// Couldn't name it this time; the user can retry.
    case failed(String)
    /// Nothing to do (file moved before it was named, or already handled).
    case skipped(String)
}

public typealias NamerFunction = @Sendable (FileContext, NamingPreferences) async -> (result: NamingResult, note: String?)

/// extract text -> ask the model (or fall back) -> sanitize -> rename -> record.
public final class NamingPipeline: @unchecked Sendable {
    public static let noBetterName = "No better name found"
    private let history: RenameHistory
    private let markers: ProcessedMarkers
    private let prefs: @Sendable () -> NamingPreferences
    private let namer: NamerFunction

    public init(history: RenameHistory, markers: ProcessedMarkers, prefs: @escaping @Sendable () -> NamingPreferences,
                namer: @escaping NamerFunction = { ctx, p in await NamingModel.name(for: ctx, prefs: p) }) {
        self.history = history; self.markers = markers; self.prefs = prefs; self.namer = namer
    }

    public struct Proposal: Sendable, Equatable {
        public var title: String
        public var category: String
        public var source: NamingResult.Source
        public var fileDate: Date
        public var summary: String
    }

    public enum ProposalOutcome: Sendable, Equatable {
        case proposal(Proposal)
        case kept(String)       // nothing better found
        case failed(String)     // couldn't name it this time
    }

    /// Everything up to (not including) the rename: extract text, ask the model, sanity-check the answer.
    public func propose(url: URL, kind: FileKind, appName: String?, prefs p: NamingPreferences) async -> ProposalOutcome {
        let ctx: FileContext
        do {
            ctx = kind == .pdf ? try await TextExtractor.pdfContext(url: url)
                               : try await TextExtractor.screenshotContext(url: url, appName: appName)
        } catch ExtractionError.notAnImage {
            return .kept(ExtractionError.notAnImage.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
        let (result, _) = await namer(ctx, p)
        let hasContent = !ctx.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !Sanitizer.cleanTitle(result.title).isEmpty, hasContent || result.source == .model else {
            return .kept(Self.noBetterName)
        }
        return .proposal(Proposal(title: result.title, category: result.category, source: result.source,
                                  fileDate: ctx.fileDate, summary: String(ctx.text.prefix(300))))
    }

    public func process(_ job: RenameJob) async -> JobOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: job.url.path) else { return .skipped("The file was moved before it was named.") }
        if job.source == .auto, markers.isProcessed(job.url) { return .skipped("Already handled.") }
        let p = prefs()
        let proposal: Proposal
        switch await propose(url: job.url, kind: job.kind, appName: job.appName, prefs: p) {
        case .failed(let why): return .failed(why)
        case .kept(let why): markers.mark(job.url, .kept); return .kept(why)
        case .proposal(let pr): proposal = pr
        }
        let base = Sanitizer.baseName(title: proposal.title, date: proposal.fileDate, style: p.dateStyle)
        let ext = job.url.pathExtension
        let dir = job.url.deletingLastPathComponent()
        let target = Sanitizer.uniqueURL(directory: dir, base: base, ext: ext) {
            $0.path != job.url.path && fm.fileExists(atPath: $0.path)
        }
        if target.path == job.url.path {
            markers.mark(job.url, .kept)
            return .kept("Already has a good name")
        }
        markers.mark(job.url, .renamed)          // before the move, so the watcher can't pick the new name up
        do {
            let rec = try history.rename(from: job.url, to: target, source: job.source, kind: job.kind,
                                         relabelName: target.lastPathComponent, summary: proposal.summary)
            return .renamed(rec)
        } catch {
            markers.unmark(job.url)
            return .failed("Couldn't rename it: \(error.localizedDescription)")
        }
    }
}

public enum QueueState: Sendable, Equatable { case idle, one, batch(Int) }

/// Handles one file at a time. A burst of files shows as a batch.
public actor RenameQueue {
    private var jobs: [RenameJob] = []
    private var running = false
    private let pipeline: NamingPipeline
    private let onState: @Sendable (QueueState) -> Void
    private let onOutcome: @Sendable (RenameJob, JobOutcome) -> Void

    public init(pipeline: NamingPipeline, onState: @escaping @Sendable (QueueState) -> Void,
                onOutcome: @escaping @Sendable (RenameJob, JobOutcome) -> Void) {
        self.pipeline = pipeline; self.onState = onState; self.onOutcome = onOutcome
    }

    public func enqueue(_ job: RenameJob) {
        jobs.append(job)
        guard !running else { return }
        running = true
        Task { await run() }
    }

    private func run() async {
        while !jobs.isEmpty {
            onState(jobs.count > 1 ? .batch(jobs.count) : .one)
            let job = jobs.removeFirst()
            let outcome = await pipeline.process(job)
            onOutcome(job, outcome)
        }
        running = false
        onState(.idle)
    }
}
