import SwiftUI
import RelabelCore

struct SettingsView: View {
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
                        Text("Shows or changes where macOS saves screenshots.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("PDF folders").font(.headline)
                    if model.pdfFolders.isEmpty {
                        Text("Not chosen yet").foregroundStyle(.secondary)
                    }
                    ForEach(model.pdfFolders) { FolderRow(model: model, folder: $0, removable: true) }
                    Button(model.pdfFolders.isEmpty ? "Choose a folder…" : "Add another PDF folder…") {
                        model.chooseFolder(kind: .pdf)
                    }
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
        .frame(width: 620, height: 420)
        .onAppear { model.refreshFolders() }
    }
}
