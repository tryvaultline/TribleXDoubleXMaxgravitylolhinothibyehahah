import SwiftUI

struct MGRootView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ZStack {
            MGAppBackground()
            if appModel.hasConnectedComputer {
                tabShell
            } else {
                MGFirstLaunchView()
            }
        }
        .sheet(
            item: Binding(
                get: { appModel.presentedSheet },
                set: { appModel.presentedSheet = $0 }
            )
        ) { destination in
            sheet(for: destination)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private var tabShell: some View {
        TabView(
            selection: Binding(
                get: { appModel.selectedTab },
                set: { appModel.selectedTab = $0 }
            )
        ) {
            NavigationStack(
                path: Binding(
                    get: { appModel.spacesPath },
                    set: { appModel.spacesPath = $0 }
                )
            ) {
                MGSpacesView()
                    .navigationDestination(for: Route.self, destination: destinationView)
            }
            .tabItem { Label("Spaces", systemImage: "square.grid.2x2") }
            .tag(AppTab.spaces)

            NavigationStack(
                path: Binding(
                    get: { appModel.activityPath },
                    set: { appModel.activityPath = $0 }
                )
            ) {
                MGActivityView()
                    .navigationDestination(for: Route.self, destination: destinationView)
            }
            .tabItem { Label("Activity", systemImage: "bolt.horizontal") }
            .tag(AppTab.activity)

            NavigationStack(
                path: Binding(
                    get: { appModel.settingsPath },
                    set: { appModel.settingsPath = $0 }
                )
            ) {
                MGSettingsView()
                    .navigationDestination(for: Route.self, destination: destinationView)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .toolbarColorScheme(.dark, for: .tabBar)
    }

    @ViewBuilder
    private func destinationView(_ route: Route) -> some View {
        switch route {
        case .newTask(let spaceID):
            MGNewTaskView(spaceID: spaceID)
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
    private func sheet(for destination: SheetDestination) -> some View {
        switch destination {
        case .connectionInfo:
            MGConnectionSheet()
        case .modelPicker:
            MGModelPicker()
        case .plusMenu:
            MGPlusMenuSheet()
        case .slashCommands:
            MGSlashCommandsSheet()
        case .fileMentions:
            MGFileMentionsSheet()
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
}

struct MGFirstLaunchView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    MGLogoMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Maxgravity")
                            .font(.title.weight(.bold))
                            .foregroundStyle(MGTheme.primaryText)
                        Text("Native companion for Antigravity")
                            .font(.subheadline)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }

                Text("Connect Antigravity on your computer")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)

                Text("The connected computer must remain online for live sessions.")
                    .font(.body)
                    .foregroundStyle(MGTheme.secondaryText)
            }

            Spacer()

            VStack(spacing: 14) {
                MGPrimaryActionButton(title: "Scan QR code") {
                    appModel.connectMockComputer()
                    MGHaptics.success()
                }

                Button("Enter pairing code") {
                    appModel.presentedSheet = .pairingCode
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
    }
}

struct MGSpacesView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MGNavigationHeader(title: "Your Spaces", subtitle: nil) {
                    HStack(spacing: 10) {
                        if let connection = appModel.connection {
                            MGConnectionPill(status: connection) {
                                appModel.presentedSheet = .connectionInfo
                            }
                        }
                        Button {
                            appModel.selectedTab = .settings
                        } label: {
                            Image(systemName: "gearshape")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(MGSecondaryIconButtonStyle())
                        .accessibilityLabel("Open settings")
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
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    appModel.toggleSpace(space.id)
                                }
                            },
                            onOpenChat: { chat in
                                appModel.push(.chat(chatID: chat.id))
                            },
                            onNewTask: {
                                appModel.push(.newTask(spaceID: space.id))
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)

                MGPrimaryActionButton(title: "New task") {
                    if let firstSpace = appModel.spaces.first {
                        appModel.push(.newTask(spaceID: firstSpace.id))
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
    let spaceID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                composer
                contextRow
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .navigationTitle(spaceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(spaceTitle)
                        .font(.headline)
                        .foregroundStyle(MGTheme.primaryText)
                    if let connection = appModel.connection {
                        Text(connection.computerName)
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }
            }
        }
    }

    private var spaceTitle: String {
        appModel.space(with: spaceID)?.name ?? "New task"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New task")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(MGTheme.primaryText)
            Text("What are we building today?")
                .font(.subheadline)
                .foregroundStyle(MGTheme.secondaryText)
        }
    }

    private var composer: some View {
        MGComposer(
            text: Binding(
                get: { appModel.draftPrompt },
                set: { appModel.draftPrompt = $0 }
            ),
            selectedModel: appModel.draftContext.selectedModel.title,
            mentionedFiles: appModel.draftContext.mentionedFiles,
            onRemoveFile: appModel.removeMentionedFile,
            onPlus: { appModel.presentedSheet = .plusMenu },
            onSlash: { appModel.presentedSheet = .slashCommands },
            onMention: { appModel.presentedSheet = .fileMentions },
            onModel: { appModel.presentedSheet = .modelPicker },
            onMicrophone: { appModel.draftMicrophoneEnabled.toggle() },
            onSend: {
                if let chat = appModel.createTask(in: spaceID) {
                    appModel.push(.chat(chatID: chat.id))
                }
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
                    Text("\(appModel.draftContext.workingFolder) | \(appModel.draftContext.permissionMode.title) | \(appModel.draftContext.planMode ? "Plan mode on" : "Plan mode off")")
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .mgSectionCardPadding()
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background {
            MGAdaptiveSurface {
                Color.clear
            }
        }
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
        .navigationTitle(appModel.chat(with: chatID)?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Pin chat") {}
                    Button("Rename chat") {}
                    Button("View files") { appModel.push(.taskDetail(chatID: chatID, segment: .files)) }
                    Button("View commands") { appModel.push(.taskDetail(chatID: chatID, segment: .commands)) }
                    Button("View task activity") { appModel.push(.taskDetail(chatID: chatID, segment: .changes)) }
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
                Text(chat.thread.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MGTheme.primaryText)
                MGStatusPill(title: chat.thread.stateText, tone: chat.isRunning ? .good : .warning)
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
                .mgSectionCardPadding()
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(MGTheme.border, lineWidth: 1)
                )
                .frame(maxWidth: 320, alignment: .trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Maxgravity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
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
        }
    }

    private func openArtifact(_ artifact: MGArtifactSummary, chatID: String) {
        switch artifact.kind {
        case .file:
            appModel.push(.codeViewer(fileRef: artifact.title))
        case .diff:
            appModel.push(.diffViewer(fileRef: artifact.title))
        case .command:
            appModel.push(.taskDetail(chatID: chatID, segment: .commands))
        case .approval:
            if let approval = appModel.chat(with: chatID)?.thread.approval {
                appModel.presentedSheet = .approvalSteering(requestID: approval.id)
            }
        case .completion:
            appModel.push(.taskDetail(chatID: chatID, segment: .changes))
        case .screenshot:
            appModel.push(.taskDetail(chatID: chatID, segment: .files))
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
                                    appModel.push(.codeViewer(fileRef: file))
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
                                .buttonStyle(.plain)
                                .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    case .changes:
                        VStack(spacing: 10) {
                            ForEach(chat.thread.diffs, id: \.fileName) { diff in
                                Button {
                                    appModel.push(.diffViewer(fileRef: diff.fileName))
                                } label: {
                                    MGDiffSummary(diff: diff)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case .commands:
                        VStack(spacing: 10) {
                            ForEach(chat.thread.commands) { command in
                                DisclosureGroup {
                                    Text(command.output)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(MGTheme.primaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 8)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(command.command)
                                            .font(.subheadline.monospaced().weight(.semibold))
                                            .foregroundStyle(MGTheme.primaryText)
                                        Text("\(command.result) | \(command.duration)")
                                            .font(.caption)
                                            .foregroundStyle(MGTheme.secondaryText)
                                    }
                                }
                                .padding(12)
                                .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(MGTheme.border, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Task detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MGCodeViewerScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            Text("""
            import SwiftUI

            struct BottomBar: View {
                var body: some View {
                    HStack(spacing: 16) {
                        // Placeholder code view until bridge-backed file reads are connected.
                    }
                }
            }
            """)
                .font(.body.monospaced())
                .foregroundStyle(MGTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(MGAppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") {}
            }
        }
    }
}

struct MGDiffViewerScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(MGTheme.primaryText)
                Text("+ Added lines shown in green")
                    .foregroundStyle(MGTheme.success)
                Text("- Removed lines shown in red")
                    .foregroundStyle(MGTheme.danger)
                Text("~ Modified lines shown in amber")
                    .foregroundStyle(MGTheme.warning)
            }
            .font(.body.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(MGAppBackground())
        .navigationTitle("Diff")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MGActivityView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Activity")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                VStack(spacing: 16) {
                    ForEach(appModel.activityBuckets) { bucket in
                        MGSettingsGroup(title: bucket.title) {
                            VStack(spacing: 0) {
                                ForEach(bucket.items) { item in
                                    Button {
                                        if let route = item.route {
                                            appModel.push(route, on: .activity)
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
                                    .buttonStyle(.plain)
                                    if item.id != bucket.items.last?.id {
                                        Divider().overlay(MGTheme.border)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
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

struct MGSettingsView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                VStack(spacing: 16) {
                    connectionGroup
                    appearanceGroup
                    notificationsGroup
                    defaultsGroup
                    privacyGroup
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }

    private var connectionGroup: some View {
        MGSettingsGroup(title: "Connection") {
            VStack(spacing: 0) {
                settingsRow("Connected computer", value: appModel.connection?.computerName ?? "None")
                Divider().overlay(MGTheme.border)
                settingsRow("Status", value: appModel.connection?.isOnline == true ? "Online" : "Offline")
                Divider().overlay(MGTheme.border)
                settingsRow("Last sync", value: DateFormatter.mgTime.string(from: appModel.connection?.lastSync ?? .now))
                Divider().overlay(MGTheme.border)
                settingsButtonRow("Link another computer") { appModel.presentedSheet = .pairingCode }
                Divider().overlay(MGTheme.border)
                settingsButtonRow("Disconnect current computer", role: .destructive) { appModel.disconnectCurrentComputer() }
            }
        }
    }

    private var appearanceGroup: some View {
        MGSettingsGroup(title: "Appearance") {
            VStack(spacing: 0) {
                settingsRow("Appearance", value: "System dark")
                Divider().overlay(MGTheme.border)
                settingsRow("High contrast", value: "Available")
                Divider().overlay(MGTheme.border)
                settingsRow("Automatic Liquid Glass adaptation", value: "Enabled")
            }
        }
    }

    private var notificationsGroup: some View {
        MGSettingsGroup(title: "Notifications") {
            VStack(spacing: 0) {
                settingsRow("Task completed", value: "On")
                Divider().overlay(MGTheme.border)
                settingsRow("Approval required", value: "On")
                Divider().overlay(MGTheme.border)
                settingsRow("Scheduled reminder", value: "On")
                Divider().overlay(MGTheme.border)
                settingsRow("Connection lost", value: "On")
            }
        }
    }

    private var defaultsGroup: some View {
        MGSettingsGroup(title: "Default task behavior") {
            VStack(spacing: 0) {
                settingsRow("Default model", value: appModel.draftContext.selectedModel.title)
                Divider().overlay(MGTheme.border)
                settingsRow("Default permission mode", value: appModel.draftContext.permissionMode.title)
                Divider().overlay(MGTheme.border)
                settingsRow("Default plan mode", value: appModel.draftContext.planMode ? "On" : "Off")
                Divider().overlay(MGTheme.border)
                settingsRow("Default Space", value: appModel.spaces.first?.name ?? "None")
            }
        }
    }

    private var privacyGroup: some View {
        MGSettingsGroup(title: "Privacy and storage") {
            VStack(spacing: 0) {
                settingsRow("Local cache", value: "Thread snapshots only")
                Divider().overlay(MGTheme.border)
                settingsButtonRow("Clear local chat cache") {}
                Divider().overlay(MGTheme.border)
                settingsRow("Trusted connected computers", value: "\(appModel.trustedComputers.count)")
                Divider().overlay(MGTheme.border)
                settingsRow("Connection encryption", value: appModel.connection?.encryption ?? "Not paired")
            }
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(MGTheme.primaryText)
            Spacer()
            Text(value)
                .foregroundStyle(MGTheme.secondaryText)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 10)
    }

    private func settingsButtonRow(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
        }
        .foregroundStyle(role == .destructive ? MGTheme.danger : MGTheme.primaryText)
        .frame(minHeight: 44)
        .padding(.vertical, 10)
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

struct MGPlusMenuSheet: View {
    let rows: [(String, String, String)] = [
        ("photo", "Upload media", "Add screenshots or visual references"),
        ("paperclip", "Attach file", "Attach a local mobile file for context"),
        ("list.bullet.clipboard", "Plan mode", "Switch the task into planning-first mode"),
        ("folder", "Choose working folder", "Browse approved desktop folders"),
        ("folder.badge.plus", "Create new folder", "Create a folder through the bridge"),
        ("lock.shield", "Permissions", "Review desktop-enforced permission mode")
    ]

    var body: some View {
        NavigationStack {
            List(Array(rows.enumerated()), id: \.offset) { entry in
                let row = entry.element
                HStack(spacing: 12) {
                    Image(systemName: row.0)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.1)
                        Text(row.2)
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }
                .foregroundStyle(MGTheme.primaryText)
                .frame(minHeight: 44)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Task tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGSlashCommandsSheet: View {
    let commands = ["/plan", "/review", "/test", "/summarize", "/schedule", "/explain"]

    var body: some View {
        NavigationStack {
            List(commands, id: \.self) { command in
                Text(command)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(MGTheme.primaryText)
                    .frame(minHeight: 44, alignment: .leading)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Slash commands")
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
        let files = [
            "@src/components/BottomBar.tsx",
            "@README.md",
            "@package.json",
            "@src/routes/PlayerRoute.tsx"
        ]
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
    @State private var guidance = "Do not use this library. Replace it with native SwiftUI."

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
                    .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(MGTheme.border, lineWidth: 1)
                    )
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
    @State private var selectedSpace = "Antigravity App"
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
                            Text("\(DateFormatter.mgSchedule.string(from: item.nextRun)) | \(item.frequency) | \(item.spaceName)")
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
    @State private var pairingCode = "MG-8491"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter pairing code")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                Text("Use a code shown by the local Maxgravity Bridge on your computer.")
                    .font(.subheadline)
                    .foregroundStyle(MGTheme.secondaryText)
                TextField("Pairing code", text: $pairingCode)
                    .textInputAutocapitalization(.characters)
                    .padding(14)
                    .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(MGTheme.border, lineWidth: 1)
                    )
                MGPrimaryActionButton(title: "Pair and connect") {
                    appModel.connectMockComputer()
                    dismiss()
                }
                Spacer()
            }
            .padding(20)
            .background(MGAppBackground())
            .navigationTitle("Pairing")
            .navigationBarTitleDisplayMode(.inline)
        }
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
