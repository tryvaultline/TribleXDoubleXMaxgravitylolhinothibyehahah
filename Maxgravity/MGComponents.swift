import SwiftUI
import UIKit
import PhotosUI

#if canImport(FloatingPanel)
import FloatingPanel
#endif

struct MGBrandMark: View {
    var size: CGFloat

    var body: some View {
        Image("MaxgravityMarkGradient")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct MGBrandWordmark: View {
    var compact: Bool = false

    var body: some View {
        Text("Maxgravity")
            .font(compact ? .headline.weight(.semibold) : .title3.weight(.bold))
            .foregroundStyle(MGTheme.primaryText)
    }
}

struct MGGoogleAvatar: View {
    var size: CGFloat = 34

    var body: some View {
        let radius = size * 0.3
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.24, green: 0.52, blue: 0.96),
                            Color(red: 0.20, green: 0.80, blue: 0.54),
                            Color(red: 0.98, green: 0.73, blue: 0.16),
                            Color(red: 0.92, green: 0.29, blue: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("G")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MGNavigationHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                MGBrandWordmark(compact: true)
                Text(title)
                    .font(.system(size: 30, weight: .bold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .mgInteractiveGlass(cornerRadius: 18)
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
        Button(action: {
            MGHaptics.selection()
            action()
        }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(status.isOnline ? MGTheme.success : MGTheme.danger)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.computerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MGTheme.primaryText)
                    Text("\(status.isOnline ? "Online" : "Offline") • \(status.quality.title)")
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(MGPressableButtonStyle())
        .mgInteractiveGlass(cornerRadius: 20)
        .accessibilityLabel("\(status.computerName), \(status.isOnline ? "online" : "offline"), \(status.quality.title)")
    }
}

struct MGSpaceRow: View {
    let space: MGSpaceSummary
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpenChat: (MGChatSummary) -> Void
    let onNewTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    iconWell(symbol: "square.grid.2x2.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(space.name)
                            .font(.body.weight(.semibold))
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MGTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(MGPressableButtonStyle())
            .contextMenu {
                Button(space.isPinned ? "Unpin Space" : "Pin Space") {}
                Button("Rename Space") {}
                Button("Collapse all") {}
                Button("Manage workspace root") {}
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
                                .padding(.leading, 68)
                        }
                    }
                }

                Button(action: onNewTask) {
                    HStack(spacing: 12) {
                        MGBrandMark(size: 18)
                        Text("New task")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(MGTheme.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(MGPressableButtonStyle())
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .mgInteractiveGlass(cornerRadius: 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .mgReadableSurface(cornerRadius: 28)
    }

    private func iconWell(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(MGTheme.primaryText)
            .frame(width: 40, height: 40)
            .mgInteractiveGlass(cornerRadius: 16)
    }
}

struct MGChatRow: View {
    let chat: MGChatSummary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MGTheme.secondaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 5) {
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
                    Text(DateFormatter.mgRelative.localizedString(for: chat.lastActivity, relativeTo: .now))
                        .font(.caption)
                        .foregroundStyle(MGTheme.secondaryText)
                }
                Spacer()
                if chat.isRunning {
                    MGStatusPill(title: "Running", tone: .good)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(MGPressableButtonStyle())
        .contextMenu {
            Button(chat.isPinned ? "Unpin" : "Pin") {}
            Button("Rename") {}
            Button("Move to another Space") {}
            Button("Delete local history", role: .destructive) {}
        }
    }
}

struct MGPrimaryActionButton: View {
    let title: String
    let icon: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    init(title: String, icon: String? = nil, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            MGHaptics.impact(.light)
            action()
        }) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black.opacity(0.82))
                        .scaleEffect(0.92)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
        }
        .buttonStyle(MGPrimaryButtonStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct MGDarkGlassSheet<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(width: 44, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 18)

            content
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 26, y: 14)
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11))
        } else {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.82))
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
        }
    }
}

struct MGDarkGlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.13, green: 0.13, blue: 0.14))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(red: 0.12, green: 0.12, blue: 0.13).opacity(0.76))
                        }
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, y: 12)
    }
}

