import SwiftUI
import RelabelCore

struct SettingsView: View {
    let model: AppModel
    let preview = NamingPreview()

    var body: some View {
        TabView(selection: Bindable(model).settingsTab) {
            FoldersTab(model: model)
                .tabItem { Label("Folders", systemImage: "folder") }.tag(0)
            NamingTab(model: model, preview: preview)
                .tabItem { Label("Naming", systemImage: "textformat") }.tag(1)
            AppearanceTab(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }.tag(2)
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(3)
            LearningTab(model: model)
                .tabItem { Label("Learning", systemImage: "brain") }.tag(4)
        }
        .frame(width: 660, height: 600)
        .onAppear { model.refreshFolders(); model.refreshAI() }
    }
}

// MARK: Folders

struct FoldersTab: View {
    let model: AppModel
    var body: some View {
        Form {
            Section("Folders") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screenshots folder").font(.headline)
                    if let s = model.screenshotsFolder {
                        FolderRow(model: model, folder: s)
                    } else {
                        HStack {
                            Text("Not chosen yet").foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose a folder…") { model.chooseFolder(kind: .screenshots) }
                        }
                    }
                    HStack {
                        Button("Screenshot options (⇧⌘5)") { model.openScreenshotOptions() }
                        Text("Shows or changes where macOS saves screenshots.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("PDF folders").font(.headline)
                    if model.pdfFolders.isEmpty { Text("Not chosen yet").foregroundStyle(.secondary) }
                    ForEach(model.pdfFolders) { FolderRow(model: model, folder: $0, removable: true) }
                    Button(model.pdfFolders.isEmpty ? "Choose a folder…" : "Add another PDF folder…") { model.chooseFolder(kind: .pdf) }
                }
                if let e = model.folderError { Text(e).font(.caption).foregroundStyle(.red) }
                Text("Relabel only looks at folders you choose here.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Label("All 100% privately on your Mac. No network, no accounts. Works with Wi-Fi off.", systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show the welcome screen again") { model.openWelcome() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Naming

struct NamingTab: View {
    let model: AppModel
    let preview: NamingPreview

    private var previewKey: String {
        let p = model.prefs
        return "\(p.includeAppName)|\(p.dateStyle)|\(p.customPDFInstruction)|\(p.length)"
    }

    var body: some View {
        @Bindable var m = model
        Form {
            Section("Apple Intelligence") { aiStatus }

            Section("Name length") {
                Picker("Length", selection: $m.prefs.length) {
                    ForEach(NameLength.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(lengthBlurb).font(.caption).foregroundStyle(.secondary)
                samplePreview
                dropZone
            }

            Section("Details") {
                Toggle("Include the app's name (screenshots)", isOn: $m.prefs.includeAppName)
                Text("For example \"Quarterly budget in Excel\".").font(.caption).foregroundStyle(.secondary)
                Picker("Date", selection: $m.prefs.dateStyle) {
                    Text("No date").tag(DateStyle.none)
                    Text("At the start (good for sorting)").tag(DateStyle.atStart)
                    Text("At the end").tag(DateStyle.atEnd)
                }
                Text("Format is YYYY-MM-DD, from the file's creation date. Tidy Up can change the date style for one batch.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Look at the image too (slower)", isOn: $m.prefs.useImage).disabled(!NamingModel.supportsImages)
                Text(NamingModel.supportsImages
                     ? "Also shows the picture to Apple's on-device model, which helps with logos, charts and pages with little text."
                     : "This Mac's on-device model can't look at images, so only the recognized text is used.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("PDFs") {
                Text("Custom instruction (optional)").font(.headline)
                TextEditor(text: $m.prefs.customPDFInstruction)
                    .font(.body).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel("Custom instruction for PDF names")
                Text("For example: \"Always start with the reference number, then the organisation, then a short subject\" or \"Put the vendor first and the invoice number last\". It's used for new PDFs and in Tidy Up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: previewKey) {
            try? await Task.sleep(for: .milliseconds(400))      // let typing settle
            if !Task.isCancelled { await preview.refreshSample(model.prefs) }
        }
    }

    private var lengthBlurb: String {
        switch model.prefs.length {
        case .short: "Short: what it shows, in 2 to 6 words."
        case .standard: "Standard: what it is and the key subject, in 4 to 8 words."
        case .detailed: "Detailed: with the specifics, in up to 10 words."
        }
    }

    @ViewBuilder private var aiStatus: some View {
        switch model.aiAvailability {
        case .available:
            Label("Apple Intelligence is on. Names are written by Apple's on-device model.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case .appleIntelligenceOff:
            Label("Apple Intelligence is off. Using basic naming from the text on the file.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
            Button("Open Apple Intelligence & Siri settings") { model.openAppleIntelligenceSettings() }
        case .stillLoading:
            Label("Waiting for Apple Intelligence. Basic naming until it's ready.", systemImage: "hourglass").foregroundStyle(.orange).font(.callout)
        case .notEligible:
            Label("This Mac can't run Apple Intelligence. Using basic naming.", systemImage: "xmark.circle.fill").foregroundStyle(.secondary).font(.callout)
        }
        if model.aiAvailability != .available {
            Text("Without Apple Intelligence every length gives the same name.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var samplePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview: a spreadsheet screenshot taken in Excel").font(.caption).foregroundStyle(.secondary)
            if preview.sample.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Naming the sample…").foregroundStyle(.secondary) }.font(.callout)
            } else {
                ForEach(preview.sample, id: \.length) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.length.label).font(.caption.weight(.semibold)).frame(width: 64, alignment: .leading)
                            .foregroundStyle(r.length == model.prefs.length ? Color.accentColor : .secondary)
                        Text(r.name).font(.callout).lineLimit(1).truncationMode(.middle)
                        if preview.sampleBusy { ProgressView().controlSize(.mini) }
                    }
                }
                if let pdf = preview.samplePDF {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("PDF").font(.caption.weight(.semibold)).frame(width: 64, alignment: .leading).foregroundStyle(.secondary)
                        Text(pdf.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    }
                    Text("A sample invoice PDF named with your custom instruction.").font(.caption2).foregroundStyle(.tertiary)
                }
                if let n = preview.note { Text(n).font(.caption).foregroundStyle(.orange) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            if preview.dropBusy && preview.dropped.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Reading \(preview.droppedName ?? "file")…").foregroundStyle(.secondary) }
            } else if let err = preview.dropError {
                Text(err).foregroundStyle(.orange)
            } else if !preview.dropped.isEmpty {
                Text(preview.droppedName ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                ForEach(preview.dropped, id: \.length) { r in
                    HStack {
                        Text(r.length.label).font(.caption.weight(.semibold)).frame(width: 64, alignment: .leading).foregroundStyle(.secondary)
                        Text(r.name).lineLimit(1).truncationMode(.middle)
                    }.font(.callout)
                }
                Text("Nothing was renamed. Drop another file to try it.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Image(systemName: "square.and.arrow.down").font(.title3).foregroundStyle(.secondary)
                Text("Drop to see its name").foregroundStyle(.secondary)
                Text("Drop any image or PDF here. Nothing is renamed.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78).padding(8)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(preview.targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
        .background(preview.targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [.fileURL], isTargeted: Bindable(preview).targeted) { providers in
            DropLoader.urls(from: providers) { urls in
                guard let url = urls.first else { return }
                Task { await preview.preview(url: url, prefs: model.prefs) }
            }
            return true
        }
        .accessibilityLabel("Drop an image or PDF here to see what it would be called")
    }
}

// MARK: Appearance

struct AppearanceTab: View {
    let model: AppModel
    var body: some View {
        @Bindable var m = model
        Form {
            Section("Menu bar icon") {
                Picker("Style", selection: $m.iconStyle) {
                    ForEach(IconStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                ForEach(IconStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(style.label).font(.subheadline.weight(.semibold))
                        HStack(spacing: 18) {
                            ForEach([(IconState.idle, "Idle"), (.naming, "Naming"), (.paused, "Paused"), (.error, "Problem")], id: \.1) { state, label in
                                VStack(spacing: 2) {
                                    Image(nsImage: MenuBarFace.image(style: style, state: state, frame: 1)).renderingMode(.template)
                                        .scaleEffect(1.4).frame(width: 30, height: 26)
                                    Text(label).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(style.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .opacity(style == model.iconStyle ? 1 : 0.6)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: General

struct GeneralTab: View {
    let model: AppModel
    var body: some View {
        @Bindable var m = model
        Form {
            Section("General") {
                Toggle("Name new files automatically", isOn: $m.prefs.automaticNaming)
                Text("Off: Relabel only names files you drop on it or tidy up yourself.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let msg = model.loginMessage { Text(msg).font(.caption).foregroundStyle(.orange) }
                Toggle("Pause while in Low Power Mode", isOn: $m.prefs.pauseInLowPowerMode)
                Text("New files wait and are named once Low Power Mode is off. Relabel also waits when your Mac gets hot.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Notifications", isOn: $m.prefs.notifications)
                Toggle("Copy screenshots to the clipboard", isOn: $m.prefs.copyScreenshotsToClipboard)
                Text("After a screenshot is named it's also placed on the clipboard, ready to paste.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Label("All 100% privately on your Mac. No network calls, no accounts, no analytics. Works with Wi-Fi off.", systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Learning

struct LearningTab: View {
    let model: AppModel
    var body: some View {
        @Bindable var m = model
        Form {
            Section("Learn from my renames") {
                Toggle("Learn from my renames", isOn: $m.prefs.learnFromRenames)
                Text("When you change a name Relabel gave a file, in the menu or in Finder, Relabel remembers it and uses your style for similar files. Turning this off keeps what it learned but stops using it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What it learned") {
                if model.learned.isEmpty {
                    Text("Nothing yet. Rename a file Relabel named and it will show up here.").foregroundStyle(.secondary)
                } else {
                    Text("Relabel has learned from \(model.learned.count) of your renames.")
                    if let style = model.styleDescription {
                        Label(style, systemImage: "sparkles").font(.callout)
                    } else {
                        Text("After \(StyleProfile.minimumCorrections) renames it can describe your style.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("See What It Learned") { model.showLearned = true }.disabled(model.learned.isEmpty)
                    Button("Forget Everything", role: .destructive) { model.confirmForget = true }.disabled(model.learned.isEmpty)
                }
            }
            Section {
                Label("This data never leaves your Mac. It's a small file in ~/Library/Application Support/Relabel.", systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $m.showLearned) { LearnedList(model: model) }
        .confirmationDialog("Forget everything Relabel learned?", isPresented: $m.confirmForget, titleVisibility: .visible) {
            Button("Forget Everything", role: .destructive) { model.forgetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all \(model.learned.count) remembered renames. Your files are not touched.")
        }
    }
}

struct LearnedList: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What Relabel learned").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
            Divider()
            if model.learned.isEmpty {
                Text("Nothing learned yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.learned.reversed()) { c in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: c.kind == .pdf ? "doc.text" : "photo").foregroundStyle(.secondary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.relabelName).font(.caption).foregroundStyle(.secondary).strikethrough().lineLimit(1)
                                    Text(c.userName).font(.callout.weight(.medium)).lineLimit(2)
                                    Text(c.time.formatted(date: .abbreviated, time: .omitted) + (c.appName.map { " · \($0)" } ?? ""))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button { model.forget(c.id) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless).help("Forget this one")
                                    .accessibilityLabel("Forget \(c.userName)")
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 440)
    }
}
