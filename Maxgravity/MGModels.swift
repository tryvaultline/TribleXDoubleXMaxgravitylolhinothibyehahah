import Foundation

enum Route: Hashable {
    case chat(chatID: String)
    case taskDetail(chatID: String, segment: MGTaskDetailSegment)
    case codeViewer(fileRef: String)
    case diffViewer(fileRef: String)
}

enum MGSheetDestination: Hashable, Identifiable {
    case connectionInfo
    case modelPicker
    case slashCommands
    case fileMentions
    case taskContext
    case remoteFolderPicker
    case approvalSteering(requestID: String)
    case scheduleTask
    case pairingCode

    var id: String {
        switch self {
        case .connectionInfo: "connectionInfo"
        case .modelPicker: "modelPicker"
        case .slashCommands: "slashCommands"
        case .fileMentions: "fileMentions"
        case .taskContext: "taskContext"
        case .remoteFolderPicker: "remoteFolderPicker"
        case .approvalSteering(let requestID): "approvalSteering-\(requestID)"
        case .scheduleTask: "scheduleTask"
        case .pairingCode: "pairingCode"
        }
    }
}

enum MGFullScreenDestination: Hashable, Identifiable {
    case newTask(spaceID: String)
    case plusMenu

    var id: String {
        switch self {
        case .newTask(let spaceID): "newTask-\(spaceID)"
        case .plusMenu: "plusMenu"
        }
    }
}

enum MGPanelDestination: String, Hashable, Identifiable {
    case activity
    case settings

    var id: String { rawValue }
}

enum MGPermissionMode: String, CaseIterable, Identifiable, Codable {
    case sandbox
    case askWhenNeeded
    case sensitiveAutoReview
    case fullAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sandbox: "Sandbox"
        case .askWhenNeeded: "Ask when needed"
        case .sensitiveAutoReview: "Sensitive auto-review"
        case .fullAccess: "Full access"
        }
    }

    var summary: String {
        switch self {
        case .sandbox: "Bridge-limited safe operations only"
        case .askWhenNeeded: "Prompt before elevated actions"
        case .sensitiveAutoReview: "Auto-review risky actions before asking"
        case .fullAccess: "Desktop-only unrestricted mode"
        }
    }
}

enum MGConnectionQuality: String, CaseIterable, Identifiable {
    case excellent
    case good
    case fair
    case weak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .weak: "Weak"
        }
    }
}

enum MGTaskDetailSegment: String, CaseIterable, Identifiable, Hashable {
    case files = "Files"
    case changes = "Changes"
    case commands = "Commands"

    var id: String { rawValue }
}

enum MGActivityTone: Hashable {
    case neutral
    case good
    case warning
    case critical
}

enum MGArtifactKind: String, Hashable {
    case file
    case diff
    case command
    case screenshot
    case approval
    case completion
}

enum MGMessageRole: Hashable {
    case user
    case assistant
}

enum MGCapabilityState: String, CaseIterable, Hashable {
    case live
    case partial
    case mock
    case unsupported

    var title: String {
        rawValue.capitalized
    }

    var tone: MGActivityTone {
        switch self {
        case .live: .good
        case .partial: .warning
        case .mock: .neutral
        case .unsupported: .critical
        }
    }
}

struct MGBridgeCapability: Identifiable, Hashable {
    let id: String
    let title: String
    let state: MGCapabilityState
    let detail: String
}

struct MGPairingQRCodePayload: Hashable, Codable {
    let address: String
    let token: String
    let desktopFingerprint: String
    let expiresAt: Date
}

struct MGTrustedDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let addedAt: Date
    let fingerprint: String
}

struct MGComputerStatus: Identifiable, Hashable {
    let id: String
    var computerName: String
    var isOnline: Bool
    var quality: MGConnectionQuality
    var lastSync: Date
    var encryption: String
    var supportedPermissionModes: [MGPermissionMode]
    var connectionAddress: String
    var pairing: MGCapabilityState
    var liveBridge: MGCapabilityState
}

struct MGModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let isRecommended: Bool
    let availability: MGCapabilityState
}

struct MGTaskContext: Hashable {
    var workingFolder: String
    var permissionMode: MGPermissionMode
    var planMode: Bool
    var selectedModel: MGModelOption
    var mentionedFiles: [String]
}

struct MGTaskDraft: Hashable {
    var title: String
    var prompt: String
    var spaceID: String
    var context: MGTaskContext
}

struct MGDiffStat: Hashable {
    let fileName: String
    let added: Int
    let removed: Int
    let modified: Int
}

struct MGArtifactSummary: Identifiable, Hashable {
    let id: String
    let kind: MGArtifactKind
    let title: String
    let detail: String
}

struct MGCommandRun: Identifiable, Hashable {
    let id: String
    let command: String
    let result: String
    let duration: String
    let output: String
}

struct MGActivityEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let duration: String
    let tone: MGActivityTone
    let isComplete: Bool
}

struct MGApprovalRequest: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let scope: String
    let affectedItems: [String]
}

struct MGCompletionSummary: Hashable {
    let summary: String
    let filesChanged: Int
    let linesAdded: Int
    let linesRemoved: Int
    let checksRun: [String]
    let warnings: [String]
    let fullReply: String
}

struct MGThreadMessage: Identifiable, Hashable {
    let id: String
    let role: MGMessageRole
    let body: String
    let timestamp: Date
    let delivered: Bool
    let attachments: [MGArtifactSummary]
}

struct MGTaskThread: Hashable {
    let id: String
    var title: String
    var stateText: String
    var stateTone: MGActivityTone
    var messages: [MGThreadMessage]
    var timeline: [MGActivityEvent]
    var files: [String]
    var diffs: [MGDiffStat]
    var commands: [MGCommandRun]
    var approval: MGApprovalRequest?
    var completion: MGCompletionSummary?
}

struct MGChatSummary: Identifiable, Hashable {
    let id: String
    var title: String
    var lastActivity: Date
    var isRunning: Bool
    var isPinned: Bool
    var thread: MGTaskThread
}

struct MGSpaceSummary: Identifiable, Hashable {
    let id: String
    var name: String
    var chats: [MGChatSummary]
    var isPinned: Bool
    var statusText: String?
}

struct MGScheduledTask: Identifiable, Hashable {
    let id: String
    var title: String
    var spaceName: String
    var nextRun: Date
    var frequency: String
    var isEnabled: Bool
    var permissionMode: MGPermissionMode
    var model: String
}

struct MGActivityBucket: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [MGActivityListItem]
}

struct MGActivityListItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let tone: MGActivityTone
    let route: Route?
}

struct MGRemoteFileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [MGRemoteFileNode]

    var optionalChildren: [MGRemoteFileNode]? {
        children.isEmpty ? nil : children
    }
}

struct MGNotificationPreferences: Hashable {
    var taskCompleted = true
    var approvalRequired = true
    var connectionLost = true
    var scheduledTaskReady = true
}
