import SwiftUI
import UIKit

struct MGAppBackground: View {
    var body: some View {
        MGTheme.background
            .ignoresSafeArea()
    }
}

struct MGLogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.46, blue: 0.18),
                            Color(red: 0.95, green: 0.26, blue: 0.46),
                            Color(red: 0.62, green: 0.21, blue: 0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

struct MGNavigationHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(MGTheme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MGTheme.secondaryText)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct MGStatusPill: View {
    let title: String
    let tone: MGActivityTone

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().stroke(MGTheme.border, lineWidth: 1))
    }

    private var color: Color {
        switch tone {
        case .neutral: MGTheme.secondaryText
        case .good: MGTheme.success
        case .warning: MGTheme.warning
        case .critical: MGTheme.danger
        }
    }
}

struct MGConnectionPill: View {
    let status: MGComputerStatus
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(status.isOnline ? MGTheme.success : MGTheme.danger)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.computerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MGTheme.primaryText)
                    Text(status.isOnline ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background {
            MGAdaptiveSurface {
                Color.clear
            }
        }
        .accessibilityLabel("\(status.computerName), \(status.isOnline ? "online" : "offline")")
    }
}

struct MGSpaceRow: View {
    let space: MGSpaceSummary
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenChat: (MGChatSummary) -> Void
    let onNewTask: () -> Void

    var body: some View {
        MGAdaptiveSurface {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(MGTheme.primaryText)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(space.name)
                                .font(.headline)
                                .foregroundStyle(MGTheme.primaryText)
                            Text("\(space.chats.count) chats")
                                .font(.subheadline)
                                .foregroundStyle(MGTheme.secondaryText)
                        }
                        Spacer()
                        if let statusText = space.statusText {
                            MGStatusPill(title: statusText, tone: .neutral)
                        }
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                    .mgSectionCardPadding()
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(space.isPinned ? "Unpin" : "Pin") {}
                    Button("Rename") {}
                    Button("Collapse all") {}
                    Button("Manage connection roots") {}
                }

                if isExpanded {
                    Divider()
                        .overlay(MGTheme.border)
                        .padding(.horizontal, 16)
                    VStack(spacing: 0) {
                        ForEach(space.chats) { chat in
                            MGChatRow(chat: chat) {
                                onOpenChat(chat)
                            }
                            if chat.id != space.chats.last?.id {
                                Divider()
                                    .overlay(MGTheme.border)
                                    .padding(.leading, 52)
                            }
                        }

                        if space.chats.isEmpty {
                            Text("No chats yet")
                                .font(.subheadline)
                                .foregroundStyle(MGTheme.secondaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                        }
                    }

                    Button(action: onNewTask) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                            Text("New task")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(MGTheme.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
            }
        }
    }
}

struct MGChatRow: View {
    let chat: MGChatSummary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(chat.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(MGTheme.primaryText)
                            .multilineTextAlignment(.leading)
                        if chat.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(MGTheme.secondaryText)
                        }
                    }
                    Text(DateFormatter.mgTime.string(from: chat.lastActivity))
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Spacer()
                if chat.isRunning {
                    MGStatusPill(title: "Running", tone: .good)
                }
            }
            .padding(.leading, 52)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(chat.isPinned ? "Unpin" : "Pin") {}
            Button("Rename") {}
            Button("Delete local history", role: .destructive) {}
            Button("Move to Space") {}
        }
    }
}

struct MGPrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(MGPrimaryButtonStyle())
    }
}

