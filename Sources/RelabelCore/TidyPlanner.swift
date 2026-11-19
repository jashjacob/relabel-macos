import Foundation

public struct TidyItem: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable { case pending, naming, ready, kept(String), failed(String) }
    public var id = UUID()
    public var url: URL
    public var kind: FileKind
    /// Already has a name a person chose (or Relabel gave it). Dimmed and unchecked by default.
    public var alreadyGood: Bool
    public var status: Status = .pending
    public var title: String?
    public var fileDate: Date
    public var summary = ""
    public var selected: Bool
    /// The user's own edit of the proposed name (without extension). Wins over the model's title.
    public var editedBase: String?
}

public struct DateFix: Identifiable, Sendable, Equatable {
    public var id = UUID()
    public var url: URL
    public var kind: FileKind
    public var newName: String
    public var oldName: String { url.lastPathComponent }
}

/// Batch naming of a whole folder: scan, propose (nothing is renamed), apply, undo all.
public enum TidyPlanner {
    /// Every image and PDF directly inside the folder, newest first.
    public static func scan(folder: URL, markers: ProcessedMarkers) -> [TidyItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> TidyItem? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let kind = FileEligibility.kindForDropped(url) else { return nil }
            let good = !NameQuality.looksGenerated(url.lastPathComponent) || markers.isProcessed(url)
            return TidyItem(url: url, kind: kind, alreadyGood: good, fileDate: v.creationDate ?? Date(), selected: !good)
        }
        .sorted { (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                > (try? $1.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    }

    /// Asks the model for a name for every item that should get one. Reports progress after each file.
    public static func proposeAll(_ items: [TidyItem], includeGood: Bool, prefs: NamingPreferences, pipeline: NamingPipeline,
                                  onUpdate: @Sendable (Int, TidyItem, _ done: Int, _ total: Int) -> Void) async {
        let todo = items.indices.filter { (includeGood || !items[$0].alreadyGood) && items[$0].status != .ready }
        var done = 0
        for i in todo {
            if Task.isCancelled { return }
            var item = items[i]
            item.status = .naming
            onUpdate(i, item, done, todo.count)
            switch await pipeline.propose(url: item.url, kind: item.kind, appName: nil, prefs: prefs) {
            case .proposal(let p):
                item.title = p.title; item.fileDate = p.fileDate; item.summary = p.summary; item.status = .ready
            case .kept(let why): item.status = .kept(why); item.selected = false
            case .failed(let why): item.status = .failed(why); item.selected = false
            }
            done += 1
            onUpdate(i, item, done, todo.count)
        }
    }

    public static func baseName(_ item: TidyItem, prefs: NamingPreferences) -> String? {
        if let e = item.editedBase { let c = Sanitizer.cleanTitle(e); return c.isEmpty ? nil : c }
        guard let t = item.title else { return nil }
        let b = Sanitizer.baseName(title: t, date: item.fileDate, style: prefs.dateStyle)
        return b.isEmpty ? nil : b
    }

    /// The file names that would result, including " 2" suffixes when proposals collide with each other or with files.
    public static func previewNames(_ items: [TidyItem], prefs: NamingPreferences) -> [UUID: String] {
        var taken = Set<String>()
        var out: [UUID: String] = [:]
        let fm = FileManager.default
        let current = Set(items.map { $0.url.lastPathComponent.lowercased() })
        for item in items where item.selected {
            guard let base = baseName(item, prefs: prefs) else { continue }
            let dir = item.url.deletingLastPathComponent()
            let url = Sanitizer.uniqueURL(directory: dir, base: base, ext: item.url.pathExtension) {
                let n = $0.lastPathComponent.lowercased()
                if n == item.url.lastPathComponent.lowercased() { return false }
                return taken.contains(n) || current.contains(n) || fm.fileExists(atPath: $0.path)
            }
            taken.insert(url.lastPathComponent.lowercased())
            out[item.id] = url.lastPathComponent
        }
        return out
    }

    public struct ApplyResult: Sendable {
        public var records: [HistoryRecord] = []
        public var failures: [(name: String, reason: String)] = []
    }

    /// Renames every selected item that has a name. Never overwrites; the whole batch can be undone with `undoAll`.
    public static func apply(_ items: [TidyItem], prefs: NamingPreferences, history: RenameHistory, markers: ProcessedMarkers,
                             progress: (Int, Int) -> Void = { _, _ in }) -> ApplyResult {
        var result = ApplyResult()
        let chosen = items.filter { $0.selected && baseName($0, prefs: prefs) != nil }
        for (n, item) in chosen.enumerated() {
            progress(n, chosen.count)
            guard let base = baseName(item, prefs: prefs) else { continue }
            let target = Sanitizer.uniqueURL(directory: item.url.deletingLastPathComponent(), base: base, ext: item.url.pathExtension) {
                $0.path != item.url.path && FileManager.default.fileExists(atPath: $0.path)
            }
            if target.path == item.url.path { continue }
            markers.mark(item.url, .renamed)
            do {
                result.records.append(try history.rename(from: item.url, to: target, source: .tidy, kind: item.kind,
                                                         relabelName: target.lastPathComponent, summary: item.summary))
            } catch {
                markers.unmark(item.url)
                result.failures.append((item.url.lastPathComponent, error.localizedDescription))
            }
        }
        progress(chosen.count, chosen.count)
        return result
    }

    /// Reverts a whole batch, newest first.
    public static func undoAll(_ records: [HistoryRecord], history: RenameHistory) -> [(name: String, reason: String)] {
        var failures: [(String, String)] = []
        for r in records.reversed() {
            do { try history.undo(id: r.id) } catch { failures.append((r.newName, error.localizedDescription)) }
        }
        return failures
    }

    // MARK: Dates in earlier names

    /// Files in the folder whose names have a date at the start or end that differs from `style`.
    public static func dateFixes(folder: URL, style: DateStyle) -> [DateFix] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> DateFix? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let kind = FileEligibility.kindForDropped(url),
                  let stem = DateTokens.restyle(stem: url.deletingPathExtension().lastPathComponent, to: style) else { return nil }
            let ext = url.pathExtension
            return DateFix(url: url, kind: kind, newName: ext.isEmpty ? stem : stem + "." + ext)
        }
        .sorted { $0.oldName < $1.oldName }
    }

    public static func applyDateFixes(_ fixes: [DateFix], history: RenameHistory, markers: ProcessedMarkers) -> ApplyResult {
        var result = ApplyResult()
        for fix in fixes {
            let ext = fix.url.pathExtension
            let base = (fix.newName as NSString).deletingPathExtension
            let target = Sanitizer.uniqueURL(directory: fix.url.deletingLastPathComponent(), base: base, ext: ext)
            markers.mark(fix.url, .renamed)
            do {
                result.records.append(try history.rename(from: fix.url, to: target, source: .tidy, kind: fix.kind,
                                                         relabelName: target.lastPathComponent, summary: ""))
            } catch {
                markers.unmark(fix.url)
                result.failures.append((fix.oldName, error.localizedDescription))
            }
        }
        return result
    }
}
