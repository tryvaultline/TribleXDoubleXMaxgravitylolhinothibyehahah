import ActivityKit
import Foundation
import Observation
import UserNotifications

protocol MGBridgeClient {
    func fetchConnectionStatus() async throws -> MGComputerStatus?
    func listSpaces() async throws -> [MGSpaceSummary]
    func listActivity() async throws -> [MGActivityBucket]
    func listSchedules() async throws -> [MGScheduledTask]
    func availableModels() async throws -> [MGModelOption]
    func approvedRoots() async throws -> [MGRemoteFileNode]
    func capabilityMatrix() async throws -> [MGBridgeCapability]
    func preparePairingSession() async throws -> MGPairingQRCodePayload
}

protocol MGSpacesRepository {
    func spaces() async throws -> [MGSpaceSummary]
}

protocol MGTasksRepository {
    func models() async throws -> [MGModelOption]
}

protocol MGActivityRepository {
    func activityBuckets() async throws -> [MGActivityBucket]
    func schedules() async throws -> [MGScheduledTask]
}

protocol MGWorkspaceRepository {
    func roots() async throws -> [MGRemoteFileNode]
}

protocol MGSettingsStore {
    var defaultModelID: String { get set }
    var defaultPermissionMode: MGPermissionMode { get set }
    var defaultPlanMode: Bool { get set }
    var defaultSpaceID: String? { get set }
}

struct MGInMemorySettingsStore: MGSettingsStore {
    var defaultModelID: String = "auto"
    var defaultPermissionMode: MGPermissionMode = .askWhenNeeded
    var defaultPlanMode: Bool = false
    var defaultSpaceID: String?
}

struct MGMockBridgeClient: MGBridgeClient, MGSpacesRepository, MGTasksRepository, MGActivityRepository, MGWorkspaceRepository {
    func fetchConnectionStatus() async throws -> MGComputerStatus? { nil }
    func listSpaces() async throws -> [MGSpaceSummary] { MGFixtures.spaces }
    func listActivity() async throws -> [MGActivityBucket] { MGFixtures.activityBuckets }
    func listSchedules() async throws -> [MGScheduledTask] { MGFixtures.schedules }
    func availableModels() async throws -> [MGModelOption] { MGFixtures.models }
    func approvedRoots() async throws -> [MGRemoteFileNode] { MGFixtures.remoteRoots }
    func capabilityMatrix() async throws -> [MGBridgeCapability] { MGFixtures.capabilities }
    func preparePairingSession() async throws -> MGPairingQRCodePayload { MGFixtures.pairingPayload }
    func spaces() async throws -> [MGSpaceSummary] { MGFixtures.spaces }
    func models() async throws -> [MGModelOption] { MGFixtures.models }
    func activityBuckets() async throws -> [MGActivityBucket] { MGFixtures.activityBuckets }
    func schedules() async throws -> [MGScheduledTask] { MGFixtures.schedules }
    func roots() async throws -> [MGRemoteFileNode] { MGFixtures.remoteRoots }
}

@available(iOS 16.1, *)
struct MGTaskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: String
        var status: String
        var approvalRequired: Bool
    }

    var taskTitle: String
    var computerName: String
}

@MainActor
final class MGTaskLiveActivityController {
    private var activity: Activity<MGTaskActivityAttributes>?
    private(set) var diagnostics = "Idle"

    func startIfPossible(taskTitle: String, computerName: String, stage: String) {
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                diagnostics = "Live Activities disabled on device"
                return
            }

            do {
                activity = try Activity.request(
                    attributes: MGTaskActivityAttributes(taskTitle: taskTitle, computerName: computerName),
                    contentState: .init(stage: stage, status: "Running", approvalRequired: false),
                    pushType: nil
                )
                diagnostics = "Started in foreground only; background bridge push updates still require APNs setup."
            } catch {
                diagnostics = "Live Activity request failed: \(error.localizedDescription)"
            }
        } else {
            diagnostics = "ActivityKit requires iOS 16.1+"
        }
    }

    func update(stage: String, status: String, approvalRequired: Bool) {
        guard #available(iOS 16.1, *), let activity else { return }
        Task {
            await activity.update(using: .init(stage: stage, status: status, approvalRequired: approvalRequired))
        }
    }

    func end() {
        guard #available(iOS 16.1, *), let activity else { return }
        Task { await activity.end(dismissalPolicy: .default) }
    }
}

