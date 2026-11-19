import SwiftUI
import RelabelCore

struct WelcomeView: View {
    let model: AppModel
    var finish: () -> Void
    private let nav = WelcomeSteps()
    private var step: Int { nav.step }

    var body: some View {
        VStack(spacing: 18) {
            Group {
                switch step {
                case 0: intro
                case 1: screenshots
                case 2: pdfs
                case 3: demo
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(0..<5) { Circle().fill($0 == step ? Color.accentColor : .secondary.opacity(0.3)).frame(width: 7, height: 7) }
            }
            .accessibilityHidden(true)
        }
        .padding(28)
        .frame(width: 520, height: 440)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.viewfinder").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Welcome to Relabel").font(.largeTitle.bold())
            Text("Relabel gives your screenshots and PDFs readable names, so you can find them later.")
                .multilineTextAlignment(.center)
            Label("All 100% privately on your Mac", systemImage: "lock.fill").foregroundStyle(.secondary)
            Text("No network, no accounts. It works with Wi-Fi off.").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") { nav.step = 1 }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var screenshots: some View {
        let suggested = SuggestedFolders.screenshotLocation()
        return VStack(spacing: 14) {
            Text("Where do your screenshots get saved?").font(.title2.bold())
            if let s = model.screenshotsFolder {
                chosen(s)
            } else {
                suggestionCard(path: suggested.path)
                Button("Use this folder") { model.setFolder(suggested, kind: .screenshots) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Choose Folder…") { model.chooseFolder(kind: .screenshots) }
            }
            Button("Screenshot options (⇧⌘5)") { model.openScreenshotOptions() }.buttonStyle(.link)
            errorText
            Spacer()
            navigation(next: model.screenshotsFolder == nil ? "Skip" : "Continue")
        }
    }

    private var pdfs: some View {
        let suggested = SuggestedFolders.downloads()
        return VStack(spacing: 14) {
            Text("Which folder holds your PDFs?").font(.title2.bold())
            if let p = model.pdfFolders.first {
                chosen(p)
            } else {
                suggestionCard(path: suggested.path)
                Button("Use this folder") { model.setFolder(suggested, kind: .pdf) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Choose Folder…") { model.chooseFolder(kind: .pdf) }
            }
            Text("You can add more PDF folders in Settings.").font(.caption).foregroundStyle(.secondary)
            errorText
            Spacer()
            navigation(next: model.pdfFolders.isEmpty ? "Skip" : "Continue")
        }
    }

    private var demo: some View {
        VStack(spacing: 14) {
            Text("Take a screenshot and watch it get a name").font(.title2.bold()).multilineTextAlignment(.center)
            if model.screenshotsFolder?.isReachable != true {
                Text("You skipped the screenshots folder, so there's nothing to watch yet. You can set it in Settings.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            } else if let r = model.lastRename, r.id != nav.baseline {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Renamed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(r.oldName).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(r.newName).font(.headline).lineLimit(2)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            } else {
                Text("Press ⇧⌘3 or ⇧⌘4. A few seconds after the preview goes away, the file gets a name.")
                    .multilineTextAlignment(.center)
                if model.status == .namingOne || model.status == .namingBatch {
                    ProgressView("Naming…")
                } else {
                    Label("Watching for a new screenshot", systemImage: "eye").foregroundStyle(.secondary)
                }
            }
            Spacer()
            navigation(next: "Continue")
        }
        .onAppear { nav.baseline = model.lastRename?.id }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: model.hasAnyFolder ? "checkmark.circle.fill" : "moon.zzz.fill")
                .font(.system(size: 48)).foregroundStyle(model.hasAnyFolder ? .green : .secondary)
            Text(model.hasAnyFolder ? "You're all set" : "Nothing to watch yet").font(.title.bold())
            Text(model.hasAnyFolder
                 ? "Relabel lives in your menu bar and will name new files in the folders you chose."
                 : "Relabel does nothing until you choose a folder. Open Settings from the menu bar icon any time.")
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { finish() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func suggestionCard(path: String) -> some View {
        HStack {
            Image(systemName: "folder.fill").foregroundStyle(.tint)
            Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func chosen(_ f: ResolvedFolder) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: f.isReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(f.isReachable ? .green : .orange)
                Text(f.displayPath).lineLimit(1).truncationMode(.middle)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Button("Choose a different folder…") { model.chooseFolder(kind: f.entry.kind, replacing: f.id) }
        }
    }

    @ViewBuilder private var errorText: some View {
        if let e = model.folderError { Text(e).font(.caption).foregroundStyle(.red) }
    }

    private func navigation(next: String) -> some View {
        HStack {
            Button("Back") { nav.step -= 1 }
            Spacer()
            Button(next) { nav.step += 1 }.keyboardShortcut(.defaultAction)
        }
    }
}

@MainActor @Observable
final class WelcomeSteps { var step = 0; var baseline: UUID? }