struct MGComposerAccessoryBar: View {
    var onPlus: () -> Void
    var onSlash: () -> Void
    var onMention: () -> Void
    var onModel: () -> Void
    var onMicrophone: () -> Void
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton(symbol: "plus", action: onPlus, label: "Plus menu")
            iconButton(symbol: "slash", action: onSlash, label: "Slash commands")
            iconButton(symbol: "@", action: onMention, label: "Mention file", isText: true)
            Spacer(minLength: 8)
            Button(action: onModel) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                    Text("Model")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(MGTheme.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(MGTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(MGTheme.border, lineWidth: 1))

            iconButton(symbol: "mic", action: onMicrophone, label: "Microphone")
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send task")
        }
    }

    @ViewBuilder
    private func iconButton(symbol: String, action: @escaping () -> Void, label: String, isText: Bool = false) -> some View {
        Button(action: action) {
            Group {
                if isText {
                    Text(symbol)
                        .font(.body.weight(.semibold))
                } else {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(MGSecondaryIconButtonStyle())
        .accessibilityLabel(label)
    }
}

struct MGComposer: View {
    @Binding var text: String
    let selectedModel: String
    let mentionedFiles: [String]
    let onRemoveFile: (String) -> Void
    let onPlus: () -> Void
    let onSlash: () -> Void
    let onMention: () -> Void
    let onModel: () -> Void
    let onMicrophone: () -> Void
    let onSend: () -> Void

    var body: some View {
        MGAdaptiveSurface {
            VStack(alignment: .leading, spacing: 14) {
                if !mentionedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(mentionedFiles, id: \.self) { file in
                                HStack(spacing: 6) {
                                    Text(file)
                                        .lineLimit(1)
                                        .font(.caption.weight(.medium))
                                    Button(action: { onRemoveFile(file) }) {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(MGTheme.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.05), in: Capsule())
                                .overlay(Capsule().stroke(MGTheme.border, lineWidth: 1))
                            }
                        }
                    }
                }

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Describe what you want Antigravity to build, change, review, or investigate...")
                            .font(.body)
                            .foregroundStyle(MGTheme.tertiaryText)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .foregroundStyle(MGTheme.primaryText)
                        .frame(minHeight: 170)
                        .tint(.white)
                }

                HStack {
                    Text(selectedModel)
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                    Spacer()
                    Text("\(text.count) chars")
                        .font(.caption)
                        .foregroundStyle(MGTheme.tertiaryText)
                }

                MGComposerAccessoryBar(
                    onPlus: onPlus,
                    onSlash: onSlash,
                    onMention: onMention,
                    onModel: onModel,
                    onMicrophone: onMicrophone,
                    onSend: onSend
                )
            }
            .mgSectionCardPadding()
        }
    }
}

struct MGAgentActivityTimeline: View {
    let stateText: String
    let events: [MGActivityEvent]

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 12) {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.isComplete ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                            .foregroundStyle(iconColor(for: event))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MGTheme.primaryText)
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(MGTheme.secondaryText)
                        }
                        Spacer()
                        Text(event.duration)
                            .font(.caption.monospaced())
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                MGThreeDotsPulse()
                Text(stateText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MGTheme.primaryText)
                Spacer()
            }
        }
        .padding(14)
        .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MGTheme.border, lineWidth: 1)
        )
    }

    private func iconColor(for event: MGActivityEvent) -> Color {
        switch event.tone {
        case .neutral: MGTheme.secondaryText
        case .good: MGTheme.success
        case .warning: MGTheme.warning
        case .critical: MGTheme.danger
        }
    }
}

struct MGThreeDotsPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MGTheme.secondaryText)
                    .frame(width: 6, height: 6)
                    .opacity(phase ? 0.95 : 0.35)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever().delay(Double(index) * 0.12),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

struct MGArtifactRow: View {
    let artifact: MGArtifactSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(MGTheme.primaryText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(artifact.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MGTheme.primaryText)
                    Text(artifact.detail)
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .padding(12)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MGTheme.border, lineWidth: 1)
        )
    }

    private var symbol: String {
        switch artifact.kind {
        case .file: "doc.text"
        case .diff: "arrow.left.arrow.right.square"
        case .command: "terminal"
        case .screenshot: "photo"
        case .approval: "hand.raised"
        case .completion: "checkmark.seal"
        }
    }
}

struct MGDiffSummary: View {
    let diff: MGDiffStat

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(diff.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MGTheme.primaryText)
                HStack(spacing: 10) {
                    Text("+\(diff.added)")
                        .foregroundStyle(MGTheme.success)
                    Text("-\(diff.removed)")
                        .foregroundStyle(MGTheme.danger)
                    if diff.modified > 0 {
                        Text("~\(diff.modified)")
                            .foregroundStyle(MGTheme.warning)
                    }
                }
                .font(.caption.monospaced())
            }
            Spacer()
        }
        .padding(12)
        .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MGTheme.border, lineWidth: 1)
        )
    }
}