@MainActor
@Observable
final class MGAppModel {
    var path: [Route] = []
    var presentedSheet: MGSheetDestination?
    var presentedFullScreen: MGFullScreenDestination?
    var presentedPanel: MGPanelDestination?

    var connection: MGComputerStatus?
    var trustedDevices: [MGTrustedDevice] = MGFixtures.trustedDevices
    var spaces: [MGSpaceSummary] = MGFixtures.spaces
    var activityBuckets: [MGActivityBucket] = MGFixtures.activityBuckets
    var schedules: [MGScheduledTask] = MGFixtures.schedules
    var models: [MGModelOption] = MGFixtures.models
    var remoteRoots: [MGRemoteFileNode] = MGFixtures.remoteRoots
    var capabilities: [MGBridgeCapability] = MGFixtures.capabilities
    var pairingPayload: MGPairingQRCodePayload = MGFixtures.pairingPayload
    var notificationPreferences = MGNotificationPreferences()
    var notificationsAuthorized = false
    var liveActivityDiagnostics = "Not started"

    var expandedSpaceIDs: Set<String> = [MGFixtures.spaces.first?.id ?? ""]

    var draftPrompt = ""
    var draftMicrophoneEnabled = false
    var draftContext = MGTaskContext(
        workingFolder: "C:\\Users\\kuroi\\OneDrive\\Desktop\\Vaultline-V\\Best Version Of Vaultline Web UI",
        permissionMode: .askWhenNeeded,
        planMode: false,
        selectedModel: MGFixtures.models[0],
        mentionedFiles: ["src/components/BottomBar.tsx", "README.md"]
    )

    private let bridge: MGBridgeClient
    private var settingsStore: MGSettingsStore
    private let liveActivityController = MGTaskLiveActivityController()

    init(
        bridge: MGBridgeClient = MGMockBridgeClient(),
        settingsStore: MGSettingsStore = MGInMemorySettingsStore()
    ) {
        self.bridge = bridge
        self.settingsStore = settingsStore
    }

    var hasConnectedComputer: Bool { connection != nil }

    func bootstrap() async {
        do {
            connection = try await bridge.fetchConnectionStatus()
            spaces = try await bridge.listSpaces()
            activityBuckets = try await bridge.listActivity()
            schedules = try await bridge.listSchedules()
            models = try await bridge.availableModels()
            remoteRoots = try await bridge.approvedRoots()
            capabilities = try await bridge.capabilityMatrix()
            pairingPayload = try await bridge.preparePairingSession()
        } catch {
            liveActivityDiagnostics = "Bridge bootstrap failed: \(error.localizedDescription)"
        }
    }

    func connectMockComputer() {
        connection = MGFixtures.connectedComputer
    }

    func disconnectCurrentComputer() {
        connection = nil
        path = []
        presentedSheet = nil
        presentedFullScreen = nil
        presentedPanel = nil
    }

    func toggleSpace(_ spaceID: String) {
        if expandedSpaceIDs.contains(spaceID) {
            expandedSpaceIDs.remove(spaceID)
        } else {
            expandedSpaceIDs.insert(spaceID)
        }
    }

    func collapseAllSpaces() {
        expandedSpaceIDs.removeAll()
    }

    func openChat(_ chatID: String) {
        path.append(.chat(chatID: chatID))
    }

    func openNewTask(spaceID: String) {
        presentedFullScreen = .newTask(spaceID: spaceID)
    }

    func presentPanel(_ panel: MGPanelDestination) {
        presentedPanel = panel
    }

    func dismissPanel() {
        presentedPanel = nil
    }

    func chat(with id: String) -> MGChatSummary? {
        for space in spaces {
            if let chat = space.chats.first(where: { $0.id == id }) {
                return chat
            }
        }
        return nil
    }

