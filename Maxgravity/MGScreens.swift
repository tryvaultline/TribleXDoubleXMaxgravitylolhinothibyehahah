import SwiftUI
import PhotosUI
import UIKit

struct MGRootView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ZStack {
            MGAppBackground()
            if appModel.hasConnectedComputer {
                NavigationStack(path: Binding(get: { appModel.path }, set: { appModel.path = $0 })) {
                    MGMainShellView()
                        .navigationDestination(for: Route.self, destination: destinationView)
                }
            } else {
                MGFirstLaunchView()
            }
        }
        .task {
            await appModel.bootstrap()
        }
        .sheet(item: Binding(get: { appModel.presentedSheet }, set: { appModel.presentedSheet = $0 })) { destination in
            sheet(for: destination)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(.clear)
                .presentationDetents(sheetDetents(for: destination))
        }
        .fullScreenCover(item: Binding(get: { appModel.presentedFullScreen }, set: { appModel.presentedFullScreen = $0 })) { destination in
            fullScreen(for: destination)
        }
    }

    @ViewBuilder
    private func destinationView(_ route: Route) -> some View {
        switch route {
        case .chat(let chatID):
            MGChatThreadView(chatID: chatID)
        case .taskDetail(let chatID, let segment):
            MGTaskDetailView(chatID: chatID, initialSegment: segment)
        case .codeViewer(let fileRef):
            MGCodeViewerScreen(title: fileRef)
        case .diffViewer(let fileRef):
            MGDiffViewerScreen(title: fileRef)
        }
    }

    @ViewBuilder
    private func sheet(for destination: MGSheetDestination) -> some View {
        switch destination {
        case .connectionInfo:
            MGConnectionSheet()
        case .modelPicker:
            MGModelPicker()
        case .slashCommands:
            MGSlashCommandsSheet()
        case .fileMentions:
            MGFileMentionsSheet()
        case .photoLibrary:
            MGPhotoLibrarySheet()
        case .plugins:
            MGPluginsSheet()
        case .taskContext:
            MGTaskContextSheet()
        case .remoteFolderPicker:
            MGRemoteFolderPicker()
        case .approvalSteering(let requestID):
            MGApprovalSteeringSheet(requestID: requestID)
        case .scheduleTask:
            MGScheduleTaskSheet()
        case .pairingCode:
            MGPairingCodeSheet()
        }
    }

    @ViewBuilder
    private func fullScreen(for destination: MGFullScreenDestination) -> some View {
        switch destination {
        case .newTask(let spaceID):
            NavigationStack {
                MGNewTaskView(spaceID: spaceID)
            }
        case .plusMenu:
            MGPlusMenuOverlay()
        }
    }

    private func sheetDetents(for destination: MGSheetDestination) -> Set<PresentationDetent> {
        switch destination {
        case .connectionInfo, .approvalSteering:
            [.medium, .large]
        case .modelPicker, .slashCommands, .fileMentions, .photoLibrary, .plugins, .taskContext, .remoteFolderPicker, .scheduleTask, .pairingCode:
            [.large]
        }
    }
}

struct MGMainShellView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch appModel.selectedSection {
                case .spaces:
                    MGSpacesView()
                case .activity:
                    MGActivityScreenView()
                case .workspace:
                    MGWorkspaceScreenView()
                case .settings:
                    MGSettingsScreenView()
                }
            }

            MGAnimatedTabBar(
                selectedSection: appModel.selectedSection,
                unreadChats: runningChatCount,
                settingsBadge: 1,
                onSelect: appModel.selectSection
            )
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(MGAppBackground().ignoresSafeArea(edges: .bottom))
        }
        .navigationBarHidden(true)
    }

    private var runningChatCount: Int {
        appModel.spaces.reduce(into: 0) { total, space in
            total += space.chats.filter(\.isRunning).count
        }
    }
}

struct MGFirstLaunchView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 20) {
                MGBrandMark(size: 68)
                MGBrandWordmark()

                Text("Connect your computer to continue")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(MGTheme.primaryText)

                Text("Your computer must stay online for live tasks.")
                    .font(.body)
                    .foregroundStyle(MGTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MGTheme.primaryText)
                        .frame(width: 48, height: 48)
                        .mgInteractiveGlass(cornerRadius: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Local QR pairing")
                            .font(.headline)
                            .foregroundStyle(MGTheme.primaryText)
                        Text("Signed token, local address, desktop fingerprint, and expiry.")
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }
                .padding(16)
                .mgReadableSurface(cornerRadius: 28)
            }

            Spacer()

            VStack(spacing: 14) {
                MGPrimaryActionButton(title: "Scan QR code", icon: "qrcode.viewfinder") {
                    appModel.presentedSheet = .pairingCode
                    MGHaptics.selection()
                }

                Button("Enter pairing code") {
                    appModel.presentedSheet = .pairingCode
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .buttonStyle(MGPressableButtonStyle())
                .mgInteractiveGlass(cornerRadius: 22)
            }

            Text("Current status: QR payload, bridge trust, and one-time token rules are implemented in the bridge. Camera scanning, Keychain storage, and desktop confirmation remain partial.")
                .font(.footnote)
                .foregroundStyle(MGTheme.tertiaryText)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }
}

