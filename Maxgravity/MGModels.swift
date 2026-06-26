import Foundation

enum Route: Hashable, Codable {
    case chat(chatID: String)
    case taskDetail(chatID: String, segment: MGTaskDetailSegment)
    case codeViewer(fileRef: String)
    case diffViewer(fileRef: String)

    enum CodingKeys: String, CodingKey {
        case type, chatID, segment, fileRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "chat":
            let chatID = try container.decode(String.self, forKey: .chatID)
            self = .chat(chatID: chatID)
        case "taskDetail":
            let chatID = try container.decode(String.self, forKey: .chatID)
            let segment = try container.decode(MGTaskDetailSegment.self, forKey: .segment)
            self = .taskDetail(chatID: chatID, segment: segment)
        case "codeViewer":
            let fileRef = try container.decode(String.self, forKey: .fileRef)
            self = .codeViewer(fileRef: fileRef)
        case "diffViewer":
            let fileRef = try container.decode(String.self, forKey: .fileRef)
            self = .diffViewer(fileRef: fileRef)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown route type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .chat(let chatID):
            try container.encode("chat", forKey: .type)
            try container.encode(chatID, forKey: .chatID)
        case .taskDetail(let chatID, let segment):
            try container.encode("taskDetail", forKey: .type)
            try container.encode(chatID, forKey: .chatID)
            try container.encode(segment, forKey: .segment)
        case .codeViewer(let fileRef):
            try container.encode("codeViewer", forKey: .type)
            try container.encode(fileRef, forKey: .fileRef)
        case .diffViewer(let fileRef):
            try container.encode("diffViewer", forKey: .type)
            try container.encode(fileRef, forKey: .fileRef)
        }
    }
}

enum MGAppSection: String, CaseIterable, Identifiable, Codable {
    case spaces
    case activity
    case workspace
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaces: "Chats"
        case .activity: "Activity"
        case .workspace: "Workspace"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .spaces: "bubble.left.and.bubble.right.fill"
        case .activity: "bolt.horizontal.fill"
        case .workspace: "folder.fill"
        case .settings: "person.crop.circle.fill"
        }
    }
}


enum MGSheetDestination: Hashable, Identifiable {
    case connectionInfo
    case modelPicker
    case slashCommands
    case fileMentions
    case photoLibrary
    case plugins
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
        case .photoLibrary: "photoLibrary"
        case .plugins: "plugins"
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

enum MGConnectionQuality: String, CaseIterable, Identifiable, Codable {
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

enum MGTaskDetailSegment: String, CaseIterable, Identifiable, Codable, Hashable {
    case files = "Files"
    case changes = "Changes"
    case commands = "Commands"

    var id: String { rawValue }
}

enum MGActivityTone: String, Codable, Hashable {
    case neutral
    case good
    case warning
    case critical
}

enum MGArtifactKind: String, Codable, Hashable {
    case file
    case diff
    case command
    case screenshot
    case approval
    case completion
}

enum MGMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

enum MGCapabilityState: String, CaseIterable, Codable, Hashable {
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

struct MGBridgeCapability: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let state: MGCapabilityState
    let detail: String
}

struct MGPairingQRCodePayload: Hashable, Codable {
    let sessionId: String
    let address: String
    let token: String?
    let protocolVersion: String?
    let httpsHost: String?
    let httpsPort: Int?
    let wssPort: Int?
    let bridgeFingerprint: String
    let expiresAt: Date
    let bridgeVersion: String
}

struct MGTrustedDevice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let addedAt: Date
    let fingerprint: String
}

struct MGComputerStatus: Identifiable, Codable, Hashable {
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

struct MGModelOption: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let providerID: String
    let providerName: String
    let modelID: String
    let modelName: String
    let runtimeID: String
    let runtimeName: String
    let speedLabel: String?
    let effortLabel: String?
    let capabilities: [String]
    let isRecommended: Bool
    let availability: MGCapabilityState

    var contractSummary: String {
        "\(providerName) / \(modelName) / \(runtimeName)"
    }
}

struct MGTaskContext: Codable, Hashable {
    var workingFolder: String
    var permissionMode: MGPermissionMode
    var planMode: Bool
    var selectedModel: MGModelOption
    var mentionedFiles: [String]
}

struct MGTaskDraft: Codable, Hashable {
    var title: String
    var prompt: String
    var spaceID: String
    var context: MGTaskContext
}

struct MGDiffStat: Codable, Hashable {
    let fileName: String
    let added: Int
    let removed: Int
    let modified: Int
}

struct MGArtifactSummary: Identifiable, Codable, Hashable {
    let id: String
    let kind: MGArtifactKind
    let title: String
    let detail: String
}

struct MGCommandRun: Identifiable, Codable, Hashable {
    let id: String
    let command: String
    let result: String
    let duration: String
    let output: String
}

struct MGActivityEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String
    let duration: String
    let tone: MGActivityTone
    let isComplete: Bool
}

struct MGApprovalRequest: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let scope: String
    let affectedItems: [String]
}

struct MGCompletionSummary: Codable, Hashable {
    let summary: String
    let filesChanged: Int
    let linesAdded: Int
    let linesRemoved: Int
    let checksRun: [String]
    let warnings: [String]
    let fullReply: String
}

struct MGThreadMessage: Identifiable, Codable, Hashable {
    let id: String
    let role: MGMessageRole
    let body: String
    let timestamp: Date
    let delivered: Bool
    let attachments: [MGArtifactSummary]
}

struct MGTaskThread: Codable, Hashable {
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

struct MGChatSummary: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var lastActivity: Date
    var isRunning: Bool
    var isPinned: Bool
    var thread: MGTaskThread
}

struct MGSpaceSummary: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var chats: [MGChatSummary]
    var isPinned: Bool
    var statusText: String?
}

struct MGScheduledTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var spaceName: String
    var nextRun: Date
    var frequency: String
    var isEnabled: Bool
    var permissionMode: MGPermissionMode
    var model: String
}

struct MGActivityBucket: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let items: [MGActivityListItem]
}

struct MGActivityListItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String
    let tone: MGActivityTone
    let route: Route?
}

struct MGRemoteFileNode: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [MGRemoteFileNode]

    var optionalChildren: [MGRemoteFileNode]? {
        children.isEmpty ? nil : children
    }
}

struct MGRemoteFileContent: Codable, Hashable {
    let path: String
    let content: String
}

struct MGPluginInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let kind: String?
    let detail: String?
    let command: String?
}

struct MGPickedPhoto: Identifiable, Hashable {
    let id: String
    let data: Data
}

struct MGNotificationPreferences: Codable, Hashable {
    var taskCompleted = true
    var approvalRequired = true
    var connectionLost = true
    var scheduledTaskReady = true
}