    func space(with id: String) -> MGSpaceSummary? {
        spaces.first(where: { $0.id == id })
    }

    func createTask(in spaceID: String) -> MGChatSummary? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return nil
        }

        let title = draftPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "New task"

        let now = Date()
        let thread = MGTaskThread(
            id: UUID().uuidString,
            title: title,
            stateText: "Planning changes",
            stateTone: .neutral,
            messages: [
                MGThreadMessage(
                    id: UUID().uuidString,
                    role: .user,
                    body: draftPrompt.isEmpty ? "Describe what you want Maxgravity to build, change, review, or investigate…" : draftPrompt,
                    timestamp: now,
                    delivered: true,
                    attachments: draftContext.mentionedFiles.map {
                        MGArtifactSummary(id: UUID().uuidString, kind: .file, title: $0, detail: "Mentioned file")
                    }
                ),
                MGThreadMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    body: "Planning the task using the selected workspace, permission mode, and model. Live bridge execution remains partial until the desktop QR-paired transport is active.",
                    timestamp: now.addingTimeInterval(8),
                    delivered: true,
                    attachments: [
                        MGArtifactSummary(id: UUID().uuidString, kind: .command, title: draftContext.selectedModel.title, detail: "Selected model"),
                        MGArtifactSummary(id: UUID().uuidString, kind: .file, title: draftContext.workingFolder, detail: "Working folder")
                    ]
                )
            ],
            timeline: [
                MGActivityEvent(
                    id: UUID().uuidString,
                    title: "Planning changes",
                    detail: "Interpreting the request and preparing the task context.",
                    duration: "0.3s",
                    tone: .neutral,
                    isComplete: true
                ),
                MGActivityEvent(
                    id: UUID().uuidString,
                    title: "Awaiting desktop bridge",
                    detail: "Bridge transport is prepared but still using partial local scaffolding.",
                    duration: "Live",
                    tone: .warning,
                    isComplete: false
                )
            ],
            files: draftContext.mentionedFiles,
            diffs: [],
            commands: [],
            approval: nil,
            completion: nil
        )

        let chat = MGChatSummary(
            id: thread.id,
            title: title,
            lastActivity: now,
            isRunning: true,
            isPinned: false,
            thread: thread
        )

        spaces[spaceIndex].chats.insert(chat, at: 0)
        expandedSpaceIDs.insert(spaceID)
        draftPrompt = ""
        presentedFullScreen = nil
        openChat(chat.id)
        if let connection {
            liveActivityController.startIfPossible(taskTitle: title, computerName: connection.computerName, stage: thread.stateText)
            liveActivityDiagnostics = liveActivityController.diagnostics
        }
        return chat
    }

    func updateDraftModel(_ model: MGModelOption) {
        draftContext.selectedModel = model
        settingsStore.defaultModelID = model.id
    }

    func updateDraftPermission(_ mode: MGPermissionMode) {
        draftContext.permissionMode = mode
        settingsStore.defaultPermissionMode = mode
    }

    func addMentionedFile(_ path: String) {
        guard !draftContext.mentionedFiles.contains(path) else { return }
        draftContext.mentionedFiles.append(path)
    }

    func removeMentionedFile(_ path: String) {
        draftContext.mentionedFiles.removeAll { $0 == path }
    }

    func steerApproval(requestID: String, guidance: String) {
        guard !guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        for spaceIndex in spaces.indices {
            for chatIndex in spaces[spaceIndex].chats.indices where spaces[spaceIndex].chats[chatIndex].thread.approval?.id == requestID {
                let message = MGThreadMessage(
                    id: UUID().uuidString,
                    role: .user,
                    body: guidance,
                    timestamp: .now,
                    delivered: true,
                    attachments: []
                )
                spaces[spaceIndex].chats[chatIndex].thread.messages.append(message)
                spaces[spaceIndex].chats[chatIndex].lastActivity = .now
                return
            }
        }
    }

    func requestNotificationAuthorization() async {
        do {
            notificationsAuthorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            notificationsAuthorized = false
        }
    }
}