struct MGAnimatedTabBar: View {
    let selectedSection: MGAppSection
    let unreadChats: Int
    let settingsBadge: Int
    let onSelect: (MGAppSection) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MGAppSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        onSelect(section)
                    }
                    MGHaptics.selection()
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(selectedSection == section ? Color.white : MGTheme.secondaryText)

                            if badgeCount(for: section) > 0 {
                                Text("\(badgeCount(for: section))")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(MGTheme.danger))
                                    .offset(x: 12, y: -12)
                            }
                        }
                        .frame(height: 34)

                        Text(section.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedSection == section ? Color.white : MGTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 38, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .matchedGeometryEffect(id: "selected-tab", in: selectionNamespace)
                        }
                    }
                }
                .buttonStyle(MGPressableButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .mgInteractiveGlass(cornerRadius: 44)
    }

    private func badgeCount(for section: MGAppSection) -> Int {
        switch section {
        case .spaces: unreadChats
        case .settings: settingsBadge
        default: 0
        }
    }
}

struct MGSpacesView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MGNavigationHeader(
                    title: "Your Spaces",
                    subtitle: "Choose a space, jump into a chat, or start a new task."
                ) {
                    if let connection = appModel.connection {
                        MGConnectionPill(status: connection) {
                            appModel.presentedSheet = .connectionInfo
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 14) {
                    ForEach(appModel.spaces) { space in
                        MGSpaceRow(
                            space: space,
                            isExpanded: appModel.expandedSpaceIDs.contains(space.id),
                            onToggle: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    appModel.toggleSpace(space.id)
                                }
                            },
                            onOpenChat: { chat in
                                appModel.openChat(chat.id)
                            },
                            onNewTask: {
                                appModel.openNewTask(spaceID: space.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)

                MGPrimaryActionButton(title: "New task", icon: "plus") {
                    if let firstSpace = appModel.spaces.first {
                        appModel.openNewTask(spaceID: firstSpace.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
        .navigationBarHidden(true)
    }
}

struct MGNewTaskView: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let spaceID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topArea
                composer
                contextRow
                bridgeState
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background(MGAppBackground())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(MGSecondaryIconButtonStyle())
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var topArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(spaceTitle)
                .font(.headline)
                .foregroundStyle(MGTheme.secondaryText)

            Text("New task")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(MGTheme.primaryText)

            if let connection = appModel.connection {
                MGConnectionPill(status: connection) {
                    appModel.presentedSheet = .connectionInfo
                }
            }
        }
    }

    private var composer: some View {
        MGComposer(
            text: Binding(get: { appModel.draftPrompt }, set: { appModel.draftPrompt = $0 }),
            selectedModel: appModel.draftContext.selectedModel.title,
            modelOptions: appModel.models,
            mentionedFiles: appModel.draftContext.mentionedFiles,
            pickedPhotos: appModel.pickedPhotos,
            onRemoveFile: appModel.removeMentionedFile,
            onRemovePhoto: appModel.removePickedPhoto,
            onPlus: { appModel.presentedFullScreen = .plusMenu },
            onSlash: { appModel.presentedSheet = .slashCommands },
            onMention: { appModel.presentedSheet = .fileMentions },
            onSelectModel: appModel.updateDraftModel,
            onMicrophone: {
                appModel.draftMicrophoneEnabled.toggle()
                MGHaptics.selection()
            },
            onSend: {
                _ = appModel.createTask(in: spaceID)
            }
        )
    }

    private var contextRow: some View {
        Button {
            appModel.presentedSheet = .taskContext
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task context")
                        .font(.headline)
                        .foregroundStyle(MGTheme.primaryText)
                    Text("\(appModel.draftContext.workingFolder) · \(appModel.draftContext.permissionMode.title) · \(appModel.draftContext.planMode ? "Plan mode on" : "Plan mode off")")
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .padding(16)
        }
        .buttonStyle(MGPressableButtonStyle())
        .mgInteractiveGlass(cornerRadius: 24)
    }

    private var bridgeState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bridge capability status")
                .font(.headline)
                .foregroundStyle(MGTheme.primaryText)
            ForEach(appModel.capabilities.prefix(3)) { capability in
                HStack {
                    Text(capability.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MGTheme.primaryText)
                    Spacer()
                    MGStatusPill(title: capability.state.title, tone: capability.state.tone)
                }
                Text(capability.detail)
                    .font(.caption)
                    .foregroundStyle(MGTheme.secondaryText)
            }
        }
        .padding(16)
        .mgReadableSurface(cornerRadius: 26)
    }

    private var spaceTitle: String {
        appModel.space(with: spaceID)?.name ?? "Space"
    }
}

struct MGChatThreadView: View {
    @Environment(MGAppModel.self) private var appModel
    let chatID: String

