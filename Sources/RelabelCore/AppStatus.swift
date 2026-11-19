import Foundation

/// What the app is doing right now. Drives the menu bar icon and the status line.
public enum AppStatus: Equatable, Sendable {
    case idle
    case namingOne
    case namingBatch
    case paused
    case waitingForAppleIntelligence
    case coolingDown
    case folderUnreachable
    case noFolder
    case automaticNamingOff

    public var title: String {
        switch self {
        case .idle: "Watching Screenshots"
        case .namingOne: "Naming a screenshot"
        case .namingBatch: "Naming a batch"
        case .paused: "Paused"
        case .waitingForAppleIntelligence: "Waiting for Apple Intelligence"
        case .coolingDown: "Letting your Mac cool down"
        case .folderUnreachable: "Can't reach the screenshots folder"
        case .noFolder: "No screenshots folder"
        case .automaticNamingOff: "Automatic naming is off"
        }
    }

    public var accessibilityLabel: String { "Relabel status: \(title)" }

    public var iconState: IconState {
        switch self {
        case .namingOne, .namingBatch: .naming
        case .paused, .coolingDown, .waitingForAppleIntelligence, .automaticNamingOff: .paused
        case .folderUnreachable, .noFolder: .error
        case .idle: .idle
        }
    }
}

public enum IconState: Sendable { case idle, naming, paused, error }
