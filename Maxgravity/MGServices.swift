import ActivityKit
import Foundation
import Observation
import UserNotifications
import Security
import CryptoKit

struct MGKeychainSession: Codable {
    let address: String
    let deviceId: String
    let deviceSecret: String
    let computerName: String
    let bridgeFingerprint: String
}

struct MGKeychainHelper {
    private static let service = "com.tryvaultline.maxgravity"
    private static let account = "paired-session"

    static func save(_ session: MGKeychainSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load() -> MGKeychainSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }
        
        return try? JSONDecoder().decode(MGKeychainSession.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

protocol MGBridgeClient {
    func fetchConnectionStatus() async throws -> MGComputerStatus?
    func listSpaces() async throws -> [MGSpaceSummary]
    func listActivity() async throws -> [MGActivityBucket]
    func listSchedules() async throws -> [MGScheduledTask]
    func availableModels() async throws -> [MGModelOption]
    func approvedRoots() async throws -> [MGRemoteFileNode]
    func capabilityMatrix() async throws -> [MGBridgeCapability]
    func browseWorkspace(rootId: String, path: String) async throws -> [MGRemoteFileNode]
    func readWorkspaceFile(rootId: String, path: String) async throws -> MGRemoteFileContent
    func listPlugins() async throws -> [MGPluginInfo]
    func importImage(rootId: String, path: String, fileName: String, data: Data) async throws -> String
    func preparePairingSession() async throws -> MGPairingQRCodePayload
    
    // Live integrations
    func isPaired() -> Bool
    func pairDevice(payload: MGPairingQRCodePayload, deviceName: String, fingerprint: String) async throws -> MGKeychainSession
    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String) async throws -> MGChatSummary
    func sendMessage(taskId: String, prompt: String, workspaceRoot: String) async throws
    func createFolder(rootId: String, path: String, name: String) async throws
    func getTask(taskId: String) async throws -> MGChatSummary
    func disconnect()
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
    var defaultModelID: String = "flash"
    var defaultPermissionMode: MGPermissionMode = .askWhenNeeded
    var defaultPlanMode: Bool = false
    var defaultSpaceID: String?
}

class MGRealBridgeClient: MGBridgeClient, MGSpacesRepository, MGTasksRepository, MGActivityRepository, MGWorkspaceRepository {
    private var session: MGKeychainSession? {
        MGKeychainHelper.load()
    }

    private var activeSession: MGKeychainSession {
        get throws {
            guard let s = session else {
                throw NSError(domain: "MGRealBridgeClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active paired session"])
            }
            return s
        }
    }

    func isPaired() -> Bool {
        return session != nil
    }

    func disconnect() {
        MGKeychainHelper.delete()
    }

    func pairDevice(payload: MGPairingQRCodePayload, deviceName: String, fingerprint: String) async throws -> MGKeychainSession {
        let httpAddress = payload.address
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        
        guard let url = URL(string: "\(httpAddress)/v1/connection/trust/register") else {
            throw NSError(domain: "MGRealBridgeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid bridge URL"])
        }
        
        struct TrustReq: Codable {
            let sessionId: String
            let token: String
            let deviceName: String
            let devicePublicKeyFingerprint: String
            let platform: String
        }
        
        let reqData = TrustReq(
            sessionId: payload.sessionId,
            token: payload.token,
            deviceName: deviceName,
            devicePublicKeyFingerprint: fingerprint,
            platform: "iOS"
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reqData)
        
        let urlSession = URLSession(configuration: .default, delegate: MGTrustPinningDelegate(expectedFingerprint: payload.bridgeFingerprint), delegateQueue: nil)
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errString = String(data: data, encoding: .utf8) ?? "Status code \(httpResponse.statusCode)"
            throw NSError(domain: "MGRealBridgeClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errString])
        }
        
        struct RegisterResp: Codable {
            let status: String
            let pendingDeviceId: String
        }
        
        let regResp = try JSONDecoder().decode(RegisterResp.self, from: data)
        let pendingId = regResp.pendingDeviceId
        
        // Polling loop
        guard let statusUrl = URL(string: "\(httpAddress)/v1/connection/trust/status?pendingDeviceId=\(pendingId)") else {
            throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid status URL"])
        }
        var statusRequest = URLRequest(url: statusUrl)
        statusRequest.httpMethod = "GET"
        