struct MGGlassIconWell: View {
    let systemName: String
    var tone: Color = MGTheme.warning

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(tone.opacity(0.20))
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tone)
        }
        .frame(width: 54, height: 54)
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)
    }
}

struct MGComposerAccessoryBar: View {
    let selectedModel: String
    let models: [MGModelOption]
    var onPlus: () -> Void
    var onSlash: () -> Void
    var onMention: () -> Void
    var onSelectModel: (MGModelOption) -> Void
    var onMicrophone: () -> Void
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton(symbol: "plus", action: onPlus, label: "Attachment menu")
            iconButton(symbol: "slash", action: onSlash, label: "Slash commands")
            iconButton(symbol: "@", action: onMention, label: "Mention file", usesText: true)
            Spacer(minLength: 10)

            Menu {
                ForEach(models) { model in
                    Button {
                        onSelectModel(model)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(model.title, systemImage: model.isRecommended ? "checkmark.circle.fill" : "circle")
                            if let speed = model.speedLabel, let effort = model.effortLabel {
                                Text("Speed: \(speed) • Effort: \(effort)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                    Text(selectedModel)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MGTheme.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
            }
            .buttonStyle(MGPressableButtonStyle())
            .mgInteractiveGlass(cornerRadius: 18)

            iconButton(symbol: "mic.fill", action: onMicrophone, label: "Microphone")

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(MGPressableButtonStyle())
            .accessibilityLabel("Send task")
        }
    }

    @ViewBuilder
    private func iconButton(symbol: String, action: @escaping () -> Void, label: String, usesText: Bool = false) -> some View {
        Button(action: action) {
            Group {
                if usesText {
                    Text(symbol)
                        .font(.body.weight(.semibold))
                } else {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(MGTheme.primaryText)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(MGPressableButtonStyle())
        .mgInteractiveGlass(cornerRadius: 18)
        .accessibilityLabel(label)
    }
}

struct MGComposer: View {
    @Binding var text: String
    let selectedModel: String
    let modelOptions: [MGModelOption]
    let mentionedFiles: [String]
    let pickedPhotos: [MGPickedPhoto]
    let onRemoveFile: (String) -> Void
    let onRemovePhoto: (String) -> Void
    let onPlus: () -> Void
    let onSlash: () -> Void
    let onMention: () -> Void
    let onSelectModel: (MGModelOption) -> Void
    let onMicrophone: () -> Void
    let onSend: () -> Void

    var body: some View {
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
                            .mgInteractiveGlass(cornerRadius: 16)
                        }
                    }
                }
            }

            if !pickedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pickedPhotos) { photo in
                            if let image = UIImage(data: photo.data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    Button(action: { onRemovePhoto(photo.id) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(.white)
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Describe what you want Maxgravity to build, change, review, or investigate…")
                        .font(.body)
                        .foregroundStyle(MGTheme.tertiaryText)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(MGTheme.primaryText)
                    .frame(minHeight: 188)
                    .tint(.white)
            }

            HStack {
                Text("Focused task composer")
                    .font(.caption)
                    .foregroundStyle(MGTheme.secondaryText)
                Spacer()
                Text("\(text.count) chars")
                    .font(.caption)
                    .foregroundStyle(MGTheme.tertiaryText)
            }

            MGComposerAccessoryBar(
                selectedModel: selectedModel,
                models: modelOptions,
                onPlus: onPlus,
                onSlash: onSlash,
                onMention: onMention,
                onSelectModel: onSelectModel,
                onMicrophone: onMicrophone,
                onSend: onSend
            )
        }
        .padding(16)
        .mgReadableSurface(cornerRadius: 30)
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
        .mgInteractiveGlass(cornerRadius: 22)
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
                    .offset(y: phase ? -1 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.82).repeatForever().delay(Double(index) * 0.12),
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
        .buttonStyle(MGPressableButtonStyle())
        .mgInteractiveGlass(cornerRadius: 20)
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
        .mgReadableSurface(cornerRadius: 20)
    }
}

struct MGApprovalPanel: View {
    let request: MGApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    let onSteer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MGStatusPill(title: "Approval required", tone: .warning)
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
                    .buttonStyle(MGPressableButtonStyle(foreground: MGTheme.warning))
                    .frame(minHeight: 52)
                    .mgInteractiveGlass(cornerRadius: 20)
                Button("Steer", action: onSteer)
                    .buttonStyle(MGPressableButtonStyle())
                    .frame(minHeight: 52)
                    .mgInteractiveGlass(cornerRadius: 20)
            }
        }
        .padding(18)
        .mgReadableSurface(cornerRadius: 28)
    }
}

