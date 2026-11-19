import SwiftUI
import AppKit
import RelabelCore

@MainActor
@Observable
final class PillModel {
    enum Content: Equatable {
        case renamed(HistoryRecord)
        case undone(HistoryRecord)
        case failed(RenameJob, String)
        case message(String)
    }
    var content: Content = .message("")
    var hovering = false
}

/// Small floating, non-activating panel near the top of the screen right after a rename.
@MainActor
final class PillController {
    private let panel: NSPanel
    private let model = PillModel()
    private var hideTask: Task<Void, Never>?
    var onUndo: (HistoryRecord) -> String? = { _ in nil }     // returns an error message, or nil on success
    var onRetry: (RenameJob) -> Void = { _ in }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 84),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = RenamePillView(model: model,
                                  undo: { [unowned self] r in undo(r) },
                                  retry: { [unowned self] j in hide(); onRetry(j) },
                                  dismiss: { [unowned self] in hide() })
        panel.contentView = NSHostingView(rootView: view)
    }

    func showRenamed(_ r: HistoryRecord) { present(.renamed(r)) }
    func showFailure(_ job: RenameJob, _ detail: String) { present(.failed(job, detail), lasting: 8) }

    private func undo(_ r: HistoryRecord) {
        if let error = onUndo(r) { present(.message(error), lasting: 6) } else { present(.undone(r), lasting: 3) }
    }

    private func present(_ c: PillModel.Content, lasting seconds: Double = 6) {
        model.content = c
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                         y: screen.visibleFrame.maxY - size.height - 10))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                if self?.model.hovering == false { remaining -= 0.2 }   // stays while hovered
            }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                             completionHandler: { [panel] in MainActor.assumeIsolated { panel.orderOut(nil) } })
    }
}

struct RenamePillView: View {
    let model: PillModel
    var undo: (HistoryRecord) -> Void
    var retry: (RenameJob) -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                switch model.content {
                case .renamed(let r):
                    Text("Renamed").font(.caption).foregroundStyle(.secondary)
                    Text(r.oldName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    Text(r.newName).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                case .undone(let r):
                    Text("Restored").font(.caption).foregroundStyle(.secondary)
                    Text(r.oldName).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                case .failed(_, let detail):
                    Text("Couldn't name it this time. Try again.").font(.callout.weight(.medium))
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                case .message(let m):
                    Text(m).font(.callout).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            switch model.content {
            case .renamed(let r): Button("Undo") { undo(r) }.keyboardShortcut(.cancelAction)
            case .failed(let job, _): Button("Retry") { retry(job) }
            default: EmptyView()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(width: 380, height: 84)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onHover { model.hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}
