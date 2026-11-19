import SwiftUI
import RelabelCore

/// One folder line: path, Show in Finder, and change/remove. Used by Settings.
struct FolderRow: View {
    let model: AppModel
    let folder: ResolvedFolder
    var removable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: folder.isReachable ? "folder" : "exclamationmark.triangle.fill")
                    .foregroundStyle(folder.isReachable ? Color.secondary : Color.orange)
                Text(folder.displayPath).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel("\(folder.entry.kind.displayName) folder \(folder.displayPath)")
                Spacer()
                Button("Show in Finder") { model.revealInFinder(folder) }.disabled(!folder.isReachable)
                Button("Choose a different folder…") { model.chooseFolder(kind: folder.entry.kind, replacing: folder.id) }
                if removable {
                    Button(role: .destructive) { model.removeFolder(folder.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Stop watching this folder")
                        .accessibilityLabel("Remove folder")
                }
            }
            if !folder.isReachable {
                Text(folder.entry.kind == .screenshots ? FolderMessages.screenshotsLost : FolderMessages.pdfLost(folder.displayPath))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
