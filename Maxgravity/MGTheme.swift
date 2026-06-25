import SwiftUI
import UIKit

enum MGTheme {
    static let background = Color.black
    static let surface = Color.white.opacity(0.08)
    static let elevatedSurface = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.10)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.45)
    static let success = Color.green.opacity(0.92)
    static let warning = Color.yellow.opacity(0.92)
    static let danger = Color.red.opacity(0.92)
    static let shadow = Color.black.opacity(0.35)
}

enum MGHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

extension DateFormatter {
    static let mgTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let mgSchedule: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

extension View {
    func mgSectionCardPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}

struct MGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct MGSecondaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MGTheme.primaryText)
            .frame(minWidth: 44, minHeight: 44)
            .background(MGTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(MGTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct MGClassicDarkSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MGTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MGTheme.border, lineWidth: 1)
            )
            .shadow(color: MGTheme.shadow, radius: 16, y: 8)
    }
}

struct MGLiquidGlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(backgroundShape.fill(reduceTransparency ? MGTheme.elevatedSurface : .ultraThinMaterial))
            .overlay(backgroundShape.stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: MGTheme.shadow, radius: 18, y: 10)
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }
}

struct MGAdaptiveSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            // Replace this wrapper with official glassEffect/GlassEffectContainer APIs
            // when building on the iOS 26 SDK.
            MGLiquidGlassSurface(content: content)
        } else {
            MGClassicDarkSurface(content: content)
        }
    }
}
