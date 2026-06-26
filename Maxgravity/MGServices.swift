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

enum MGTrustMismatchReason {
    case pairing
    case reconnect
}

enum MGBridgeTrustError: LocalizedError {
    case invalidBridgeURL
    case missingApprovedHost
    case hostMismatch(expected: String, actual: String)
    case certificateUnavailable(host: String)
    case certificateValidationFailed(host: String)
    case fingerprintMismatch(host: String, expectedSuffix: String, actualSuffix: String)
    case identityChanged(host: String, expectedSuffix: String, actualSuffix: String)

    var errorDescription: String? {
        switch self {
        case .invalidBridgeURL:
            return "Secure connection failed."
        case .missingApprovedHost:
            return "Bridge host could not be verified."
        case .hostMismatch:
            return "Bridge host verification failed."
        case .certificateUnavailable:
            return "Bridge identity data is unavailable."
        case .certificateValidationFailed:
            return "Bridge identity could not be verified."
        case .fingerprintMismatch:
            return "Bridge fingerprint verification failed."
        case .identityChanged:
            return "Bridge identity changed."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .invalidBridgeURL: "INVALID_URL"
        case .missingApprovedHost: "MISSING_HOST"
        case .hostMismatch: "HOST_MISMATCH"
        case .certificateUnavailable: "CERT_UNAVAILABLE"
        case .certificateValidationFailed: "CERT_VALIDATION_FAILED"
        case .fingerprintMismatch: "PIN_MISMATCH"
        case .identityChanged: "IDENTITY_CHANGED"
        }
    }

    var host: String? {
        switch self {
        case .hostMismatch(let expected, _): return expected
        case .certificateUnavailable(let host),
             .certificateValidationFailed(let host),
             .fingerprintMismatch(let host, _, _),
             .identityChanged(let host, _, _):
            return host
        case .invalidBridgeURL, .missingApprovedHost:
            return nil
        }
    }