    var body: some View {
        ScrollView {
            if let chat = appModel.chat(with: chatID) {
                VStack(alignment: .leading, spacing: 18) {
                    stateHeader(chat)
                    ForEach(chat.thread.messages) { message in
                        messageBlock(message, thread: chat.thread)
                    }
                    if let approval = chat.thread.approval {
                        MGApprovalPanel(
                            request: approval,
                            onApprove: { MGHaptics.success() },
                            onReject: { MGHaptics.warning() },
                            onSteer: { appModel.presentedSheet = .approvalSteering(requestID: approval.id) }
                        )
                    }
                    if let completion = chat.thread.completion {
                        MGCompletionEmbed(summary: completion)
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            } else {
                Text("Chat not found")
                    .foregroundStyle(MGTheme.secondaryText)
            }
        }
        .background(MGAppBackground())
        .navigationTitle(appModel.chat(with: chatID)?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Pin chat") {}
                    Button("Rename chat") {}
                    Button("View files") { appModel.path.append(.taskDetail(chatID: chatID, segment: .files)) }
                    Button("View commands") { appModel.path.append(.taskDetail(chatID: chatID, segment: .commands)) }
                    Button("View activity") { appModel.path.append(.taskDetail(chatID: chatID, segment: .changes)) }
                    Button("Delete local chat history", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func stateHeader(_ chat: MGChatSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MGBrandMark(size: 22)
                Text(chat.thread.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MGTheme.primaryText)
                MGStatusPill(title: chat.thread.stateText, tone: chat.thread.stateTone)
            }
            MGAgentActivityTimeline(stateText: chat.thread.stateText, events: chat.thread.timeline)
        }
    }

    @ViewBuilder
    private func messageBlock(_ message: MGThreadMessage, thread: MGTaskThread) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(MGTheme.primaryText)
                    HStack {
                        Text(DateFormatter.mgTime.string(from: message.timestamp))
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                        if message.delivered {
                            Text("Delivered")
                                .font(.caption)
                                .foregroundStyle(MGTheme.tertiaryText)
                        }
                    }
                    if !message.attachments.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(message.attachments) { artifact in
                                MGArtifactRow(artifact: artifact) {
                                    openArtifact(artifact, chatID: thread.id)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .mgReadableSurface(cornerRadius: 24)
                .frame(maxWidth: 320, alignment: .trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    MGGoogleAvatar(size: 20)
                    Text("Antigravity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(MGTheme.primaryText)
                if !message.attachments.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(message.attachments) { artifact in
                            MGArtifactRow(artifact: artifact) {
                                openArtifact(artifact, chatID: thread.id)
                            }
                        }
                    }
                }
                Text(DateFormatter.mgTime.string(from: message.timestamp))
                    .font(.caption)
                    .foregroundStyle(MGTheme.tertiaryText)
            }
            .padding(.horizontal, 2)
        }
    }

    private func openArtifact(_ artifact: MGArtifactSummary, chatID: String) {
        switch artifact.kind {
        case .file:
            appModel.path.append(.codeViewer(fileRef: artifact.title))
        case .diff:
            appModel.path.append(.diffViewer(fileRef: artifact.title))
        case .command:
            appModel.path.append(.taskDetail(chatID: chatID, segment: .commands))
        case .approval:
            if let approval = appModel.chat(with: chatID)?.thread.approval {
                appModel.presentedSheet = .approvalSteering(requestID: approval.id)
            }
        case .completion:
            appModel.path.append(.taskDetail(chatID: chatID, segment: .changes))
        case .screenshot:
            appModel.path.append(.taskDetail(chatID: chatID, segment: .files))
        }
    }
}

struct MGTaskDetailView: View {
    @Environment(MGAppModel.self) private var appModel
    let chatID: String
    @State var initialSegment: MGTaskDetailSegment

    var body: some View {
        ScrollView {
            if let chat = appModel.chat(with: chatID) {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Task Detail", selection: $initialSegment) {
                        ForEach(MGTaskDetailSegment.allCases) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch initialSegment {
                    case .files:
                        VStack(spacing: 10) {
                            ForEach(chat.thread.files, id: \.self) { file in
                                Button {
                                    appModel.path.append(.codeViewer(fileRef: file))
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text")
                                        Text(file)
                                            .foregroundStyle(MGTheme.primaryText)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .padding(12)
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(MGPressableButtonStyle())
                                .mgReadableSurface(cornerRadius: 18)
                            }
                        }
                    case .changes:
                        VStack(spacing: 10) {
                            ForEach(chat.thread.diffs, id: \.fileName) { diff in
                                Button {
                                    appModel.path.append(.diffViewer(fileRef: diff.fileName))
                                } label: {
                                    MGDiffSummary(diff: diff)
                                }
                                .buttonStyle(MGPressableButtonStyle())
                            }
                        }
                    case .commands:
                        VStack(spacing: 12) {
                            ForEach(chat.thread.commands) { command in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(command.command)
                                            .font(.callout.monospaced())
                                            .foregroundStyle(MGTheme.primaryText)
                                        Spacer()
                                        Text("\(command.result) · \(command.duration)")
                                            .font(.caption)
                                            .foregroundStyle(command.result == "Passed" ? MGTheme.success : MGTheme.warning)
                                    }
                                    Text(command.output)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(MGTheme.secondaryText)
                                        .textSelection(.enabled)
                                }
                                .padding(14)
                                .mgReadableSurface(cornerRadius: 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .background(MGAppBackground())
        .navigationTitle("Task detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MGCodeViewerScreen: View {
    @Environment(MGAppModel.self) private var appModel
    let title: String

    var body: some View {
        ScrollView {
            Text(sampleCode)
                .font(.callout.monospaced())
                .foregroundStyle(MGTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .mgReadableSurface(cornerRadius: 26)
                .padding(20)
        }
        .background(MGAppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sampleCode: String {
        appModel.workspaceFileContents[title] ?? "No live file content loaded for this path yet."
    }
}

struct MGDiffViewerScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                diffLine("+    .padding(.horizontal, 16)", color: MGTheme.success)
                diffLine("-    .padding(.horizontal, 12)", color: MGTheme.danger)
                diffLine("~    .frame(minHeight: 44)", color: MGTheme.warning)
            }
            .padding(18)
            .mgReadableSurface(cornerRadius: 26)
            .padding(20)
        }
        .background(MGAppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diffLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MGPanelShell<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(MGAppBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGActivityScreenView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        MGPanelShell(title: "Activity") {
            ForEach(appModel.activityBuckets) { bucket in
                MGSettingsGroup(title: bucket.title) {
                    VStack(spacing: 0) {
                        ForEach(bucket.items) { item in
                            Button {
                                if let route = item.route {
                                    appModel.path.append(route)
                                } else if bucket.id == "scheduled" {
                                    appModel.presentedSheet = .scheduleTask
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(color(for: item.tone))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(MGTheme.primaryText)
                                        Text(item.detail)
                                            .font(.caption)
                                            .foregroundStyle(MGTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(MGTheme.secondaryText)
                                }
                                .frame(minHeight: 44)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(MGPressableButtonStyle())
                            if item.id != bucket.items.last?.id {
                                Divider().overlay(MGTheme.border)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for tone: MGActivityTone) -> Color {
        switch tone {
        case .neutral: MGTheme.secondaryText
        case .good: MGTheme.success
        case .warning: MGTheme.warning
        case .critical: MGTheme.danger
        }
    }
}

struct MGSettingsScreenView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        MGPanelShell(title: "Settings") {
            MGSettingsGroup(title: "Connected computer") {
                VStack(spacing: 0) {
                    settingsRow("desktopcomputer", "Computer", appModel.connection?.computerName ?? "Not connected")
                    divider
                    settingsRow("waveform.path.ecg", "Connection health", appModel.connection?.quality.title ?? "Unavailable")
                    divider
                    settingsButtonRow("qrcode", "Link another computer") { appModel.presentedSheet = .pairingCode }
                    divider
                    settingsButtonRow("xmark.circle", "Disconnect this computer", destructive: true) { appModel.disconnectCurrentComputer() }
                }
            }

            MGSettingsGroup(title: "Defaults") {
                VStack(spacing: 0) {
                    settingsRow("sparkles.rectangle.stack", "Default model", appModel.draftContext.selectedModel.title)
                    divider
                    settingsRow("lock.shield", "Default permission mode", appModel.draftContext.permissionMode.title)
                    divider
                    settingsRow("drop", "Appearance", "System / Dark / High contrast")
                }
            }

            MGSettingsGroup(title: "Antigravity account") {
                HStack(spacing: 14) {
                    MGGoogleAvatar(size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google account")
                            .foregroundStyle(MGTheme.primaryText)
                        Text("Connected through the local Antigravity desktop session")
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                    Spacer()
                }
                .frame(minHeight: 44)
                .padding(.vertical, 10)
            }

            MGSettingsGroup(title: "Diagnostics") {
                VStack(spacing: 0) {
                    settingsRow("bell.badge", "Notifications", appModel.notificationsAuthorized ? "Authorized" : "Not requested")
                    divider
                    settingsRow("rectangle.badge.clock", "Live Activity", appModel.liveActivityDiagnostics)
                    divider
                    settingsRow("person.2", "Trusted devices", "\(appModel.trustedDevices.count)")
                }
            }
        }
    }

    private var divider: some View {
        Divider().overlay(MGTheme.border)
    }

    private func settingsRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(MGTheme.secondaryText)
            Text(title)
                .foregroundStyle(MGTheme.primaryText)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(MGTheme.secondaryText)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 10)
    }

    private func settingsButtonRow(_ symbol: String, _ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
        }
        .foregroundStyle(destructive ? MGTheme.danger : MGTheme.primaryText)
        .frame(minHeight: 44)
        .padding(.vertical, 10)
        .buttonStyle(MGPressableButtonStyle(foreground: destructive ? MGTheme.danger : MGTheme.primaryText))
    }
}

struct MGWorkspaceScreenView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        MGPanelShell(title: "Workspace") {
            if appModel.remoteRoots.isEmpty {
                Text("No approved workspace roots are available yet.")
                    .font(.subheadline)
                    .foregroundStyle(MGTheme.secondaryText)
                    .padding(.top, 12)
            }

            ForEach(appModel.remoteRoots) { root in
                MGSettingsGroup(title: root.name) {
                    VStack(spacing: 0) {
                        Button {
                            Task {
                                await appModel.loadWorkspaceRoot(root)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.gearshape")
                                    .foregroundStyle(MGTheme.primaryText)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(root.path)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(MGTheme.primaryText)
                                        .multilineTextAlignment(.leading)
                                    Text(appModel.workspaceLoadingRoots.contains(root.id) ? "Loading live files..." : "Tap to refresh live contents from the paired computer")
                                        .font(.caption)
                                        .foregroundStyle(MGTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(MGTheme.secondaryText)
                            }
                            .frame(minHeight: 44)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(MGPressableButtonStyle())

                        if let nodes = appModel.workspaceNodesByRoot[root.id], !nodes.isEmpty {
                            Divider().overlay(MGTheme.border)
                            ForEach(nodes) { node in
                                Button {
                                    if !node.isDirectory {
                                        Task {
                                            await appModel.openWorkspaceFile(rootId: root.id, path: node.path)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                                            .foregroundStyle(node.isDirectory ? MGTheme.warning : MGTheme.primaryText)
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(node.name)
                                                .foregroundStyle(MGTheme.primaryText)
                                            Text(node.path)
                                                .font(.caption)
                                                .foregroundStyle(MGTheme.secondaryText)
                                        }
                                        Spacer()
                                        Image(systemName: node.isDirectory ? "folder" : "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(MGTheme.secondaryText)
                                    }
                                    .frame(minHeight: 44)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(MGPressableButtonStyle())
                                if node.id != nodes.last?.id {
                                    Divider().overlay(MGTheme.border)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if let root = appModel.remoteRoots.first, appModel.workspaceNodesByRoot[root.id] == nil {
                await appModel.loadWorkspaceRoot(root)
            }
        }
    }
}

struct MGConnectionSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let connection = appModel.connection {
                    Section {
                        labeledRow("Computer name", value: connection.computerName)
                        labeledRow("Connection quality", value: connection.quality.title)
                        labeledRow("Last sync", value: DateFormatter.mgTime.string(from: connection.lastSync))
                        labeledRow("Transport", value: connection.encryption)
                    }
                    Section("Capability state") {
                        labeledRow("Pairing", value: connection.pairing.title)
                        labeledRow("Live bridge", value: connection.liveBridge.title)
                    }
                    Section {
                        Button("Link another computer") {
                            appModel.presentedSheet = .pairingCode
                        }
                        Button("Disconnect this computer", role: .destructive) {
                            appModel.disconnectCurrentComputer()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func labeledRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(MGTheme.secondaryText)
        }
    }
}

struct MGPlusMenuOverlay: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private let primaryRows: [(String, String)] = [
        ("photo.on.rectangle.angled", "Photos"),
        ("doc.fill", "Files"),
        ("puzzlepiece.extension.fill", "Plugins")
    ]

    private let secondaryRows: [(String, String)] = [
        ("at", "Mention workspace file"),
        ("list.bullet.clipboard", "Plan mode"),
        ("folder", "Choose working folder"),
        ("lock.shield", "Permissions")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(primaryRows, id: \.1) { row in
                        Button {
                            if row.1 == "Files" {
                                appModel.presentedSheet = .remoteFolderPicker
                            } else if row.1 == "Photos" {
                                appModel.presentedSheet = .photoLibrary
                            } else if row.1 == "Plugins" {
                                appModel.presentedSheet = .plugins
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: row.0)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(MGTheme.primaryText)
                                    .frame(width: 54, height: 54)
                                    .mgInteractiveGlass(cornerRadius: 20)
                                Text(row.1)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(MGTheme.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(MGPressableButtonStyle())
                    }

                    Divider().overlay(MGTheme.border)
                        .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(secondaryRows, id: \.1) { row in
                            Button {
                                switch row.1 {
                                case "Mention workspace file":
                                    appModel.presentedSheet = .fileMentions
                                case "Plan mode":
                                    appModel.draftContext.planMode.toggle()
                                case "Choose working folder":
                                    appModel.presentedSheet = .remoteFolderPicker
                                case "Permissions":
                                    appModel.presentedSheet = .taskContext
                                default:
                                    break
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: row.0)
                                        .frame(width: 20)
                                    Text(row.1)
                                    Spacer()
                                }
                                .font(.body.weight(.medium))
                                .foregroundStyle(MGTheme.primaryText)
                            }
                            .buttonStyle(MGPressableButtonStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }
                .padding(.top, 22)
                .padding(.bottom, 18)
                .mgInteractiveGlass(cornerRadius: 32)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
    }
}

struct MGSlashCommandsSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let commands = ["/plan", "/review", "/test", "/summarize", "/schedule", "/explain"]

    var body: some View {
        NavigationStack {
            List(commands, id: \.self) { command in
                Button {
                    if appModel.draftPrompt.isEmpty {
                        appModel.draftPrompt = "\(command) "
                    } else {
                        appModel.draftPrompt += "\n\(command) "
                    }
                    dismiss()
                } label: {
                    Text(command)
                        .font(.body.monospaced().weight(.medium))
                        .foregroundStyle(MGTheme.primaryText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Slash commands")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGPhotoLibrarySheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.stack.fill")
                        Text("Pick images from Photos")
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(MGTheme.primaryText)
                    .padding(16)
                    .mgInteractiveGlass(cornerRadius: 24)
                }

                if appModel.pickedPhotos.isEmpty {
                    Text("No photos selected yet.")
                        .font(.subheadline)
                        .foregroundStyle(MGTheme.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(appModel.pickedPhotos) { photo in
                                if let image = UIImage(data: photo.data) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 92, height: 92)
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        Button {
                                            appModel.removePickedPhoto(photo.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white)
                                        }
                                        .offset(x: 6, y: -6)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(MGAppBackground())
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: selectedItems) {
            for item in selectedItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    appModel.addPickedPhoto(data: data)
                }
            }
            if !selectedItems.isEmpty {
                selectedItems = []
            }
        }
    }
}

struct MGPluginsSheet: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            List(appModel.plugins) { plugin in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plugin.name)
                            .foregroundStyle(MGTheme.primaryText)
                        if let kind = plugin.kind {
                            Text(kind.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MGTheme.secondaryText)
                        }
                    }
                    if let detail = plugin.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                    if let command = plugin.command, !command.isEmpty {
                        Text(command)
                            .font(.caption.monospaced())
                            .foregroundStyle(MGTheme.tertiaryText)
                    }
                    Text(plugin.path)
                        .font(.caption2)
                        .foregroundStyle(MGTheme.tertiaryText)
                }
                .frame(minHeight: 44, alignment: .leading)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Bridge tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGFileMentionsSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filteredFiles, id: \.self) { file in
                Button {
                    appModel.addMentionedFile(file)
                    dismiss()
                } label: {
                    Text(file)
                        .font(.body.monospaced())
                        .foregroundStyle(MGTheme.primaryText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .searchable(text: $query, prompt: "Search approved workspace files")
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Mention file")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var filteredFiles: [String] {
        let files = appModel.mentionableFiles.map { "@\($0)" }
        if query.isEmpty {
            return files
        }
        return files.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct MGApprovalSteeringSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let requestID: String
    @State private var guidance = "Tell Maxgravity what to change before continuing…"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Steer the task")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                Text("Redirect the agent without leaving the thread.")
                    .font(.subheadline)
                    .foregroundStyle(MGTheme.secondaryText)
                TextEditor(text: $guidance)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(12)
                    .mgReadableSurface(cornerRadius: 20)
                MGPrimaryActionButton(title: "Send steering") {
                    appModel.steerApproval(requestID: requestID, guidance: guidance)
                    dismiss()
                }
                Spacer()
            }
            .padding(20)
            .background(MGAppBackground())
            .navigationTitle("Steer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGScheduleTaskSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var taskTitle = "Run nightly tests"
    @State private var selectedSpace = "Maxgravity App"
    @State private var selectedModel = "Auto"
    @State private var selectedPermission = MGPermissionMode.sandbox
    @State private var scheduledDate = Date().addingTimeInterval(36_000)
    @State private var repetition = "Every night"
    @State private var notificationsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $taskTitle)
                    TextField("Selected Space", text: $selectedSpace)
                    TextField("Working folder", text: .constant(appModel.draftContext.workingFolder))
                    TextField("Agent / model", text: $selectedModel)
                }

                Section("Timing") {
                    DatePicker("Date and time", selection: $scheduledDate)
                    TextField("Repetition", text: $repetition)
                    Toggle("Notifications", isOn: $notificationsEnabled)
                        .tint(.white)
                }

                Section("Permissions") {
                    Picker("Permission mode", selection: $selectedPermission) {
                        ForEach(MGPermissionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("Scheduled") {
                    ForEach(appModel.schedules) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                            Text("\(DateFormatter.mgSchedule.string(from: item.nextRun)) - \(item.frequency) - \(item.spaceName)")
                                .font(.caption)
                                .foregroundStyle(MGTheme.secondaryText)
                            Text(item.isEnabled ? "Enabled" : "Paused")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.isEnabled ? MGTheme.success : MGTheme.warning)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Schedule task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { dismiss() }
                }
            }
        }
    }
}

struct MGPairingCodeSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    enum ScreenState {
        case scanner
        case manualEntry
        case confirmation(payload: MGPairingQRCodePayload)
        case loading(message: String)
        case waitingForApproval
        case success
        case error(PairingIssue)
    }

    enum RetryAction {
        case scanner
        case manualLookup
        case performPairing(MGPairingQRCodePayload)
    }

    struct PairingIssue: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let diagnosticCode: String?
        let host: String?
        let certificateSuffix: String?
    }

    @State private var state: ScreenState = .scanner
    @State private var ipAddress = ""
    @State private var pairingToken = ""
    @State private var retryAction: RetryAction = .scanner
    @State private var isRetrying = false
    @State private var connectionDetailsExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                MGAppBackground()

                ScrollView(showsIndicators: false) {
                    MGDarkGlassSheet {
                        VStack(alignment: .leading, spacing: 18) {
                            switch state {
                            case .scanner:
                                scannerView
                            case .manualEntry:
                                manualEntryView
                            case .confirmation(let payload):
                                confirmationView(payload)
                            case .loading(let message):
                                loadingView(message)
                            case .waitingForApproval:
                                waitingForApprovalView
                            case .success:
                                successView
                            case .error(let issue):
                                errorView(issue)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Pairing Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(MGTheme.secondaryText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if case .manualEntry = state {
                        Button("Scan QR") {
                            retryAction = .scanner
                            state = .scanner
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MGTheme.primaryText)
                    } else if case .scanner = state {
                        Button("Enter Code") {
                            state = .manualEntry
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MGTheme.primaryText)
                    }
                }
            }
        }
    }

    private var scannerView: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader("Scan the desktop QR", detail: "Use the current pairing screen from your Windows bridge. Pairing stays on your local network and pins the bridge identity.")

            MGDarkGlassCard(cornerRadius: 30) {
                MGCameraScannerView { scannedCode in
                    MGHaptics.selection()

                    if let payload = decodePairingPayload(from: scannedCode) {
                        retryAction = .performPairing(payload)
                        state = .confirmation(payload: payload)
                    } else {
                        state = .error(issue(code: "INVALID_QR", host: nil, suffix: nil))
                        retryAction = .scanner
                    }
                } onError: { errMsg in
                    state = .error(
                        PairingIssue(
                            title: "Secure connection failed",
                            body: "Maxgravity could not verify this bridge’s identity. Check that the QR code is current and try pairing again.",
                            diagnosticCode: "CAMERA_\(errMsg.replacingOccurrences(of: " ", with: "_").uppercased())",
                            host: nil,
                            certificateSuffix: nil
                        )
                    )
                    retryAction = .scanner
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var manualEntryView: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader("Enter pairing details", detail: "Manual pairing still verifies the same pinned bridge identity. The code does not bypass TLS or fingerprint checks.")

            MGDarkGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    entryField(title: "Bridge IP", placeholder: "192.168.1.18", text: $ipAddress, autocapitalization: .never, keyboardType: .numbersAndPunctuation)
                    entryField(title: "Pairing code", placeholder: "Shown on your desktop", text: $pairingToken, autocapitalization: .characters, keyboardType: .asciiCapable)
                }
            }

            MGPrimaryActionButton(title: "Verify bridge", icon: "lock.shield.fill", isLoading: isRetrying, isDisabled: isRetrying) {
                Task { await fetchManualSession() }
            }
        }
    }

    private func fetchManualSession() async {
        isRetrying = true
        defer { isRetrying = false }

        state = .loading(message: "Checking the bridge certificate…")
        retryAction = .manualLookup
        connectionDetailsExpanded = false

        let cleanedIp = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedIp.isEmpty, !normalizedToken.isEmpty else {
            state = .error(
                PairingIssue(
                    title: "Secure connection failed",
                    body: "Maxgravity could not verify this bridge’s identity. Check that the QR code is current and try pairing again.",
                    diagnosticCode: "MANUAL_INPUT_REQUIRED",
                    host: cleanedIp.isEmpty ? nil : cleanedIp,
                    certificateSuffix: nil
                )
            )
            return
        }

        let targetUrlStr = "https://\(cleanedIp):59443/v1/connection/active-session"
        guard let url = URL(string: targetUrlStr) else {
            state = .error(issue(code: "INVALID_HOST", host: cleanedIp, suffix: nil))
            return
        }

        do {
            let delegate = MGManualPairingTrustDelegate(expectedHost: cleanedIp)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (data, response) = try await session.data(for: URLRequest(url: url))

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                state = .error(issue(code: "BRIDGE_NOT_FOUND", host: cleanedIp, suffix: nil))
                return
            }

            let meta = try JSONDecoder.mgDecoder.decode(MGPairingQRCodePayload.self, from: data)
            let retrievedFingerprint = delegate.retrievedFingerprint?.lowercased()
            let expectedFingerprint = meta.bridgeFingerprint.replacingOccurrences(of: ":", with: "").lowercased()

            guard retrievedFingerprint == expectedFingerprint else {
                state = .error(issue(code: "PIN_MISMATCH", host: cleanedIp, suffix: String(expectedFingerprint.suffix(8)).uppercased()))
                return
            }

            let payload = MGPairingQRCodePayload(
                sessionId: meta.sessionId,
                address: meta.address,
                token: normalizedToken,
                protocolVersion: meta.protocolVersion,
                httpsHost: meta.httpsHost ?? cleanedIp,
                httpsPort: meta.httpsPort,
                wssPort: meta.wssPort,
                bridgeFingerprint: meta.bridgeFingerprint,
                expiresAt: meta.expiresAt,
                bridgeVersion: meta.bridgeVersion
            )

            retryAction = .performPairing(payload)
            state = .confirmation(payload: payload)
        } catch let trustError as MGBridgeTrustError {
            state = .error(issue(from: trustError))
        } catch {
            state = .error(issue(code: "MANUAL_LOOKUP_FAILED", host: cleanedIp, suffix: nil))
        }
    }

    private func decodePairingPayload(from scannedCode: String) -> MGPairingQRCodePayload? {
        let trimmed = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder.mgDecoder.decode(MGPairingQRCodePayload.self, from: data) {
            return payload
        }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let payloadItem = components.queryItems?.first(where: { $0.name == "payload" })?.value,
               let decoded = decodePayloadString(payloadItem) {
                return decoded
            }

            if let jsonItem = components.queryItems?.first(where: { $0.name == "json" })?.value,
               let decoded = decodePayloadString(jsonItem) {
                return decoded
            }
        }

        return nil
    }

    private func decodePayloadString(_ value: String) -> MGPairingQRCodePayload? {
        let candidates = [value, value.removingPercentEncoding ?? value]

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let payload = try? JSONDecoder.mgDecoder.decode(MGPairingQRCodePayload.self, from: data) {
                return payload
            }

            if let data = Data(base64Encoded: candidate),
               let payload = try? JSONDecoder.mgDecoder.decode(MGPairingQRCodePayload.self, from: data) {
                return payload
            }
        }

        return nil
    }

    private func confirmationView(_ payload: MGPairingQRCodePayload) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader("Confirm this bridge", detail: "The app will trust only this host and this certificate pin. Any certificate change requires a fresh pairing approval.")

            MGDarkGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    labeledField("Bridge host", value: payload.httpsHost ?? URL(string: payload.address)?.host ?? payload.address)
                    Divider().overlay(MGTheme.border)
                    labeledField("Certificate suffix", value: "…" + payload.bridgeFingerprint.replacingOccurrences(of: ":", with: "").suffix(8).uppercased())
                    Divider().overlay(MGTheme.border)
                    labeledField("Protocol", value: payload.protocolVersion ?? payload.bridgeVersion)
                }
            }

            HStack(spacing: 12) {
                MGPrimaryActionButton(title: "Trust this bridge", icon: "lock.fill", isLoading: isRetrying, isDisabled: isRetrying) {
                    Task { await performPairing(payload) }
                }

                Button("Back") {
                    state = payload.token == nil ? .scanner : .manualEntry
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
                .frame(minWidth: 72, minHeight: 56)
                .buttonStyle(MGPressableButtonStyle())
                .mgInteractiveGlass(cornerRadius: 22)
            }
        }
    }

    private func performPairing(_ payload: MGPairingQRCodePayload) async {
        isRetrying = true
        defer { isRetrying = false }

        state = .waitingForApproval
        retryAction = .performPairing(payload)
        connectionDetailsExpanded = false

        do {
            try await appModel.pair(payload: payload, name: UIDevice.current.name)
            appModel.selectedSection = .spaces
            state = .success
            MGHaptics.success()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                dismiss()
            }
        } catch let trustError as MGBridgeTrustError {
            MGHaptics.warning()
            state = .error(issue(from: trustError))
        } catch {
            MGHaptics.warning()
            state = .error(issue(code: "PAIRING_FAILED", host: payload.httpsHost ?? URL(string: payload.address)?.host, suffix: String(payload.bridgeFingerprint.replacingOccurrences(of: ":", with: "").suffix(8)).uppercased()))
        }
    }

    private func retryCurrentAction() {
        guard !isRetrying else { return }

        switch retryAction {
        case .scanner:
            state = .scanner
        case .manualLookup:
            Task { await fetchManualSession() }
        case .performPairing(let payload):
            Task { await performPairing(payload) }
        }
    }

    private func sheetHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(MGTheme.primaryText)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(MGTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func entryField(title: String, placeholder: String, text: Binding<String>, autocapitalization: TextInputAutocapitalization, keyboardType: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MGTheme.secondaryText)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .foregroundStyle(MGTheme.primaryText)
        }
    }

    private func labeledField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MGTheme.secondaryText)
            Text(value)
                .font(.subheadline.monospaced())
                .foregroundStyle(MGTheme.primaryText)
        }
    }

    private func loadingView(_ message: String) -> some View {
        MGDarkGlassCard(cornerRadius: 28) {
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.1)
                Text(message)
                    .font(.body)
                    .foregroundStyle(MGTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var waitingForApprovalView: some View {
        MGDarkGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                MGStatusPill(title: "Waiting for desktop approval", tone: .warning)
                Text("Approve this iPhone from your Windows pairing page to finish linking it.")
                    .font(.body)
                    .foregroundStyle(MGTheme.primaryText)
                Text("The secure connection is established. Maxgravity is waiting for a local approval response from the bridge.")
                    .font(.caption)
                    .foregroundStyle(MGTheme.secondaryText)
            }
        }
    }

    private var successView: some View {
        MGDarkGlassCard(cornerRadius: 28) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(MGTheme.success)
                Text("Pairing complete")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                Text("The bridge is approved and Spaces is ready.")
                    .font(.subheadline)
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func errorView(_ issue: PairingIssue) -> some View {
        MGDarkGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                MGGlassIconWell(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MGTheme.primaryText)
                    Text(issue.body)
                        .font(.subheadline)
                        .foregroundStyle(MGTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if issue.diagnosticCode != nil || issue.host != nil || issue.certificateSuffix != nil {
                    DisclosureGroup("Connection details", isExpanded: $connectionDetailsExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let code = issue.diagnosticCode {
                                labeledField("Code", value: code)
                            }
                            if let host = issue.host {
                                labeledField("Host", value: host)
                            }
                            if let suffix = issue.certificateSuffix {
                                labeledField("Certificate", value: suffix)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
                }

                MGPrimaryActionButton(title: isRetrying ? "Retrying…" : "Try pairing again", isLoading: isRetrying, isDisabled: isRetrying) {
                    retryCurrentAction()
                }
            }
        }
    }

    private func issue(from trustError: MGBridgeTrustError) -> PairingIssue {
        let title: String
        let body: String

        switch trustError {
        case .identityChanged:
            title = "Bridge identity changed"
            body = "This bridge presents a different certificate than the one previously approved. Pair it again from a current QR code."
        default:
            title = "Secure connection failed"
            body = "Maxgravity could not verify this bridge’s identity. Check that the QR code is current and try pairing again."
        }

        return PairingIssue(
            title: title,
            body: body,
            diagnosticCode: trustError.diagnosticCode,
            host: trustError.host,
            certificateSuffix: trustError.certificateSuffix
        )
    }

    private func issue(code: String, host: String?, suffix: String?) -> PairingIssue {
        PairingIssue(
            title: "Secure connection failed",
            body: "Maxgravity could not verify this bridge’s identity. Check that the QR code is current and try pairing again.",
            diagnosticCode: code,
            host: host,
            certificateSuffix: suffix
        )
    }
}

#Preview("First Launch") {
    MGFirstLaunchView()
        .environment(MGAppModel())
        .preferredColorScheme(.dark)
}

#Preview("Spaces") {
    let model = MGAppModel()
    model.connectMockComputer()
    return MGSpacesView()
        .environment(model)
        .preferredColorScheme(.dark)
}

#Preview("New Task") {
    let model = MGAppModel()
    model.connectMockComputer()
    return NavigationStack {
        MGNewTaskView(spaceID: MGFixtures.spaces[0].id)
            .environment(model)
    }
    .preferredColorScheme(.dark)
}

#Preview("Chat") {
    let model = MGAppModel()
    model.connectMockComputer()
    return NavigationStack {
        MGChatThreadView(chatID: MGFixtures.thread.id)
            .environment(model)
    }
    .preferredColorScheme(.dark)
}