enum MGFixtures {
    static let models: [MGModelOption] = [
        MGModelOption(id: "auto", title: "Auto", subtitle: "Recommended for most tasks", isRecommended: true, availability: .live),
        MGModelOption(id: "gpt-4o", title: "GPT-4o", subtitle: "Fast multimodal execution", isRecommended: false, availability: .partial),
        MGModelOption(id: "gpt-4.1", title: "GPT-4.1", subtitle: "Balanced reasoning", isRecommended: false, availability: .partial),
        MGModelOption(id: "gpt-5-codex", title: "GPT-5 Codex", subtitle: "Code-first reasoning", isRecommended: false, availability: .mock),
        MGModelOption(id: "gpt-5-codex-high", title: "GPT-5 Codex High", subtitle: "Highest reasoning budget", isRecommended: false, availability: .mock)
    ]

    static let pairingPayload = MGPairingQRCodePayload(
        address: "wss://192.168.1.18:59443",
        token: "MG-7K4Q-98N1",
        desktopFingerprint: "3B:A7:E1:44:3F:92",
        expiresAt: .now.addingTimeInterval(300)
    )

    static let connectedComputer = MGComputerStatus(
        id: "desktop-1",
        computerName: "MAX-WS-01",
        isOnline: true,
        quality: .excellent,
        lastSync: .now.addingTimeInterval(-18),
        encryption: "Pinned local transport",
        supportedPermissionModes: [.sandbox, .askWhenNeeded, .sensitiveAutoReview],
        connectionAddress: pairingPayload.address,
        pairing: .partial,
        liveBridge: .partial
    )

    static let capabilities: [MGBridgeCapability] = [
        MGBridgeCapability(id: "cap-health", title: "Connection health", state: .live, detail: "Computer identity and online quality are sourced from the bridge shell."),
        MGBridgeCapability(id: "cap-spaces", title: "Spaces and chats", state: .mock, detail: "Still fixture-backed in mobile while the bridge contract settles."),
        MGBridgeCapability(id: "cap-launch", title: "Task launch", state: .partial, detail: "Mobile draft flow exists; desktop execution handoff is not end-to-end yet."),
        MGBridgeCapability(id: "cap-events", title: "Live task events", state: .partial, detail: "Safe activity states are modeled, but live streaming is not connected."),
        MGBridgeCapability(id: "cap-artifacts", title: "Files, diffs, commands", state: .mock, detail: "Artifact rendering is implemented with realistic payload shapes."),
        MGBridgeCapability(id: "cap-workspace", title: "Workspace roots", state: .partial, detail: "Remote approved-root browsing is scaffolded; bridge enforcement is pending."),
        MGBridgeCapability(id: "cap-pairing", title: "QR pairing", state: .partial, detail: "Signed payload model exists; camera scan and desktop trust confirmation are pending.")
    ]

    static let trustedDevices: [MGTrustedDevice] = [
        MGTrustedDevice(id: "ios-1", name: "Kuroi iPhone", addedAt: .now.addingTimeInterval(-86_400), fingerprint: "A1:6F:9B:42")
    ]

