import SwiftUI
import RelabelCore

@MainActor
@Observable
final class AppModel {
    var status: AppStatus = .noFolder
    var isDraggingFile = false
    var namedCount = 0
    var tick = 0   // animation clock for the icon
}