        struct StatusResp: Codable {
            struct Device: Codable {
                let id: String
                let name: String
            }
            let status: String
            let device: Device?
            let deviceSecret: String?
        }
        
        while true {
            let (statusData, statusResponse) = try await urlSession.data(for: statusRequest)
            guard let statusHttpResponse = statusResponse as? HTTPURLResponse, statusHttpResponse.statusCode == 200 else {
                throw NSError(domain: "MGRealBridgeClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Pairing was rejected or session expired."])
            }
            
            let statusObj = try JSONDecoder().decode(StatusResp.self, from: statusData)
            if statusObj.status == "approved", let dev = statusObj.device, let secret = statusObj.deviceSecret {
                let newSession = MGKeychainSession(
                    address: payload.address,
                    deviceId: dev.id,
                    deviceSecret: secret,
                    computerName: dev.name,
                    bridgeFingerprint: payload.bridgeFingerprint
                )
                _ = MGKeychainHelper.save(newSession)
                return newSession
            } else if statusObj.status == "rejected" {
                throw NSError(domain: "MGRealBridgeClient", code: 403, userInfo: [NSLocalizedDescriptionKey: "Pairing request was rejected."])
            }
            
            // Wait 2 seconds before polling again
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func performRequest<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let s = try activeSession
        let httpAddress = s.address
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        
        guard let url = URL(string: "\(httpAddress)\(path)") else {
            throw NSError(domain: "MGRealBridgeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(s.deviceSecret)", forHTTPHeaderField: "Authorization")
        request.setValue(s.deviceId, forHTTPHeaderField: "X-MG-Device-Id")
        if let body = body {
            request.httpBody = body
        }
        
        let urlSession = URLSession(configuration: .default, delegate: MGTrustPinningDelegate(expectedFingerprint: s.bridgeFingerprint), delegateQueue: nil)
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errString = String(data: data, encoding: .utf8) ?? "Status code \(httpResponse.statusCode)"
            throw NSError(domain: "MGRealBridgeClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errString])
        }
        
        let decoder = JSONDecoder.mgDecoder
        return try decoder.decode(T.self, from: data)
    }

    func fetchConnectionStatus() async throws -> MGComputerStatus? {
        do {
            let s = try activeSession
            struct HealthResponse: Codable {
                let status: String
                let bridgeVersion: String
                let time: String
            }
            let health: HealthResponse = try await performRequest(path: "/v1/connection/health")
            
            return MGComputerStatus(
                id: s.deviceId,
                computerName: s.computerName,
                isOnline: health.status == "Live",
                quality: .excellent,
                lastSync: Date(),
                encryption: "Pinned local transport",
                supportedPermissionModes: [.sandbox, .askWhenNeeded, .sensitiveAutoReview],
                connectionAddress: s.address,
                pairing: .live,
                liveBridge: .live
            )
        } catch {
            return nil
        }
    }

    func listSpaces() async throws -> [MGSpaceSummary] {
        return try await performRequest(path: "/v1/spaces")
    }

    func listActivity() async throws -> [MGActivityBucket] {
        let spaces = try await listSpaces()
        var runningItems: [MGActivityListItem] = []
        var approvalItems: [MGActivityListItem] = []
        
        for space in spaces {
            for chat in space.chats {
                if chat.isRunning {
                    runningItems.append(MGActivityListItem(
                        id: chat.id,
                        title: chat.title,
                        detail: space.name,
                        tone: .good,
                        route: .chat(chatID: chat.id)
                    ))
                }
                if chat.thread.approval != nil {
                    approvalItems.append(MGActivityListItem(
                        id: "approval-\(chat.id)",
                        title: chat.thread.approval?.title ?? "Approve changes",
                        detail: chat.title,
                        tone: .warning,
                        route: .chat(chatID: chat.id)
                    ))
                }
            }
        }
        
        return [
            MGActivityBucket(id: "running", title: "Running now", items: runningItems),
            MGActivityBucket(id: "approval", title: "Needs approval", items: approvalItems),
            MGActivityBucket(id: "scheduled", title: "Scheduled", items: [])
        ]
    }

