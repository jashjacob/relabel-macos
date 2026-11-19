import SwiftUI
import RelabelCore

@MainActor
@Observable
final class TidyModel {
    enum Phase: Equatable { case idle, naming(done: Int, total: Int), ready, renaming(done: Int, total: Int), done }

    private unowned let app: AppModel
    let thumbs = ThumbnailCache()
    var folder: URL?
    private(set) var items: [TidyItem] = []
    private(set) var phase: Phase = .idle
    private(set) var records: [HistoryRecord] = []
    private(set) var failures: [String] = []
    private(set) var dateFixes: [DateFix] = []
    var dateMessage: String?
    var undoMessage: String?
    var editingID: UUID?
    var editText = ""
    var length: NameLength = .standard { didSet { if oldValue != length { renameAgain() } } }
    var dateStyle: DateStyle = .none { didSet { if oldValue != dateStyle { refreshDateFixes() } } }
    var includeGood = false { didSet { if oldValue != includeGood { applyIncludeGood() } } }
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var batchPrefs: NamingPreferences {
        var p = app.prefs
        p.length = length; p.dateStyle = dateStyle
        return p
    }

    var preview: [UUID: String] { TidyPlanner.previewNames(items, prefs: batchPrefs) }
    var selectedCount: Int { items.filter { $0.selected && $0.status == .ready || $0.selected && $0.editedBase != nil }.count }
    var visibleItems: [TidyItem] { includeGood ? items : items.filter { !$0.alreadyGood || $0.status != .pending } }

    func chooseFolder() {
        if let url = FolderPicker.choose(message: "Choose a folder to tidy up", startingAt: folder ?? SuggestedFolders.downloads()) { open(folder: url) }
    }

    // MARK: Flow

    func open(folder: URL) {
        task?.cancel()
        self.folder = folder
        length = app.prefs.length
        dateStyle = app.prefs.dateStyle
        includeGood = false
        records = []; failures = []; undoMessage = nil; dateMessage = nil; editingID = nil
        items = TidyPlanner.scan(folder: folder, markers: app.engine.markers)
        phase = .ready
        refreshDateFixes()
        generate()
    }

    func newBatch() {
        if let f = folder { open(folder: f) }
    }

    private func generate() {
        task?.cancel()
        let prefs = batchPrefs
        let snapshot = items
        let include = includeGood
        guard snapshot.contains(where: { (include || !$0.alreadyGood) && $0.status != .ready }) else { phase = .ready; return }
        phase = .naming(done: 0, total: snapshot.filter { include || !$0.alreadyGood }.count)
        let pipeline = NamingPipeline(history: app.engine.history, markers: app.engine.markers, prefs: { prefs })
        let sink: @Sendable (Int, TidyItem, Int, Int) -> Void = { [weak self] i, item, done, total in
            Task { @MainActor in self?.applyUpdate(i, item, done, total) }
        }
        task = Task { [weak self] in
            await TidyPlanner.proposeAll(snapshot, includeGood: include, prefs: prefs, pipeline: pipeline) { i, item, done, total in
                sink(i, item, done, total)
            }
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                if case .naming = phase { phase = .ready }
            }
        }
    }

    private func applyUpdate(_ i: Int, _ item: TidyItem, _ done: Int, _ total: Int) {
        guard i < items.count, items[i].url == item.url else { return }
        var updated = item
        updated.editedBase = items[i].editedBase
        if item.status == .ready { updated.selected = items[i].selected || (!items[i].alreadyGood || includeGood) && items[i].status != .ready }
        items[i] = updated
        if item.status != .naming { phase = .naming(done: done, total: total) }
    }

    /// A different length needs new names from the model; date style only changes how the preview is built.
    private func renameAgain() {
        guard folder != nil, phase != .done else { return }
        for i in items.indices where items[i].status == .ready || items[i].status != .pending && items[i].alreadyGood == false {
            if items[i].editedBase == nil { items[i].status = .pending; items[i].title = nil }
        }
        generate()
    }

    private func applyIncludeGood() {
        guard phase != .done else { return }
        for i in items.indices where items[i].alreadyGood { items[i].selected = includeGood }
        if includeGood { generate() }
    }

    func setSelected(_ id: UUID, _ on: Bool) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].selected = on }
    }

    func selectAll(_ on: Bool) {
        for i in items.indices {
            let eligible = items[i].status == .ready && (includeGood || !items[i].alreadyGood)
            items[i].selected = on && eligible
        }
    }

    func beginEdit(_ item: TidyItem) {
        editingID = item.id
        editText = (preview[item.id].map { ($0 as NSString).deletingPathExtension }) ?? item.title ?? ""
    }
    func cancelEdit() { editingID = nil }
    func commitEdit(_ item: TidyItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            let c = Sanitizer.cleanTitle(editText)
            if !c.isEmpty { items[i].editedBase = c; items[i].selected = true; if items[i].status != .ready { items[i].status = .ready } }
        }
        editingID = nil
    }

    func renameSelected() {
        task?.cancel()
        let chosen = items
        phase = .renaming(done: 0, total: selectedCount)
        let result = TidyPlanner.apply(chosen, prefs: batchPrefs, history: app.engine.history, markers: app.engine.markers) { [weak self] n, total in
            self?.phase = .renaming(done: n, total: total)
        }
        records = result.records
        failures = result.failures.map { "\($0.name): \($0.reason)" }
        phase = .done
        app.historyChanged()
    }

    func undoAll() {
        let fails = TidyPlanner.undoAll(records, history: app.engine.history)
        undoMessage = fails.isEmpty ? "All \(records.count) files are back to their original names." :
            "\(records.count - fails.count) restored. \(fails.count) couldn't be restored: \(fails.first!.reason)"
        if fails.isEmpty { records = [] }
        app.historyChanged()
    }

    // MARK: Dates in earlier names

    func refreshDateFixes() {
        guard let folder else { dateFixes = []; return }
        dateFixes = TidyPlanner.dateFixes(folder: folder, style: dateStyle)
    }

    func applyDateFixes() {
        let r = TidyPlanner.applyDateFixes(dateFixes, history: app.engine.history, markers: app.engine.markers)
        dateMessage = r.failures.isEmpty ? "Updated \(r.records.count) names." : "Updated \(r.records.count). Couldn't update \(r.failures.count)."
        if let f = folder { items = TidyPlanner.scan(folder: f, markers: app.engine.markers) ; if phase != .done { generate() } }
        refreshDateFixes()
        app.historyChanged()
    }
}
