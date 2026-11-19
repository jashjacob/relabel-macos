import SwiftUI
import AppKit
import ImageIO
import PDFKit
import RelabelCore

/// Small cache of file thumbnails (ImageIO and PDFKit only), keyed by history record.
@MainActor
@Observable
final class ThumbnailCache {
    private(set) var images: [UUID: NSImage] = [:]
    @ObservationIgnored private var loading: Set<UUID> = []

    func forget(_ id: UUID) { images[id] = nil }

    func request(_ r: HistoryRecord) {
        guard images[r.id] == nil, loading.insert(r.id).inserted else { return }
        let url = r.state == .applied ? r.newURL : r.oldURL
        let isPDF = r.kind == .pdf
        let id = r.id
        Task.detached(priority: .utility) {
            let img = Self.make(url, pdf: isPDF)
            await MainActor.run { [weak self] in
                if let img { self?.images[id] = img }
                self?.loading.remove(id)
            }
        }
    }

    nonisolated private static func make(_ url: URL, pdf: Bool) -> NSImage? {
        if pdf {
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: NSSize(width: 80, height: 80), for: .mediaBox)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 96,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct RecentRenamesList: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent renames").font(.subheadline).foregroundStyle(.secondary)
            if model.recents.isEmpty {
                Text("Nothing named yet.")
                    .font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.recents) { RecentRow(model: model, record: $0) }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }
}

struct RecentRow: View {
    let model: AppModel
    let record: HistoryRecord
    @FocusState private var focused: Bool

    private var editing: Bool { model.editingID == record.id }
    private var applied: Bool { record.state == .applied }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    nameView
                    Text(applied ? record.oldName : "Restored to original name")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button { applied ? model.undoRow(record) : model.redoRow(record) } label: {
                    Image(systemName: applied ? "arrow.uturn.backward" : "arrow.uturn.forward")
                }
                .buttonStyle(.borderless)
                .help(applied ? "Undo: put the original name back" : "Redo: use the new name again")
                .accessibilityLabel(applied ? "Undo rename of \(record.newName)" : "Redo rename of \(record.oldName)")
                Button { model.showInFinder(record) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).help("Show in Finder")
                    .accessibilityLabel("Show \(applied ? record.newName : record.oldName) in Finder")
            }
            if let err = model.rowErrors[record.id] {
                Text(err).font(.caption).foregroundStyle(.orange).padding(.leading, 44)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .opacity(applied ? 1 : 0.65)
        .onAppear { model.thumbnails.request(record) }
    }

    @ViewBuilder private var nameView: some View {
        if editing {
            TextField("Name", text: Bindable(model).editText)
                .textFieldStyle(.roundedBorder).font(.callout)
                .focused($focused)
                .onSubmit { model.commitEdit(record) }
                .onExitCommand { model.cancelEdit() }
                .onAppear { focused = true }
                .accessibilityLabel("New name. Press Return to rename, Escape to cancel")
        } else {
            Text(applied ? record.newName : record.oldName)
                .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                .contentShape(Rectangle())
                .onTapGesture { if applied { model.beginEdit(record) } }
                .help(applied ? "Click to edit the name" : "")
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let img = model.thumbnails.images[record.id] {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 36, height: 36)
                .overlay(Image(systemName: record.kind == .pdf ? "doc.text" : "photo").foregroundStyle(.secondary))
        }
    }
}