    static let thread = MGTaskThread(
        id: "thread-maxgravity-bottom-bar",
        title: "Implement bottom bar",
        stateText: "Waiting for approval",
        stateTone: .warning,
        messages: [
            MGThreadMessage(
                id: "m1",
                role: .user,
                body: "Refine the bottom navigation into a native glass treatment and make the active state clearer.",
                timestamp: .now.addingTimeInterval(-3500),
                delivered: true,
                attachments: [
                    MGArtifactSummary(id: "a1", kind: .file, title: "src/components/BottomBar.tsx", detail: "Mentioned file")
                ]
            ),
            MGThreadMessage(
                id: "m2",
                role: .assistant,
                body: "Reviewed the current bottom bar, updated spacing and active affordance, then prepared a small validation pass before applying the final diff.",
                timestamp: .now.addingTimeInterval(-3200),
                delivered: true,
                attachments: [
                    MGArtifactSummary(id: "a2", kind: .diff, title: "BottomBar.tsx  +48  -23", detail: "Diff summary"),
                    MGArtifactSummary(id: "a3", kind: .command, title: "npm run test", detail: "Passed · 2.3s")
                ]
            )
        ],
        timeline: [
            MGActivityEvent(id: "e1", title: "Planning changes", detail: "Mapped the bottom bar update and preserved existing layout rules.", duration: "0.4s", tone: .neutral, isComplete: true),
            MGActivityEvent(id: "e2", title: "Reading `src/components/BottomBar.tsx`", detail: "Reviewed the current active state and spacing.", duration: "0.7s", tone: .neutral, isComplete: true),
            MGActivityEvent(id: "e3", title: "Updating styles", detail: "Prepared clearer spacing, icon rhythm, and state emphasis.", duration: "1.2s", tone: .good, isComplete: true),
            MGActivityEvent(id: "e4", title: "Running checks", detail: "Verified the changed surface using targeted tests.", duration: "2.3s", tone: .good, isComplete: true),
            MGActivityEvent(id: "e5", title: "Awaiting approval", detail: "Dependency installation requires explicit approval.", duration: "Live", tone: .warning, isComplete: false)
        ],
        files: [
            "src/components/BottomBar.tsx",
            "src/styles/navigation.css",
            "README.md"
        ],
        diffs: [
            MGDiffStat(fileName: "BottomBar.tsx", added: 48, removed: 23, modified: 5),
            MGDiffStat(fileName: "navigation.css", added: 16, removed: 8, modified: 4)
        ],
        commands: [
            MGCommandRun(id: "c1", command: "npm run lint -- src/components/BottomBar.tsx", result: "Passed", duration: "0.8s", output: "Lint completed with no issues in the changed file."),
            MGCommandRun(id: "c2", command: "npm test", result: "Passed", duration: "2.3s", output: "2 suites passed. 12 tests passed. No snapshots updated.")
        ],
        approval: MGApprovalRequest(
            id: "approval-1",
            title: "Approve dependency installation",
            summary: "Install a native animation helper to match the requested transition polish.",
            scope: "One package installation in the selected workspace.",
            affectedItems: ["package.json", "package-lock.json", "npm install package-name"]
        ),
        completion: MGCompletionSummary(
            summary: "Updated the bottom navigation glass treatment and clarified the active state. Added a targeted validation pass and kept the interaction native-feeling.",
            filesChanged: 2,
            linesAdded: 48,
            linesRemoved: 23,
            checksRun: ["npm run lint -- src/components/BottomBar.tsx", "npm test"],
            warnings: ["Dependency installation still requires approval."],
            fullReply: "Updated the bottom navigation glass treatment and active state. Added validation checks and confirmed targeted tests passed. Remaining warning: dependency installation still requires approval."
        )
    )

    static let spaces: [MGSpaceSummary] = [
        MGSpaceSummary(
            id: "space-maxgravity-app",
            name: "Maxgravity App",
            chats: [
                MGChatSummary(id: thread.id, title: thread.title, lastActivity: .now.addingTimeInterval(-3200), isRunning: true, isPinned: true, thread: thread),
                MGChatSummary(id: "chat-auth", title: "Fix auth flow bug", lastActivity: .now.addingTimeInterval(-8600), isRunning: false, isPinned: false, thread: thread),
                MGChatSummary(id: "chat-onboarding", title: "Improve onboarding", lastActivity: .now.addingTimeInterval(-12400), isRunning: false, isPinned: false, thread: thread),
                MGChatSummary(id: "chat-dark", title: "Add dark mode", lastActivity: .now.addingTimeInterval(-16200), isRunning: false, isPinned: false, thread: thread)
            ],
            isPinned: true,
            statusText: "1 running"
        ),
        MGSpaceSummary(
            id: "space-rootline",
            name: "Rootline",
            chats: [
                MGChatSummary(id: "chat-rootline-review", title: "Review route performance", lastActivity: .now.addingTimeInterval(-5400), isRunning: false, isPinned: false, thread: thread)
            ],
            isPinned: false,
            statusText: nil
        ),
        MGSpaceSummary(
            id: "space-max-clouds",
            name: "Max Clouds",
            chats: [
                MGChatSummary(id: "chat-max-clouds", title: "Stabilize sync worker", lastActivity: .now.addingTimeInterval(-9600), isRunning: true, isPinned: false, thread: thread)
            ],
            isPinned: false,
            statusText: "Running"
        ),
        MGSpaceSummary(
            id: "space-1980",
            name: "1980 Control Center",
            chats: [],
            isPinned: false,
            statusText: nil
        ),
        MGSpaceSummary(
            id: "space-personal-os",
            name: "Personal OS",
            chats: [
                MGChatSummary(id: "chat-personal-os", title: "Summarize weekly notes", lastActivity: .now.addingTimeInterval(-1800), isRunning: false, isPinned: false, thread: thread)
            ],
            isPinned: false,
            statusText: nil
        )
    ]