struct MGApprovalPanel: View {
    let request: MGApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    let onSteer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MGStatusPill(title: "Waiting for approval", tone: .warning)
            Text(request.title)
                .font(.headline)
                .foregroundStyle(MGTheme.primaryText)
            Text(request.summary)
                .font(.subheadline)
                .foregroundStyle(MGTheme.secondaryText)
            Text(request.scope)
                .font(.caption)
                .foregroundStyle(MGTheme.tertiaryText)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(request.affectedItems, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .foregroundStyle(MGTheme.primaryText)
                }
            }

            HStack(spacing: 10) {
                Button("Approve", action: onApprove)
                    .buttonStyle(MGPrimaryButtonStyle())
                Button("Reject", action: onReject)
                    .buttonStyle(.bordered)
                    .tint(MGTheme.warning)
                    .frame(minHeight: 52)
                Button("Steer", action: onSteer)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .frame(minHeight: 52)
            }
        }
        .mgSectionCardPadding()
        .background(MGTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MGTheme.warning.opacity(0.45), lineWidth: 1)
        )
    }
}

struct MGCompletionEmbed: View {
    let summary: MGCompletionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MGStatusPill(title: "Task completed", tone: .good)
            Text(summary.summary)
                .font(.subheadline)
                .foregroundStyle(MGTheme.primaryText)
            VStack(alignment: .leading, spacing: 8) {
                metricRow("Files modified", value: "\(summary.filesChanged)")
                metricRow("Lines added", value: "+\(summary.linesAdded)")
                metricRow("Lines removed", value: "-\(summary.linesRemoved)")
            }
            if !summary.checksRun.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checks run")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MGTheme.secondaryText)
                    ForEach(summary.checksRun, id: \.self) { check in
                        Text(check)
                            .font(.caption.monospaced())
                            .foregroundStyle(MGTheme.primaryText)
                    }
                }
            }
            if !summary.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Warnings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MGTheme.warning)
                    ForEach(summary.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(MGTheme.secondaryText)
                    }
                }
            }
            Button("Copy reply") {
                UIPasteboard.general.string = summary.fullReply
                MGHaptics.success()
            }
            .buttonStyle(MGPrimaryButtonStyle())
        }
        .mgSectionCardPadding()
        .background(MGTheme.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MGTheme.success.opacity(0.4), lineWidth: 1)
        )
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(MGTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
        }
    }
}

struct MGTaskContextSheet: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Working folder") {
                    Button(appModel.draftContext.workingFolder) {
                        appModel.presentedSheet = .remoteFolderPicker
                    }
                    .foregroundStyle(MGTheme.primaryText)
                }

                Section("Permissions") {
                    ForEach(appModel.connection?.supportedPermissionModes ?? [.sandbox, .askWhenNeeded, .sensitiveAutoReview]) { mode in
                        Button {
                            appModel.updateDraftPermission(mode)
                        } label: {
                            HStack {
                                Text(mode.title)
                                Spacer()
                                if appModel.draftContext.permissionMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(MGTheme.primaryText)
                    }
                }

                Section("Plan mode") {
                    Toggle(
                        "Enable plan mode",
                        isOn: Binding(
                            get: { appModel.draftContext.planMode },
                            set: { appModel.draftContext.planMode = $0 }
                        )
                    )
                    .tint(.white)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Task context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MGRemoteFolderPicker: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(appModel.remoteRoots, children: \.children) { node in
                Button {
                    if node.isDirectory {
                        appModel.draftContext.workingFolder = node.path
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: node.isDirectory ? "folder" : "doc.text")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.name)
                            Text(node.path)
                                .font(.caption)
                                .foregroundStyle(MGTheme.secondaryText)
                        }
                    }
                    .foregroundStyle(MGTheme.primaryText)
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Choose folder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGModelPicker: View {
    @Environment(MGAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(appModel.models) { model in
                Button {
                    appModel.updateDraftModel(model)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(model.title)
                                    .foregroundStyle(MGTheme.primaryText)
                                if model.isRecommended {
                                    MGStatusPill(title: "Recommended", tone: .good)
                                }
                            }
                            if let subtitle = model.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(MGTheme.secondaryText)
                            }
                        }
                        Spacer()
                        if appModel.draftContext.selectedModel == model {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(MGAppBackground())
            .navigationTitle("Select model")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MGSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MGTheme.primaryText)
            MGAdaptiveSurface {
                VStack(spacing: 0) {
                    content
                }
                .mgSectionCardPadding()
            }
        }
    }
}
