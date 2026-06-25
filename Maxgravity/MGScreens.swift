import SwiftUI

struct MGRootView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ZStack {
            MGAppBackground()
            if appModel.hasConnectedComputer {
                NavigationStack(path: Binding(get: { appModel.path }, set: { appModel.path = $0 })) {
                    MGSpacesView()
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
        .background {
            floatingPanelPresenter
        }
#if !canImport(FloatingPanel)
        .sheet(item: Binding(get: { appModel.presentedPanel }, set: { appModel.presentedPanel = $0 })) { panel in
            panelView(for: panel)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationBackground(.clear)
                .presentationDetents([.fraction(0.42), .large])
        }
#endif
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

    @ViewBuilder
    private func panelView(for destination: MGPanelDestination) -> some View {
        switch destination {
        case .activity:
            MGActivityPanelView()
        case .settings:
            MGSettingsPanelView()
        }
    }

    @ViewBuilder
    private var floatingPanelPresenter: some View {
        if let panel = appModel.presentedPanel {
            MGFloatingPanelPresenter(
                isPresented: Binding(
                    get: { appModel.presentedPanel != nil },
                    set: { isPresented in
                        if !isPresented {
                            appModel.presentedPanel = nil
                        }
                    }
                )
            ) {
                panelView(for: panel)
            }
            .frame(width: 0, height: 0)
        }
    }

    private func sheetDetents(for destination: MGSheetDestination) -> Set<PresentationDetent> {
        switch destination {
        case .connectionInfo, .approvalSteering:
            [.medium, .large]
        case .modelPicker, .slashCommands, .fileMentions, .taskContext, .remoteFolderPicker, .scheduleTask, .pairingCode:
            [.large]
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

struct MGSpacesView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MGNavigationHeader(
                    title: "Your Spaces",
                    subtitle: "Choose a space, jump into a chat, or start a new task."
                ) {
                    VStack(alignment: .trailing, spacing: 10) {
                        if let connection = appModel.connection {
                            MGConnectionPill(status: connection) {
                                appModel.presentedSheet = .connectionInfo
                            }
                        }
                        HStack(spacing: 10) {
                            Button {
                                appModel.presentPanel(.activity)
                            } label: {
                                Image(systemName: "bolt.horizontal.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(MGSecondaryIconButtonStyle())
                            .accessibilityLabel("Open activity")

                            Button {
                                appModel.presentPanel(.settings)
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(MGSecondaryIconButtonStyle())
                            .accessibilityLabel("Open settings")
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
            mentionedFiles: appModel.draftContext.mentionedFiles,
            onRemoveFile: appModel.removeMentionedFile,
            onPlus: { appModel.presentedFullScreen = .plusMenu },
            onSlash: { appModel.presentedSheet = .slashCommands },
            onMention: { appModel.presentedSheet = .fileMentions },
            onModel: { appModel.presentedSheet = .modelPicker },
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
                    MGBrandMark(size: 18)
                    Text("Maxgravity")
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
        """
        struct BottomBar: View {
            var body: some View {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Spaces")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        """
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

struct MGActivityPanelView: View {
    @Environment(MGAppModel.self) private var appModel

    var body: some View {
        MGPanelShell(title: "Activity") {
            ForEach(appModel.activityBuckets) { bucket in
                MGSettingsGroup(title: bucket.title) {
                    VStack(spacing: 0) {
                        ForEach(bucket.items) { item in
                            Button {
                                appModel.dismissPanel()
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

struct MGSettingsPanelView: View {
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
        ("camera.fill", "Camera"),
        ("photo.on.rectangle.angled", "Photos"),
        ("doc.fill", "Files"),
        ("puzzlepiece.extension.fill", "Plugins")
    ]

    private let secondaryRows: [(String, String)] = [
        ("at", "Mention workspace file"),
        ("list.bullet.clipboard", "Plan mode"),
        ("folder", "Choose working folder"),
        ("folder.badge.plus", "Create folder"),
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
    @Environment(\.dismiss) private var dismiss
    @State private var pairingCode = "MG-8491"
    @State private var statusMessage = "Manual code entry is scaffolded. Complete trust confirmation requires the running Windows bridge."

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                MGBrandMark(size: 40)
                Text("Enter pairing code")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                Text("Use a code shown by the local Maxgravity Bridge on your computer.")
                    .font(.subheadline)
                    .foregroundStyle(MGTheme.secondaryText)
                TextField("Pairing code", text: $pairingCode)
                    .textInputAutocapitalization(.characters)
                    .padding(14)
                    .mgReadableSurface(cornerRadius: 18)
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(MGTheme.warning)
                MGPrimaryActionButton(title: "Check pairing code") {
                    statusMessage = "Partial: bridge pairing endpoints are implemented, but this iOS build still needs camera scan, Keychain storage, and desktop trust confirmation before it can connect."
                    MGHaptics.warning()
                }
                Button("Close") {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .buttonStyle(MGPressableButtonStyle())
                .mgInteractiveGlass(cornerRadius: 22)
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