    func listSchedules() async throws -> [MGScheduledTask] {
        return []
    }

    func availableModels() async throws -> [MGModelOption] {
        struct ModelResponse: Codable {
            let id: String
            let name: String
            let description: String
            let speed: String
            let effort: String
            let isRecommended: Bool
            let state: String
        }

        do {
            let models: [ModelResponse] = try await performRequest(path: "/v1/models")
            return models.map { model in
                let availability: MGCapabilityState
                switch model.state.lowercased() {
                case "live": availability = .live
                case "partial": availability = .partial
                case "mock": availability = .mock
                default: availability = .unsupported
                }
                return MGModelOption(
                    id: model.id,
                    title: model.name,
                    subtitle: model.description,
                    speedLabel: model.speed,
                    effortLabel: model.effort,
                    isRecommended: model.isRecommended,
                    availability: availability
                )
            }
        } catch {
            #if DEBUG
            return MGFixtures.models
            #else
            throw error
            #endif
        }
    }

    func approvedRoots() async throws -> [MGRemoteFileNode] {
        return try await performRequest(path: "/v1/workspace/roots")
    }

    func browseWorkspace(rootId: String, path: String = ".") async throws -> [MGRemoteFileNode] {
        guard let encodedRoot = rootId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "MGRealBridgeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid workspace query"])
        }
        return try await performRequest(path: "/v1/workspace/browse?rootId=\(encodedRoot)&path=\(encodedPath)")
    }

    func readWorkspaceFile(rootId: String, path: String) async throws -> MGRemoteFileContent {
        guard let encodedRoot = rootId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "MGRealBridgeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid file query"])
        }
        return try await performRequest(path: "/v1/workspace/file?rootId=\(encodedRoot)&path=\(encodedPath)")
    }

    func listPlugins() async throws -> [MGPluginInfo] {
        return try await performRequest(path: "/v1/tools")
    }

    func importImage(rootId: String, path: String, fileName: String, data: Data) async throws -> String {
        struct ImportImageBody: Codable {
            let rootId: String
            let path: String
            let fileName: String
            let base64Data: String
        }
        struct ImportImageResponse: Codable {
            let status: String
            let path: String
        }

        let body = ImportImageBody(
            rootId: rootId,
            path: path,
            fileName: fileName,
            base64Data: data.base64EncodedString()
        )
        let bodyData = try JSONEncoder().encode(body)
        let response: ImportImageResponse = try await performRequest(path: "/v1/workspace/import-image", method: "POST", body: bodyData)
        return response.path
    }

    func capabilityMatrix() async throws -> [MGBridgeCapability] {
        struct CapabilityResponse: Codable {
            struct BridgeCap: Codable {
                let id: String
                let title: String
                let status: String
                let notes: String
            }
            let bridge: [BridgeCap]
        }
        do {
            let cap: CapabilityResponse = try await performRequest(path: "/v1/capabilities")
            return cap.bridge.map { bc in
                let state: MGCapabilityState
                switch bc.status.lowercased() {
                case "live": state = .live
                case "partial": state = .partial
                case "mock": state = .mock
                default: state = .unsupported
                }
                return MGBridgeCapability(id: bc.id, title: bc.title, state: state, detail: bc.notes)
            }
        } catch {
            return []
        }
    }

    func preparePairingSession() async throws -> MGPairingQRCodePayload {
        #if DEBUG
        return MGFixtures.pairingPayload
        #else
        throw NSError(domain: "MGRealBridgeClient", code: 501, userInfo: [NSLocalizedDescriptionKey: "Client-side pairing preparation is unavailable in release mode."])
        #endif
    }

    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String) async throws -> MGChatSummary {
        struct CreateTaskBody: Codable {
            let spaceId: String
            let title: String
            let prompt: String
            let workspaceRoot: String
            let selectedModelId: String
        }
        let body = CreateTaskBody(spaceId: spaceId, title: title, prompt: prompt, workspaceRoot: workspaceRoot, selectedModelId: selectedModelId)
        let bodyData = try JSONEncoder().encode(body)
        
        struct CreateTaskResponse: Codable {
            let conversationId: String
            let title: String
            let status: String
        }
        
        let resp: CreateTaskResponse = try await performRequest(path: "/v1/tasks", method: "POST", body: bodyData)
        return try await getTask(taskId: resp.conversationId)
    }

    func sendMessage(taskId: String, prompt: String, workspaceRoot: String) async throws {
        struct SendMsgBody: Codable {
            let prompt: String
            let workspaceRoot: String
        }
        let body = SendMsgBody(prompt: prompt, workspaceRoot: workspaceRoot)
        let bodyData = try JSONEncoder().encode(body)
        
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await performRequest(path: "/v1/tasks/\(taskId)/messages", method: "POST", body: bodyData)
    }

    func createFolder(rootId: String, path: String, name: String) async throws {
        struct CreateFolderBody: Codable {
            let rootId: String
            let path: String
            let name: String
        }
        let body = CreateFolderBody(rootId: rootId, path: path, name: name)
        let bodyData = try JSONEncoder().encode(body)
        
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await performRequest(path: "/v1/workspace/create-folder", method: "POST", body: bodyData)
    }

    func getTask(taskId: String) async throws -> MGChatSummary {
        return try await performRequest(path: "/v1/tasks/\(taskId)")
    }
    
    // MGSpacesRepository, MGTasksRepository, MGActivityRepository, MGWorkspaceRepository conformance
    func spaces() async throws -> [MGSpaceSummary] {
        return try await listSpaces()
    }
    
    func models() async throws -> [MGModelOption] {
        return try await availableModels()
    }
    
    func activityBuckets() async throws -> [MGActivityBucket] {
        return try await listActivity()
    }
    
    func schedules() async throws -> [MGScheduledTask] {
        return try await listSchedules()
    }
    
    func roots() async throws -> [MGRemoteFileNode] {
        return try await approvedRoots()
    }
}