struct MGCompletionEmbed: View {
    let summary: MGCompletionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MGBrandMark(size: 24)
                MGStatusPill(title: "Task completed", tone: .good)
            }
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
        .padding(18)
        .mgInteractiveGlass(cornerRadius: 30)
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                    Text(mode.summary)
                                        .font(.caption)
                                        .foregroundStyle(MGTheme.secondaryText)
                                }
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
            List(appModel.remoteRoots, children: \.optionalChildren) { node in
                Button {
                    if node.isDirectory {
                        appModel.draftContext.workingFolder = node.path
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
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
                                MGStatusPill(title: model.availability.title, tone: model.availability.tone)
                            }
                            if let subtitle = model.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(MGTheme.secondaryText)
                            }
                            if let speed = model.speedLabel, let effort = model.effortLabel {
                                Text("Speed: \(speed) • Effort: \(effort)")
                                    .font(.caption2)
                                    .foregroundStyle(MGTheme.tertiaryText)
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
            VStack(spacing: 0) {
                content
            }
            .padding(14)
            .mgReadableSurface(cornerRadius: 26)
        }
    }
}

struct MGGlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .mgInteractiveGlass(cornerRadius: cornerRadius)
    }
}

struct MGGlassButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(minHeight: 44)
        }
        .buttonStyle(MGPressableButtonStyle())
        .mgInteractiveGlass(cornerRadius: 20)
    }
}

struct MGGlassIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(MGSecondaryIconButtonStyle())
        .accessibilityLabel(label)
    }
}

typealias MGGlassComposer = MGComposer
typealias MGGlassPill = MGStatusPill
typealias MGGlassAttachmentMenu = MGPlusMenuOverlay
typealias MGGlassCompletionEmbed = MGCompletionEmbed

struct MGGlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        MGGlassSurface(cornerRadius: 30) {
            content
        }
    }
}

struct MGGlassListGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        MGSettingsGroup(title: title) {
            content
        }
    }
}

#if canImport(FloatingPanel)
struct MGFloatingPanelPresenter<PanelContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let panelContent: PanelContent

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> PanelContent) {
        self._isPresented = isPresented
        self.panelContent = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            if let hosting = context.coordinator.panel?.contentViewController as? UIHostingController<PanelContent> {
                hosting.rootView = panelContent
                return
            }

            let panel = FloatingPanelController()
            panel.isRemovalInteractionEnabled = true
            panel.surfaceView.appearance.cornerRadius = 34
            panel.surfaceView.appearance.backgroundColor = UIColor.black.withAlphaComponent(0.82)
            panel.surfaceView.grabberHandle.isHidden = false
            let hosting = UIHostingController(rootView: panelContent)
            hosting.view.backgroundColor = .clear
            panel.set(contentViewController: hosting)
            panel.presentationController?.delegate = context.coordinator
            context.coordinator.panel = panel
            uiViewController.present(panel, animated: true)
        } else if let panel = context.coordinator.panel {
            panel.dismiss(animated: true)
            context.coordinator.panel = nil
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var panel: FloatingPanelController?
        private var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            panel = nil
            isPresented.wrappedValue = false
        }
    }
}
#else
struct MGFloatingPanelPresenter<PanelContent: View>: View {
    @Binding var isPresented: Bool
    let panelContent: PanelContent

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> PanelContent) {
        self._isPresented = isPresented
        self.panelContent = content()
    }

    var body: some View {
        EmptyView()
    }
}
#endif