    static let activityBuckets: [MGActivityBucket] = [
        MGActivityBucket(
            id: "running",
            title: "Running now",
            items: [
                MGActivityListItem(id: "run1", title: "Implement bottom bar", detail: "Maxgravity App", tone: .good, route: .chat(chatID: thread.id)),
                MGActivityListItem(id: "run2", title: "Stabilize sync worker", detail: "Max Clouds", tone: .neutral, route: .chat(chatID: "chat-max-clouds"))
            ]
        ),
        MGActivityBucket(
            id: "approval",
            title: "Needs approval",
            items: [
                MGActivityListItem(id: "approval1", title: "Approve dependency installation", detail: "Implement bottom bar", tone: .warning, route: .chat(chatID: thread.id))
            ]
        ),
        MGActivityBucket(
            id: "scheduled",
            title: "Scheduled",
            items: [
                MGActivityListItem(id: "scheduled1", title: "Run nightly tests", detail: "Scheduled for 11:00 PM", tone: .neutral, route: nil)
            ]
        )
    ]

    static let schedules: [MGScheduledTask] = [
        MGScheduledTask(id: "sch-1", title: "Run nightly tests", spaceName: "Maxgravity App", nextRun: .now.addingTimeInterval(36_000), frequency: "Every night", isEnabled: true, permissionMode: .sandbox, model: "Auto"),
        MGScheduledTask(id: "sch-2", title: "Summarize open approvals", spaceName: "Personal OS", nextRun: .now.addingTimeInterval(7200), frequency: "Weekdays", isEnabled: false, permissionMode: .askWhenNeeded, model: "GPT-4.1")
    ]

    static let remoteRoots: [MGRemoteFileNode] = [
        MGRemoteFileNode(
            id: "root-1",
            name: "Vaultline Web UI",
            path: "C:\\Users\\kuroi\\OneDrive\\Desktop\\Vaultline-V\\Best Version Of Vaultline Web UI",
            isDirectory: true,
            children: [
                MGRemoteFileNode(
                    id: "root-1-src",
                    name: "src",
                    path: "src",
                    isDirectory: true,
                    children: [
                        MGRemoteFileNode(
                            id: "root-1-src-components",
                            name: "components",
                            path: "src/components",
                            isDirectory: true,
                            children: [
                                MGRemoteFileNode(
                                    id: "root-1-file-1",
                                    name: "BottomBar.tsx",
                                    path: "src/components/BottomBar.tsx",
                                    isDirectory: false,
                                    children: []
                                )
                            ]
                        )
                    ]
                ),
                MGRemoteFileNode(id: "root-1-readme", name: "README.md", path: "README.md", isDirectory: false, children: [])
            ]
        ),
        MGRemoteFileNode(
            id: "root-2",
            name: "MaxPlayer",
            path: "C:\\Users\\kuroi\\OneDrive\\Desktop\\MaxPlayer",
            isDirectory: true,
            children: [
                MGRemoteFileNode(id: "root-2-file-1", name: "PlayerRoute.tsx", path: "src/routes/PlayerRoute.tsx", isDirectory: false, children: [])
            ]
        )
    ]
}