class MGTrustPinningDelegate: NSObject, URLSessionDelegate {
    let expectedFingerprint: String
    
    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint.replacingOccurrences(of: ":", with: "").lowercased()
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let cert = certificates.first {
            let data = SecCertificateCopyData(cert) as Data
            let digest = SHA256.hash(data: data)
            let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
            
            if fingerprint.lowercased() == expectedFingerprint {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }
        
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

class MGManualPairingTrustDelegate: NSObject, URLSessionDelegate {
    var retrievedFingerprint: String?
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let cert = certificates.first {
            let data = SecCertificateCopyData(cert) as Data
            let digest = SHA256.hash(data: data)
            retrievedFingerprint = digest.map { String(format: "%02x", $0) }.joined()
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

struct MGMockBridgeClient: MGBridgeClient, MGSpacesRepository, MGTasksRepository, MGWorkspaceRepository {
    func fetchConnectionStatus() async throws -> MGComputerStatus? { nil }
    func listSpaces() async throws -> [MGSpaceSummary] { MGFixtures.spaces }
    func listActivity() async throws -> [MGActivityBucket] { MGFixtures.activityBuckets }
    func listSchedules() async throws -> [MGScheduledTask] { MGFixtures.schedules }
    func availableModels() async throws -> [MGModelOption] { MGFixtures.models }
    func approvedRoots() async throws -> [MGRemoteFileNode] { MGFixtures.remoteRoots }
    func browseWorkspace(rootId: String, path: String) async throws -> [MGRemoteFileNode] { [] }
    func readWorkspaceFile(rootId: String, path: String) async throws -> MGRemoteFileContent { MGRemoteFileContent(path: path, content: "") }
    func listPlugins() async throws -> [MGPluginInfo] { [] }
    func importImage(rootId: String, path: String, fileName: String, data: Data) async throws -> String { path + "/" + fileName }
    func capabilityMatrix() async throws -> [MGBridgeCapability] { MGFixtures.capabilities }
    func preparePairingSession() async throws -> MGPairingQRCodePayload { MGFixtures.pairingPayload }
    
    func isPaired() -> Bool { false }
    func pairDevice(payload: MGPairingQRCodePayload, deviceName: String, fingerprint: String) async throws -> MGKeychainSession {
        return MGKeychainSession(address: "", deviceId: "", deviceSecret: "", computerName: "", bridgeFingerprint: "")
    }
    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String) async throws -> MGChatSummary {
        return MGFixtures.spaces[0].chats[0]
    }
    func sendMessage(taskId: String, prompt: String, workspaceRoot: String) async throws {}
    func createFolder(rootId: String, path: String, name: String) async throws {}
    func getTask(taskId: String) async throws -> MGChatSummary {
        return MGFixtures.spaces[0].chats[0]
    }
    func disconnect() {}

    func spaces() async throws -> [MGSpaceSummary] { MGFixtures.spaces }
    func models() async throws -> [MGModelOption] { MGFixtures.models }
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
    var selectedSection: MGAppSection = .spaces
    var presentedSheet: MGSheetDestination?
    var presentedFullScreen: MGFullScreenDestination?

    var connection: MGComputerStatus?
    #if DEBUG
    var trustedDevices: [MGTrustedDevice] = MGFixtures.trustedDevices
    var pairingPayload: MGPairingQRCodePayload = MGFixtures.pairingPayload
    #else
    var trustedDevices: [MGTrustedDevice] = []
    var pairingPayload: MGPairingQRCodePayload = MGPairingQRCodePayload(
        sessionId: "",
        address: "",
        token: "",
        bridgeFingerprint: "",
        expiresAt: Date(),
        bridgeVersion: ""
    )
    #endif
    var notificationPreferences = MGNotificationPreferences()
    var notificationsAuthorized = false
    var liveActivityDiagnostics = "Not started"
    var workspaceNodesByRoot: [String: [MGRemoteFileNode]] = [:]
    var workspaceLoadingRoots: Set<String> = []
    var openedWorkspaceRootID: String?
    var workspaceFileContents: [String: String] = [:]
    var plugins: [MGPluginInfo] = []
    var pickedPhotos: [MGPickedPhoto] = []

    var expandedSpaceIDs: Set<String> = []

    var draftPrompt = ""
    var draftMicrophoneEnabled = false
    var draftContext = MGTaskContext(
        workingFolder: "",
        permissionMode: .askWhenNeeded,
        planMode: false,
        selectedModel: MGModelOption(id: "flash", title: "Gemini Flash", subtitle: "Recommended Antigravity route", speedLabel: "Fast", effortLabel: "Balanced", isRecommended: true, availability: .live),
        mentionedFiles: []
    )

    private let bridge: MGBridgeClient
    private var settingsStore: MGSettingsStore
    private let liveActivityController = MGTaskLiveActivityController()
    private var webSocketTask: URLSessionWebSocketTask?

    init(
        bridge: MGBridgeClient = MGRealBridgeClient(),
        settingsStore: MGSettingsStore = MGInMemorySettingsStore()
    ) {
        self.bridge = bridge
        self.settingsStore = settingsStore
    }

    var hasConnectedComputer: Bool { connection != nil }

    func bootstrap() async {
        do {
            connection = try await bridge.fetchConnectionStatus()
            if connection != nil {
                spaces = try await bridge.listSpaces()
                activityBuckets = try await bridge.listActivity()
                schedules = try await bridge.listSchedules()
                models = try await bridge.availableModels()
                remoteRoots = try await bridge.approvedRoots()
                capabilities = try await bridge.capabilityMatrix()
                plugins = try await bridge.listPlugins()
                
                // Initialize default workspace configurations
                if let firstRoot = remoteRoots.first {
                    if draftContext.workingFolder.isEmpty {
                        draftContext.workingFolder = firstRoot.path
                    }
                    if openedWorkspaceRootID == nil {
                        openedWorkspaceRootID = firstRoot.id
                    }
                }
                if let firstModel = models.first {
                    draftContext.selectedModel = firstModel
                }
                if expandedSpaceIDs.isEmpty, let firstSpace = spaces.first {
                    expandedSpaceIDs.insert(firstSpace.id)
                }
            } else {
                // If not connected, clear live data
                spaces = []
                activityBuckets = []
                schedules = []
                models = []
                remoteRoots = []
                capabilities = []
                plugins = []
            }
            #if DEBUG
            pairingPayload = try await bridge.preparePairingSession()
            #endif
        } catch {
            liveActivityDiagnostics = "Bridge bootstrap failed: \(error.localizedDescription)"
        }
    }

    func connectMockComputer() {
        connection = MGFixtures.connectedComputer
        spaces = MGFixtures.spaces
        activityBuckets = MGFixtures.activityBuckets
        schedules = MGFixtures.schedules
        models = MGFixtures.models
        remoteRoots = MGFixtures.remoteRoots
        capabilities = MGFixtures.capabilities
    }

    func pair(payload: MGPairingQRCodePayload, name: String = "iOS Companion") async throws {
        let fingerprint = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).uppercased()
        _ = try await bridge.pairDevice(payload: payload, deviceName: name, fingerprint: String(fingerprint))
        await bootstrap()
    }

    func disconnectCurrentComputer() {
        bridge.disconnect()
        stopTaskEventStreaming()
        connection = nil
        spaces = []
        activityBuckets = []
        schedules = []
        models = []
        remoteRoots = []
        capabilities = []
        path = []
        presentedSheet = nil
        presentedFullScreen = nil
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
        selectedSection = .spaces
        path.append(.chat(chatID: chatID))
        startTaskEventStreaming(taskId: chatID)
    }

    func openNewTask(spaceID: String) {
        presentedFullScreen = .newTask(spaceID: spaceID)
    }

    func selectSection(_ section: MGAppSection) {
        selectedSection = section
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

        let prompt = draftPrompt
        let currentMentionedFiles = draftContext.mentionedFiles
        let currentPickedPhotos = pickedPhotos
        let space = spaces[spaceIndex]
        let newChatID = UUID().uuidString
        let now = Date()
        
        let initialThread = MGTaskThread(
            id: newChatID,
            title: title,
            stateText: "Planning changes",
            stateTone: .neutral,
            messages: [
                MGThreadMessage(
                    id: UUID().uuidString,
                    role: .user,
                    body: prompt,
                    timestamp: now,
                    delivered: true,
                    attachments: currentMentionedFiles.map {
                        MGArtifactSummary(id: UUID().uuidString, kind: .file, title: $0, detail: "Mentioned file")
                    } + currentPickedPhotos.enumerated().map { index, _ in
                        MGArtifactSummary(id: UUID().uuidString, kind: .screenshot, title: "Selected image \(index + 1)", detail: "Attached from Photos")
                    }
                )
            ],
            timeline: [
                MGActivityEvent(
                    id: UUID().uuidString,
                    title: "Planning changes",
                    detail: "Interpreting request and preparing task context...",
                    duration: "Live",
                    tone: .neutral,
                    isComplete: false
                )
            ],
            files: currentMentionedFiles,
            diffs: [],
            commands: [],
            approval: nil,
            completion: nil
        )
        
        let optChat = MGChatSummary(
            id: newChatID,
            title: title,
            lastActivity: now,
            isRunning: true,
            isPinned: false,
            thread: initialThread
        )
        
        spaces[spaceIndex].chats.insert(optChat, at: 0)
        expandedSpaceIDs.insert(spaceID)
        draftPrompt = ""
        pickedPhotos = []
        presentedFullScreen = nil
        openChat(optChat.id)
        
        if let connection {
            liveActivityController.startIfPossible(taskTitle: title, computerName: connection.computerName, stage: "Planning changes")
            liveActivityDiagnostics = liveActivityController.diagnostics
        }
        
        Task {
            do {
                var livePrompt = prompt
                var importedPhotoPaths: [String] = []
                if !currentPickedPhotos.isEmpty {
                    importedPhotoPaths = try await importPickedPhotos(currentPickedPhotos)
                    if !importedPhotoPaths.isEmpty {
                        let attachmentBlock = importedPhotoPaths.map { "- \($0)" }.joined(separator: "\n")
                        livePrompt += "\n\nAttached images saved into the workspace:\n\(attachmentBlock)"
                    }
                }

                let realChat = try await bridge.createTask(
                    spaceId: spaceID,
                    title: title,
                    prompt: livePrompt,
                    workspaceRoot: draftContext.workingFolder,
                    selectedModelId: draftContext.selectedModel.id
                )
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.spaces[spaceIndex].chats.firstIndex(where: { $0.id == newChatID }) {
                        var mergedChat = realChat
                        mergedChat.thread.files = currentMentionedFiles + importedPhotoPaths
                        self.spaces[spaceIndex].chats[idx] = mergedChat
                        
                        // Swap route if open
                        if let pathIdx = self.path.firstIndex(of: .chat(chatID: newChatID)) {
                            self.path[pathIdx] = .chat(chatID: realChat.id)
                        }
                        
                        self.startTaskEventStreaming(taskId: realChat.id)
                    }
                }
            } catch {
                print("Failed to spawn live task: \(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.spaces[spaceIndex].chats.firstIndex(where: { $0.id == newChatID }) {
                        self.spaces[spaceIndex].chats[idx].isRunning = false
                        self.spaces[spaceIndex].chats[idx].thread.stateText = "Task failed"
                        self.spaces[spaceIndex].chats[idx].thread.stateTone = .critical
                        self.spaces[spaceIndex].chats[idx].thread.timeline.append(
                            MGActivityEvent(
                                id: UUID().uuidString,
                                title: "Task failed",
                                detail: "Bridge call failed: \(error.localizedDescription)",
                                duration: "0s",
                                tone: .critical,
                                isComplete: true
                            )
                        )
                        self.liveActivityController.end()
                    }
                }
            }
        }
        
        return optChat
    }