    var certificateSuffix: String? {
        switch self {
        case .fingerprintMismatch(_, let expectedSuffix, let actualSuffix),
             .identityChanged(_, let expectedSuffix, let actualSuffix):
            return "\(expectedSuffix)/\(actualSuffix)"
        default:
            return nil
        }
    }
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
    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String, clientRequestId: String) async throws -> MGChatSummary
    func sendMessage(taskId: String, prompt: String, workspaceRoot: String, clientRequestId: String) async throws
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

    private func approvedHost(from address: String, fallback: String?) throws -> String {
        if let fallback, !fallback.isEmpty {
            return fallback
        }

        let httpAddress = address
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")

        guard let host = URL(string: httpAddress)?.host, !host.isEmpty else {
            throw MGBridgeTrustError.missingApprovedHost
        }

        return host
    }

    private func pinnedData(for request: URLRequest, address: String, fallbackHost: String?, expectedFingerprint: String, mismatchReason: MGTrustMismatchReason) async throws -> (Data, URLResponse) {
        let host = try approvedHost(from: address, fallback: fallbackHost)
        let delegate = MGTrustPinningDelegate(
            expectedHost: host,
            expectedFingerprint: expectedFingerprint,
            mismatchReason: mismatchReason
        )
        let urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
            return try await urlSession.data(for: request)
        } catch {
            if let trustError = delegate.lastFailure {
                throw trustError
            }
            throw error
        }
    }

    private func inspectedData(for request: URLRequest, address: String, fallbackHost: String?) async throws -> (Data, URLResponse, String) {
        let host = try approvedHost(from: address, fallback: fallbackHost)
        let delegate = MGManualPairingTrustDelegate(expectedHost: host)
        let urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let fingerprint = delegate.retrievedFingerprint else {
                throw MGBridgeTrustError.certificateUnavailable(host: host)
            }
            return (data, response, fingerprint)
        } catch {
            if let trustError = delegate.lastFailure {
                throw trustError
            }
            throw error
        }
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
            let token: String?
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
        
        let (data, response) = try await pinnedData(
            for: request,
            address: payload.address,
            fallbackHost: payload.httpsHost,
            expectedFingerprint: payload.bridgeFingerprint,
            mismatchReason: .pairing
        )
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw bridgeHTTPError(statusCode: httpResponse.statusCode, data: data)
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
        
        for _ in 0..<150 {
            try Task.checkCancellation()
            let (statusData, statusResponse) = try await pinnedData(
                for: statusRequest,
                address: payload.address,
                fallbackHost: payload.httpsHost,
                expectedFingerprint: payload.bridgeFingerprint,
                mismatchReason: .pairing
            )
            guard let statusHttpResponse = statusResponse as? HTTPURLResponse else {
                throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid pairing response."])
            }
            guard statusHttpResponse.statusCode == 200 else {
                throw bridgeHTTPError(statusCode: statusHttpResponse.statusCode, data: statusData)
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

        throw NSError(domain: "MGRealBridgeClient", code: 408, userInfo: [NSLocalizedDescriptionKey: "Pairing approval timed out."])
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
        
        let (data, response) = try await pinnedData(
            for: request,
            address: s.address,
            fallbackHost: nil,
            expectedFingerprint: s.bridgeFingerprint,
            mismatchReason: .reconnect
        )
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "MGRealBridgeClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw bridgeHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        
        let decoder = JSONDecoder.mgDecoder
        return try decoder.decode(T.self, from: data)
    }

    private func bridgeHTTPError(statusCode: Int, data: Data) -> NSError {
        struct ErrorEnvelope: Codable {
            let error: String?
            let message: String?
        }

        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let code = envelope?.error ?? "HTTP_\(statusCode)"
        let message: String

        switch statusCode {
        case 400:
            message = "The bridge rejected an invalid request."
        case 401:
            message = "This iPhone is not authorized for the bridge."
        case 403:
            message = envelope?.message ?? "This trusted device is not allowed to perform that action."
        case 404:
            message = "The requested bridge resource was not found."
        case 409:
            message = "The bridge already handled this operation."
        case 429:
            message = "The bridge is receiving too many requests. Wait a moment and try again."
        case 500...599:
            message = "The bridge could not complete the request."
        default:
            message = envelope?.message ?? "Bridge request failed."
        }

        return NSError(domain: "MGRealBridgeClient", code: statusCode, userInfo: [
            NSLocalizedDescriptionKey: message,
            "BridgeErrorCode": code
        ])
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
            if case MGBridgeTrustError.identityChanged = error {
                disconnect()
            }
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
            struct Provider: Codable {
                let id: String
                let name: String
            }

            struct ModelIdentity: Codable {
                let id: String
                let name: String
            }

            struct AgentRuntime: Codable {
                let id: String
                let name: String
                let status: String?
            }

            let id: String
            let name: String
            let description: String
            let provider: Provider?
            let model: ModelIdentity?
            let agentRuntime: AgentRuntime?
            let speed: String
            let effort: String
            let capabilities: [String]?
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
                    providerID: model.provider?.id ?? "antigravity",
                    providerName: model.provider?.name ?? "Antigravity",
                    modelID: model.model?.id ?? model.id,
                    modelName: model.model?.name ?? model.name.replacingOccurrences(of: "Antigravity ", with: ""),
                    runtimeID: model.agentRuntime?.id ?? "antigravity-agent-cli",
                    runtimeName: model.agentRuntime?.name ?? "Antigravity Agent CLI",
                    speedLabel: model.speed,
                    effortLabel: model.effort,
                    capabilities: model.capabilities ?? ["Chat", "Workspace context", "Task execution"],
                    isRecommended: model.isRecommended,
                    availability: availability
                )
            }
        } catch {
            #if DEBUG
            return MGPreviewFixtures.models
            #else
            throw error
            #endif
        }
    }

    func approvedRoots() async throws -> [MGRemoteFileNode] {
        return try await performRequest(path: "/v1/workspace/roots")
    }

    func browseWorkspace(rootId: String, path: String = ".") async throws -> [MGRemoteFileNode] {
        let requestPath = try encodedRequestPath("/v1/workspace/browse", queryItems: [
            URLQueryItem(name: "rootId", value: rootId),
            URLQueryItem(name: "path", value: path)
        ])
        return try await performRequest(path: requestPath)
    }

    func readWorkspaceFile(rootId: String, path: String) async throws -> MGRemoteFileContent {
        let requestPath = try encodedRequestPath("/v1/workspace/file", queryItems: [
            URLQueryItem(name: "rootId", value: rootId),
            URLQueryItem(name: "path", value: path)
        ])
        return try await performRequest(path: requestPath)
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
        return MGPreviewFixtures.pairingPayload
        #else
        throw NSError(domain: "MGRealBridgeClient", code: 501, userInfo: [NSLocalizedDescriptionKey: "Client-side pairing preparation is unavailable in release mode."])
        #endif
    }

    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String, clientRequestId: String) async throws -> MGChatSummary {
        struct CreateTaskBody: Codable {
            let spaceId: String
            let title: String
            let prompt: String
            let workspaceRoot: String
            let selectedModelId: String
            let clientRequestId: String
        }
        let body = CreateTaskBody(spaceId: spaceId, title: title, prompt: prompt, workspaceRoot: workspaceRoot, selectedModelId: selectedModelId, clientRequestId: clientRequestId)
        let bodyData = try JSONEncoder().encode(body)
        
        struct CreateTaskResponse: Codable {
            let conversationId: String
            let title: String
            let status: String
        }
        
        let resp: CreateTaskResponse = try await performRequest(path: "/v1/tasks", method: "POST", body: bodyData)
        return try await getTask(taskId: resp.conversationId)
    }

    func sendMessage(taskId: String, prompt: String, workspaceRoot: String, clientRequestId: String) async throws {
        struct SendMsgBody: Codable {
            let prompt: String
            let workspaceRoot: String
            let clientRequestId: String
        }
        let body = SendMsgBody(prompt: prompt, workspaceRoot: workspaceRoot, clientRequestId: clientRequestId)
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

    private func encodedRequestPath(_ path: String, queryItems: [URLQueryItem]) throws -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems

        guard let encoded = components.string else {
            throw NSError(domain: "MGRealBridgeClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid bridge query."])
        }
        return encoded
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
    let expectedHost: String
    let expectedFingerprint: String
    let mismatchReason: MGTrustMismatchReason
    var lastFailure: MGBridgeTrustError?
    
    init(expectedHost: String, expectedFingerprint: String, mismatchReason: MGTrustMismatchReason) {
        self.expectedHost = expectedHost
        self.expectedFingerprint = expectedFingerprint.replacingOccurrences(of: ":", with: "").lowercased()
        self.mismatchReason = mismatchReason
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let actualHost = challenge.protectionSpace.host
        guard actualHost == expectedHost else {
            lastFailure = .hostMismatch(expected: expectedHost, actual: actualHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let cert = certificates.first else {
            lastFailure = .certificateUnavailable(host: expectedHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let data = SecCertificateCopyData(cert) as Data
        let digest = SHA256.hash(data: data)
        let observedFingerprint = digest.map { String(format: "%02x", $0) }.joined()

        guard observedFingerprint.lowercased() == expectedFingerprint else {
            let expectedSuffix = String(expectedFingerprint.suffix(8)).uppercased()
            let actualSuffix = String(observedFingerprint.suffix(8)).uppercased()
            lastFailure = mismatchReason == .reconnect
                ? .identityChanged(host: expectedHost, expectedSuffix: expectedSuffix, actualSuffix: actualSuffix)
                : .fingerprintMismatch(host: expectedHost, expectedSuffix: expectedSuffix, actualSuffix: actualSuffix)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let policy = SecPolicyCreateSSL(true, expectedHost as CFString)
        SecTrustSetPolicies(serverTrust, policy)
        SecTrustSetAnchorCertificates(serverTrust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            lastFailure = .certificateValidationFailed(host: expectedHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

class MGManualPairingTrustDelegate: NSObject, URLSessionDelegate {
    let expectedHost: String
    var retrievedFingerprint: String?
    var lastFailure: MGBridgeTrustError?

    init(expectedHost: String) {
        self.expectedHost = expectedHost
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let actualHost = challenge.protectionSpace.host
        guard actualHost == expectedHost else {
            lastFailure = .hostMismatch(expected: expectedHost, actual: actualHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let cert = certificates.first else {
            lastFailure = .certificateUnavailable(host: expectedHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let policy = SecPolicyCreateSSL(true, expectedHost as CFString)
        SecTrustSetPolicies(serverTrust, policy)
        SecTrustSetAnchorCertificates(serverTrust, [cert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            lastFailure = .certificateValidationFailed(host: expectedHost)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let data = SecCertificateCopyData(cert) as Data
        let digest = SHA256.hash(data: data)
        retrievedFingerprint = digest.map { String(format: "%02x", $0) }.joined()
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

struct MGPreviewBridgeClient: MGBridgeClient, MGSpacesRepository, MGTasksRepository, MGWorkspaceRepository {
    func fetchConnectionStatus() async throws -> MGComputerStatus? { nil }
    func listSpaces() async throws -> [MGSpaceSummary] { MGPreviewFixtures.spaces }
    func listActivity() async throws -> [MGActivityBucket] { MGPreviewFixtures.activityBuckets }
    func listSchedules() async throws -> [MGScheduledTask] { MGPreviewFixtures.schedules }
    func availableModels() async throws -> [MGModelOption] { MGPreviewFixtures.models }
    func approvedRoots() async throws -> [MGRemoteFileNode] { MGPreviewFixtures.remoteRoots }
    func browseWorkspace(rootId: String, path: String) async throws -> [MGRemoteFileNode] { [] }
    func readWorkspaceFile(rootId: String, path: String) async throws -> MGRemoteFileContent { MGRemoteFileContent(path: path, content: "") }
    func listPlugins() async throws -> [MGPluginInfo] { [] }
    func importImage(rootId: String, path: String, fileName: String, data: Data) async throws -> String { path + "/" + fileName }
    func capabilityMatrix() async throws -> [MGBridgeCapability] { MGPreviewFixtures.capabilities }
    func preparePairingSession() async throws -> MGPairingQRCodePayload { MGPreviewFixtures.pairingPayload }
    
    func isPaired() -> Bool { false }
    func pairDevice(payload: MGPairingQRCodePayload, deviceName: String, fingerprint: String) async throws -> MGKeychainSession {
        return MGKeychainSession(address: "", deviceId: "", deviceSecret: "", computerName: "", bridgeFingerprint: "")
    }
    func createTask(spaceId: String, title: String, prompt: String, workspaceRoot: String, selectedModelId: String, clientRequestId: String) async throws -> MGChatSummary {
        return MGPreviewFixtures.spaces[0].chats[0]
    }
    func sendMessage(taskId: String, prompt: String, workspaceRoot: String, clientRequestId: String) async throws {}
    func createFolder(rootId: String, path: String, name: String) async throws {}
    func getTask(taskId: String) async throws -> MGChatSummary {
        return MGPreviewFixtures.spaces[0].chats[0]
    }
    func disconnect() {}

    func spaces() async throws -> [MGSpaceSummary] { MGPreviewFixtures.spaces }
    func models() async throws -> [MGModelOption] { MGPreviewFixtures.models }
    func roots() async throws -> [MGRemoteFileNode] { MGPreviewFixtures.remoteRoots }
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
    var spaces: [MGSpaceSummary] = []
    var activityBuckets: [MGActivityBucket] = []
    var schedules: [MGScheduledTask] = []
    var models: [MGModelOption] = []
    var remoteRoots: [MGRemoteFileNode] = []
    var capabilities: [MGBridgeCapability] = []
    #if DEBUG
    var trustedDevices: [MGTrustedDevice] = MGPreviewFixtures.trustedDevices
    var pairingPayload: MGPairingQRCodePayload = MGPreviewFixtures.pairingPayload
    #else
    var trustedDevices: [MGTrustedDevice] = []
    var pairingPayload: MGPairingQRCodePayload = MGPairingQRCodePayload(
        sessionId: "",
        address: "",
        token: nil,
        protocolVersion: nil,
        httpsHost: nil,
        httpsPort: nil,
        wssPort: nil,
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
    var isCreatingTask = false
    var sendingMessageTaskIDs: Set<String> = []
    var bridgeErrorMessage: String?
    var taskSuccessMessage: String?

    var expandedSpaceIDs: Set<String> = []

    var draftPrompt = ""
    var draftMicrophoneEnabled = false
    var draftContext = MGTaskContext(
        workingFolder: "",
        permissionMode: .askWhenNeeded,
        planMode: false,
        selectedModel: MGModelOption(
            id: "antigravity-fast",
            title: "Antigravity Fast",
            subtitle: "Provider: Antigravity. Model: Fast. Runtime: Antigravity Agent CLI.",
            providerID: "antigravity",
            providerName: "Antigravity",
            modelID: "flash",
            modelName: "Fast",
            runtimeID: "antigravity-agent-cli",
            runtimeName: "Antigravity Agent CLI",
            speedLabel: "Fast",
            effortLabel: "Balanced",
            capabilities: ["Chat", "Workspace context", "Task execution"],
            isRecommended: true,
            availability: .live
        ),
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
        connection = try? await bridge.fetchConnectionStatus()
        if connection != nil {
            bridgeErrorMessage = nil
            spaces = (try? await bridge.listSpaces()) ?? spaces
            activityBuckets = (try? await bridge.listActivity()) ?? activityBuckets
            schedules = (try? await bridge.listSchedules()) ?? schedules
            models = (try? await bridge.availableModels()) ?? fallbackAntigravityModels(availability: .unsupported)
            remoteRoots = (try? await bridge.approvedRoots()) ?? remoteRoots
            capabilities = (try? await bridge.capabilityMatrix()) ?? capabilities
            plugins = (try? await bridge.listPlugins()) ?? plugins

            if let firstRoot = remoteRoots.first {
                if draftContext.workingFolder.isEmpty {
                    draftContext.workingFolder = firstRoot.path
                }
                if openedWorkspaceRootID == nil {
                    openedWorkspaceRootID = firstRoot.id
                }
            }
            if let firstModel = models.first, draftContext.selectedModel.availability == .unsupported || !models.contains(draftContext.selectedModel) {
                draftContext.selectedModel = firstModel
            }
            if expandedSpaceIDs.isEmpty, let firstSpace = spaces.first {
                expandedSpaceIDs.insert(firstSpace.id)
            }
        } else {
            spaces = []
            activityBuckets = []
            schedules = []
            models = fallbackAntigravityModels(availability: .unsupported)
            remoteRoots = []
            capabilities = []
            plugins = []
        }
        do {
            #if DEBUG
            pairingPayload = try await bridge.preparePairingSession()
            #endif
        } catch {
            liveActivityDiagnostics = "Bridge bootstrap failed: \(error.localizedDescription)"
        }
    }

    private func fallbackAntigravityModels(availability: MGCapabilityState) -> [MGModelOption] {
        MGPreviewFixtures.models.map {
            MGModelOption(
                id: $0.id,
                title: $0.title,
                subtitle: availability == .live ? $0.subtitle : "Antigravity is unavailable until the desktop session is ready.",
                providerID: $0.providerID,
                providerName: $0.providerName,
                modelID: $0.modelID,
                modelName: $0.modelName,
                runtimeID: $0.runtimeID,
                runtimeName: $0.runtimeName,
                speedLabel: $0.speedLabel,
                effortLabel: $0.effortLabel,
                capabilities: $0.capabilities,
                isRecommended: $0.isRecommended,
                availability: availability
            )
        }
    }

    func connectPreviewComputer() {
        connection = MGPreviewFixtures.connectedComputer
        spaces = MGPreviewFixtures.spaces
        activityBuckets = MGPreviewFixtures.activityBuckets
        schedules = MGPreviewFixtures.schedules
        models = MGPreviewFixtures.models
        remoteRoots = MGPreviewFixtures.remoteRoots
        capabilities = MGPreviewFixtures.capabilities
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
        guard !isCreatingTask else {
            return nil
        }
        let cleanedPrompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else {
            bridgeErrorMessage = "Write a task prompt before sending."
            return nil
        }
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            bridgeErrorMessage = "Selected space is unavailable."
            return nil
        }
        isCreatingTask = true
        bridgeErrorMessage = nil

        let title = cleanedPrompt
            .split(separator: "\n")
            .first
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "New task"

        let prompt = cleanedPrompt
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
                    selectedModelId: draftContext.selectedModel.id,
                    clientRequestId: newChatID
                )
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isCreatingTask = false
                    self.taskSuccessMessage = "Task sent to Antigravity."
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
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isCreatingTask = false
                    self.bridgeErrorMessage = self.userFacingBridgeMessage(error)
                    if let idx = self.spaces[spaceIndex].chats.firstIndex(where: { $0.id == newChatID }) {
                        self.spaces[spaceIndex].chats[idx].isRunning = false
                        self.spaces[spaceIndex].chats[idx].thread.stateText = "Task failed"
                        self.spaces[spaceIndex].chats[idx].thread.stateTone = .critical
                        self.spaces[spaceIndex].chats[idx].thread.timeline.append(
                            MGActivityEvent(
                                id: UUID().uuidString,
                                title: "Task failed",
                                detail: self.userFacingBridgeMessage(error),
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
                let chatId = spaces[spaceIndex].chats[chatIndex].id
                let message = MGThreadMessage(
                    id: UUID().uuidString,
                    role: .user,
                    body: guidance,
                    timestamp: .now,
                    delivered: true,
                    attachments: []
                )
                spaces[spaceIndex].chats[chatIndex].thread.messages.append(message)
                spaces[spaceIndex].chats[chatIndex].thread.approval = nil
                spaces[spaceIndex].chats[chatIndex].lastActivity = Date()
                
                Task {
                    await sendMessage(chatID: chatId, prompt: guidance)
                }
                return
            }
        }
    }

    func sendMessage(chatID: String, prompt: String) async {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty, !sendingMessageTaskIDs.contains(chatID) else { return }

        sendingMessageTaskIDs.insert(chatID)
        bridgeErrorMessage = nil
        let requestId = UUID().uuidString
        updateChat(chatID) { chat in
            chat.isRunning = true
            chat.lastActivity = Date()
            chat.thread.messages.append(
                MGThreadMessage(
                    id: requestId,
                    role: .user,
                    body: cleanedPrompt,
                    timestamp: Date(),
                    delivered: true,
                    attachments: []
                )
            )
            chat.thread.timeline.append(
                MGActivityEvent(
                    id: UUID().uuidString,
                    title: "Sending message",
                    detail: "Forwarding your reply to Antigravity.",
                    duration: "Live",
                    tone: .neutral,
                    isComplete: false
                )
            )
            chat.thread.stateText = "Running task"
            chat.thread.stateTone = .neutral
        }

        do {
            try await bridge.sendMessage(
                taskId: chatID,
                prompt: cleanedPrompt,
                workspaceRoot: draftContext.workingFolder,
                clientRequestId: requestId
            )
            sendingMessageTaskIDs.remove(chatID)
            taskSuccessMessage = "Message sent."
            startTaskEventStreaming(taskId: chatID)
        } catch {
            sendingMessageTaskIDs.remove(chatID)
            let message = userFacingBridgeMessage(error)
            bridgeErrorMessage = message
            updateChat(chatID) { chat in
                chat.isRunning = false
                chat.thread.stateText = "Task failed"
                chat.thread.stateTone = .critical
                chat.thread.timeline.append(
                    MGActivityEvent(
                        id: UUID().uuidString,
                        title: "Message failed",
                        detail: message,
                        duration: "0s",
                        tone: .critical,
                        isComplete: true
                    )
                )
            }
        }
    }

    private func updateChat(_ chatID: String, mutate: (inout MGChatSummary) -> Void) {
        for spaceIndex in spaces.indices {
            if let chatIndex = spaces[spaceIndex].chats.firstIndex(where: { $0.id == chatID }) {
                mutate(&spaces[spaceIndex].chats[chatIndex])
                return
            }
        }
    }

    private func userFacingBridgeMessage(_ error: Error) -> String {
        if let trustError = error as? MGBridgeTrustError {
            return trustError.errorDescription ?? "Secure bridge verification failed."
        }

        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("not authenticated") {
            return "Antigravity is not authenticated on the desktop. Open Antigravity on Windows and try again."
        }
        if raw.localizedCaseInsensitiveContains("quota") || raw.localizedCaseInsensitiveContains("resource_exhausted") {
            return "The selected Antigravity route is temporarily limited. Try again later or choose another model."
        }
        if raw.localizedCaseInsensitiveContains("timed out") {
            return "The bridge did not respond in time. Check that the desktop bridge is still running."
        }
        return "The bridge could not complete the request. Check the desktop bridge logs for diagnostics."
    }

    func startTaskEventStreaming(taskId: String) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        
        guard let s = MGKeychainHelper.load() else { return }
        let wsAddress = s.address
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        
        guard let url = URL(string: "\(wsAddress)/v1/tasks/\(taskId)/events") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(s.deviceSecret)", forHTTPHeaderField: "Authorization")
        request.setValue(s.deviceId, forHTTPHeaderField: "x-mg-device-id")
        
        guard let host = URL(string: wsAddress.replacingOccurrences(of: "wss://", with: "https://"))?.host else { return }

        let delegate = MGTrustPinningDelegate(
            expectedHost: host,
            expectedFingerprint: s.bridgeFingerprint,
            mismatchReason: .reconnect
        )
        let urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let wsTask = urlSession.webSocketTask(with: request)
        self.webSocketTask = wsTask
        wsTask.resume()
        
        listenForWsEvents(wsTask, taskId: taskId)
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
                DispatchQueue.main.async { [weak self] in
                    self?.liveActivityDiagnostics = self?.userFacingBridgeMessage(error) ?? "Bridge stream disconnected."
                }
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
                            case "Planning changes", "Checking workspace", "Reading files", "Queued":
                                tone = .neutral
                            case "Updating styles", "Applying changes", "Running commands", "Running tests", "Running task":
                                tone = .good
                            case "Awaiting approval", "Paused":
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
                                isComplete: stage == "Task completed" || stage == "Task failed"
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

enum MGPreviewFixtures {
    static let models: [MGModelOption] = [
        MGModelOption(
            id: "antigravity-fast",
            title: "Antigravity Fast",
            subtitle: "Provider: Antigravity. Model: Fast. Runtime: Antigravity Agent CLI.",
            providerID: "antigravity",
            providerName: "Antigravity",
            modelID: "flash",
            modelName: "Fast",
            runtimeID: "antigravity-agent-cli",
            runtimeName: "Antigravity Agent CLI",
            speedLabel: "Fast",
            effortLabel: "Balanced",
            capabilities: ["Chat", "Workspace context", "Task execution"],
            isRecommended: true,
            availability: .live
        ),
        MGModelOption(
            id: "antigravity-pro",
            title: "Antigravity Pro",
            subtitle: "Provider: Antigravity. Model: Pro. Runtime: Antigravity Agent CLI.",
            providerID: "antigravity",
            providerName: "Antigravity",
            modelID: "pro",
            modelName: "Pro",
            runtimeID: "antigravity-agent-cli",
            runtimeName: "Antigravity Agent CLI",
            speedLabel: "Deliberate",
            effortLabel: "High",
            capabilities: ["Chat", "Workspace context", "Task execution"],
            isRecommended: false,
            availability: .live
        ),
        MGModelOption(
            id: "antigravity-lite",
            title: "Antigravity Lite",
            subtitle: "Provider: Antigravity. Model: Lite. Runtime: Antigravity Agent CLI.",
            providerID: "antigravity",
            providerName: "Antigravity",
            modelID: "flash_lite",
            modelName: "Lite",
            runtimeID: "antigravity-agent-cli",
            runtimeName: "Antigravity Agent CLI",
            speedLabel: "Ultra fast",
            effortLabel: "Low",
            capabilities: ["Chat", "Workspace context", "Task execution"],
            isRecommended: false,
            availability: .live
        )
    ]

    static let pairingPayload = MGPairingQRCodePayload(
        sessionId: "preview-session-12345678",
        address: "wss://192.168.1.18:59443",
        token: nil,
        protocolVersion: "1",
        httpsHost: "192.168.1.18",
        httpsPort: 59443,
        wssPort: 59443,
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
                    MGArtifactSummary(id: "a3", kind: .command, title: "npm run test", detail: "Passed Â· 2.3s")
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

