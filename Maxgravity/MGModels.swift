import Foundation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case spaces
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaces: "Spaces"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .spaces: "square.grid.2x2"
        case .activity: "bolt.horizontal"
        case .settings: "gearshape"
        }
    }
}

enum Route: Hashable {
    case newTask(spaceID: String)
    case chat(chatID: String)
    case taskDetail(chatID: String, segment: MGTaskDetailSegment)
    case codeViewer(fileRef: String)
    case diffViewer(fileRef: String)
}

enum SheetDestination: Hashable, Identifiable {
    case connectionInfo
    case modelPicker
    case plusMenu
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
        case .plusMenu: "plusMenu"
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

struct MGComputerStatus: Identifiable, Hashable {
    let id: String
    var computerName: String
    var isOnline: Bool
    var quality: MGConnectionQuality
    var lastSync: Date
    var encryption: String
    var supportedPermissionModes: [MGPermissionMode]
}

struct MGModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let isRecommended: Bool
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
}