    private func importPickedPhotos(_ photos: [MGPickedPhoto]) async throws -> [String] {
        guard let targetRoot = resolveRootForWorkingFolder() else {
            return []
        }

        let relativeFolder = relativeFolderPath(for: draftContext.workingFolder, rootPath: targetRoot.path)
        let uploadFolderName = "maxgravity-imports"
        try? await bridge.createFolder(rootId: targetRoot.id, path: relativeFolder, name: uploadFolderName)
        let finalFolder = [relativeFolder, uploadFolderName]
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")

        var savedPaths: [String] = []
        for (index, photo) in photos.enumerated() {
            let fileName = "ios-photo-\(Int(Date().timeIntervalSince1970))-\(index + 1).jpg"
            let saved = try await bridge.importImage(rootId: targetRoot.id, path: finalFolder.isEmpty ? "." : finalFolder, fileName: fileName, data: photo.data)
            savedPaths.append(saved)
        }
        return savedPaths
    }

    private func resolveRootForWorkingFolder() -> MGRemoteFileNode? {
        remoteRoots
            .sorted { $0.path.count > $1.path.count }
            .first(where: { draftContext.workingFolder.hasPrefix($0.path) })
    }

    private func relativeFolderPath(for absolutePath: String, rootPath: String) -> String {
        let normalizedRoot = rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
        let normalizedAbsolute = absolutePath.trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
        if normalizedAbsolute == normalizedRoot {
            return "."
        }
        let relative = normalizedAbsolute.replacingOccurrences(of: normalizedRoot + "\\", with: "")
            .replacingOccurrences(of: normalizedRoot + "/", with: "")
        return relative.isEmpty ? "." : relative.replacingOccurrences(of: "\\", with: "/")
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
    }

