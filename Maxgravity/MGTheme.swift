import SwiftUI
import UIKit

#if canImport(LiquidGlassKit)
import LiquidGlassKit
#endif

enum MGTheme {
    static let background = Color.black
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let elevatedSurface = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let denseSurface = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let border = Color.white.opacity(0.09)
    static let strongBorder = Color.white.opacity(0.16)
    static let primaryText = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.42)
    static let success = Color(red: 0.32, green: 0.84, blue: 0.46)
    static let warning = Color(red: 0.94, green: 0.73, blue: 0.29)
    static let danger = Color(red: 0.96, green: 0.37, blue: 0.34)
    static let shadow = Color.black.opacity(0.38)
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.49, blue: 0.22),
            Color(red: 0.95, green: 0.28, blue: 0.47),
            Color(red: 0.64, green: 0.29, blue: 0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum MGHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

extension DateFormatter {
    static let mgTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let mgRelative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
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

    func mgReadableSurface(cornerRadius: CGFloat = 26) -> some View {
        modifier(MGReadableSurfaceModifier(cornerRadius: cornerRadius))
    }

    func mgInteractiveGlass(cornerRadius: CGFloat = 22) -> some View {
        modifier(MGInteractiveGlassModifier(cornerRadius: cornerRadius))
    }
}

private struct MGReadableSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.denseSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.border, lineWidth: 1)
            )
            .shadow(color: MGTheme.shadow, radius: 18, y: 8)
    }
}

private struct MGInteractiveGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(MGTheme.elevatedSurface)
                } else {
                    glassBackground
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.strongBorder, lineWidth: 1)
            }
            .shadow(color: MGTheme.shadow, radius: 20, y: 10)
    }

    @ViewBuilder
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.elevatedSurface.opacity(0.55))
            }
#if canImport(LiquidGlassKit)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
#endif
    }
}

struct MGPressableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 22
    var foreground: Color = MGTheme.primaryText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct MGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

struct MGSecondaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MGTheme.primaryText)
            .frame(minWidth: 44, minHeight: 44)
            .padding(2)
            .mgInteractiveGlass(cornerRadius: 18)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct MGAppBackground: View {
    var body: some View {
        ZStack {
            MGTheme.background
            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.clear,
                    MGTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

struct MGClassicDarkSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .mgReadableSurface()
    }
}

struct MGLiquidGlassSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .mgInteractiveGlass()
    }
}

struct MGAdaptiveSurface<Content: View>: View {
    var prefersGlass: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        if prefersGlass {
            MGLiquidGlassSurface { content }
        } else {
            MGClassicDarkSurface { content }
        }
    }
}
