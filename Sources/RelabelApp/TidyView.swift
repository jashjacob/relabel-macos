import SwiftUI
import RelabelCore

struct TidyView: View {
    let model: TidyModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                Text(model.folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "No folder").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Another Folder…") { model.chooseFolder() }
            }
            HStack(spacing: 16) {
                Picker("Length", selection: Bindable(model).length) {
                    ForEach(NameLength.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 260)
                Picker("Date", selection: Bindable(model).dateStyle) {
                    Text("No date").tag(DateStyle.none)
                    Text("Date at start").tag(DateStyle.atStart)
                    Text("Date at end").tag(DateStyle.atEnd)
                }.frame(width: 170)
                Toggle("Include files that already have a good name", isOn: Bindable(model).includeGood)
                Spacer()
            }
            .labelsHidden()
        }
        .padding(12)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.phase == .done {
            doneView
        } else if model.items.isEmpty || (model.visibleItems.isEmpty && model.phase == .ready) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Nothing to tidy up").font(.title3.bold())
                Text("Every image and PDF in this folder already has a good name.").foregroundStyle(.secondary)
                dateHelper
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleItems) { TidyRow(model: model, item: $0) }
                    dateHelper.padding(.top, 14)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text(model.records.isEmpty && model.undoMessage != nil ? "Reverted" : "Renamed \(model.records.count) files").font(.title2.bold())
            if let m = model.undoMessage { Text(m).foregroundStyle(.secondary) }
            ForEach(model.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            HStack {
                if !model.records.isEmpty {
                    Button("Undo All") { model.undoAll() }.help("Revert all to their original names")
                }
                Button("Start a New Batch") { model.newBatch() }.buttonStyle(.borderedProminent)
            }
            if !model.records.isEmpty { Text("Revert all to their original names").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var dateHelper: some View {
        if !model.dateFixes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dates in earlier names").font(.headline)
                Text("These names still have a date. Update moves or removes it to match your date setting. Nothing changes until you click Update.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.dateFixes.prefix(8)) { fix in
                    HStack {
                        Text(fix.oldName).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2)
                        Text(fix.newName).lineLimit(1).truncationMode(.middle)
                    }.font(.callout)
                }
                if model.dateFixes.count > 8 { Text("and \(model.dateFixes.count - 8) more").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Update \(model.dateFixes.count) Names") { model.applyDateFixes() }
                    if let m = model.dateMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        } else if let m = model.dateMessage {
            Text(m).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            switch model.phase {
            case .naming(let d, let t):
                ProgressView(value: Double(d), total: Double(max(t, 1))).frame(width: 140)
                Text("Naming \(min(d + 1, t)) of \(t)").foregroundStyle(.secondary)
            case .renaming(let d, let t):
                ProgressView(value: Double(d), total: Double(max(t, 1))).frame(width: 140)
                Text("Renaming \(d) of \(t)").foregroundStyle(.secondary)
            default:
                Text("Nothing is renamed until you click Rename.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase != .done {
                Button("Select All") { model.selectAll(true) }
                Button("Select None") { model.selectAll(false) }
                Button("Rename \(model.selectedCount) Files") { model.renameSelected() }
                    .buttonStyle(.borderedProminent).disabled(model.selectedCount == 0 || { if case .renaming = model.phase { true } else { false } }())
            }
        }
        .padding(12)
    }
}

struct TidyRow: View {
    let model: TidyModel
    let item: TidyItem
    @FocusState private var focused: Bool

    private var dim: Bool { item.alreadyGood && !model.includeGood }
    private var editing: Bool { model.editingID == item.id }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.selected }, set: { model.setSelected(item.id, $0) }))
                .labelsHidden().disabled(item.status != .ready || dim)
                .accessibilityLabel("Rename \(item.url.lastPathComponent)")
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                proposed
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(dim ? 0.45 : 1)
        .onAppear { model.thumbs.request(id: item.id, url: item.url, pdf: item.kind == .pdf) }
        Divider()
    }

    @ViewBuilder private var proposed: some View {
        switch item.status {
        case .pending: Text(dim ? "Already has a good name" : "Waiting…").font(.callout).foregroundStyle(.tertiary)
        case .naming: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Naming…").foregroundStyle(.secondary) }.font(.callout)
        case .kept(let why): Text(why).font(.callout).foregroundStyle(.secondary)
        case .failed(let why): Text("Couldn't name it: \(why)").font(.callout).foregroundStyle(.orange)
        case .ready:
            if editing {
                TextField("Name", text: Bindable(model).editText).textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { model.commitEdit(item) }.onExitCommand { model.cancelEdit() }.onAppear { focused = true }
            } else {
                Text(model.preview[item.id] ?? "…").font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    .contentShape(Rectangle()).onTapGesture { model.beginEdit(item) }.help("Click to edit the name")
            }
        }
    }

    @ViewBuilder private var thumb: some View {
        if let img = model.thumbs.images[item.id] {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 40, height: 40)
                .overlay(Image(systemName: item.kind == .pdf ? "doc.text" : "photo").foregroundStyle(.secondary))
        }
    }
}