    func stopTaskEventStreaming() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func listenForWsEvents(_ task: URLSessionWebSocketTask, taskId: String) {
        task.receive { [weak self] result in
            guard let self = self, self.webSocketTask === task else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleWsEventData(data, taskId: taskId)
                    }
                case .data(let data):
                    self.handleWsEventData(data, taskId: taskId)
                @unknown default:
                    break
                }
                self.listenForWsEvents(task, taskId: taskId)
            case .failure(let error):
                print("WS connection failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleWsEventData(_ data: Data, taskId: String) {
        struct WSEvent: Codable {
            let type: String
            let taskId: String
            let stage: String?
            let detail: String?
            let approvalId: String?
            let action: String?
            let reason: String?
            let affectedItems: [String]?
        }
        
        guard let event = try? JSONDecoder().decode(WSEvent.self, from: data) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for spaceIndex in self.spaces.indices {
                if let chatIndex = self.spaces[spaceIndex].chats.firstIndex(where: { $0.id == taskId }) {
                    var chat = self.spaces[spaceIndex].chats[chatIndex]
                    
                    switch event.type {
                    case "task.stage":
                        if let stage = event.stage {
                            chat.thread.stateText = stage
                            
                            let tone: MGActivityTone
                            switch stage {
                            case "Planning changes", "Checking workspace", "Reading files":
                                tone = .neutral
                            case "Updating styles", "Applying changes", "Running commands", "Running tests":
                                tone = .good
                            case "Awaiting approval":
                                tone = .warning
                            case "Task completed":
                                tone = .good
                                chat.isRunning = false
                            case "Task failed":
                                tone = .critical
                                chat.isRunning = false
                            default:
                                tone = .neutral
                            }
                            chat.thread.stateTone = tone
                            
                            let newEvent = MGActivityEvent(
                                id: UUID().uuidString,
                                title: stage,
                                detail: event.detail ?? "",
                                duration: "Live",
                                tone: tone,
                                isComplete: stage == "Task completed"
                            )
                            chat.thread.timeline.append(newEvent)
                            
                            if chat.isRunning {
                                self.liveActivityController.update(
                                    stage: stage,
                                    status: chat.isRunning ? "Running" : "Idle",
                                    approvalRequired: chat.thread.approval != nil
                                )
                            } else {
                                self.liveActivityController.end()
                            }
                        }
                    case "approval.required":
                        if let approvalId = event.approvalId {
                            let approval = MGApprovalRequest(
                                id: approvalId,
                                title: event.action ?? "Approve required changes",
                                summary: event.reason ?? "",
                                scope: "Bridge validation scope",
                                affectedItems: event.affectedItems ?? []
                            )
                            chat.thread.approval = approval
                            chat.thread.stateText = "Awaiting approval"
                            chat.thread.stateTone = .warning
                            
                            self.liveActivityController.update(
                                stage: "Awaiting approval",
                                status: "Suspended",
                                approvalRequired: true
                            )
                        }
                    default:
                        break
                    }
                    
                    self.spaces[spaceIndex].chats[chatIndex] = chat
                    break
                }
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

    func addPickedPhoto(data: Data) {
        pickedPhotos.insert(MGPickedPhoto(id: UUID().uuidString, data: data), at: 0)
    }

    func removePickedPhoto(_ id: String) {
        pickedPhotos.removeAll { $0.id == id }
    }

    var mentionableFiles: [String] {
        let liveFiles = workspaceNodesByRoot.values
            .flatMap { $0 }
            .filter { !$0.isDirectory }
            .map(\.path)

        let roots = remoteRoots.map(\.path)
        return Array(Set(liveFiles + roots)).sorted()
    }

    func loadWorkspaceRoot(_ root: MGRemoteFileNode) async {
        if workspaceLoadingRoots.contains(root.id) {
            return
        }

        workspaceLoadingRoots.insert(root.id)
        defer { workspaceLoadingRoots.remove(root.id) }

        do {
            workspaceNodesByRoot[root.id] = try await bridge.browseWorkspace(rootId: root.id, path: ".")
            openedWorkspaceRootID = root.id
        } catch {
            liveActivityDiagnostics = "Workspace load failed: \(error.localizedDescription)"
        }
    }

    func openWorkspaceFile(rootId: String, path: String) async {
        do {
            let file = try await bridge.readWorkspaceFile(rootId: rootId, path: path)
            self.workspaceFileContents[file.path] = file.content
            self.path.append(.codeViewer(fileRef: file.path))
        } catch {
            liveActivityDiagnostics = "File read failed: \(error.localizedDescription)"
        }
    }
}

enum MGFixtures {
    static let models: [MGModelOption] = [
        MGModelOption(id: "flash", title: "Gemini Flash", subtitle: "Live Antigravity route", speedLabel: "Fast", effortLabel: "Balanced", isRecommended: true, availability: .live),
        MGModelOption(id: "pro", title: "Gemini Pro", subtitle: "Live Antigravity route", speedLabel: "Deliberate", effortLabel: "High", isRecommended: false, availability: .live),
        MGModelOption(id: "flash_lite", title: "Gemini Flash Lite", subtitle: "Live Antigravity route", speedLabel: "Ultra fast", effortLabel: "Low", isRecommended: false, availability: .live)
    ]

    static let pairingPayload = MGPairingQRCodePayload(
        sessionId: "mock-session-12345678",
        address: "ws://192.168.1.18:59443",
        token: "MG-7K4Q-98N1",
        bridgeFingerprint: "3B:A7:E1:44:3F:92",
        expiresAt: .now.addingTimeInterval(300),
        bridgeVersion: "0.1.0"
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
