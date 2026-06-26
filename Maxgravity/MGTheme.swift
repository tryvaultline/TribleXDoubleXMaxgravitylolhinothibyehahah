import SwiftUI
import UIKit

#if canImport(LiquidGlassKit)
import LiquidGlassKit

struct MGLiquidGlassRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> LiquidGlassEffectView {
        let view = LiquidGlassEffectView(effect: LiquidGlassEffect(style: .regular))
        return view
    }
    
    func updateUIView(_ uiView: LiquidGlassEffectView, context: Context) {}
}

struct MGLiquidLensRepresentable: UIViewRepresentable {
    var isLifted: Bool
    
    func makeUIView(context: Context) -> LiquidLensView {
        let view = LiquidLensView()
        return view
    }
    
    func updateUIView(_ uiView: LiquidLensView, context: Context) {
        // isLifted is a private/internal property of LiquidLensView in LiquidGlassKit
    }
}
#endif

enum MGTheme {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.051)
    static let backgroundSecondary = Color(red: 0.040, green: 0.048, blue: 0.068)
    static let surface = Color(red: 0.085, green: 0.097, blue: 0.126)
    static let elevatedSurface = Color(red: 0.105, green: 0.118, blue: 0.152)
    static let denseSurface = Color(red: 0.072, green: 0.083, blue: 0.109)
    static let insetSurface = Color(red: 0.118, green: 0.131, blue: 0.166)
    static let border = Color.white.opacity(0.09)
    static let strongBorder = Color.white.opacity(0.16)
    static let primaryText = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.42)
    static let success = Color(red: 0.32, green: 0.84, blue: 0.46)
    static let warning = Color(red: 0.94, green: 0.73, blue: 0.29)
    static let danger = Color(red: 0.96, green: 0.37, blue: 0.34)
    static let shadow = Color.black.opacity(0.38)
    static let scrim = Color.black.opacity(0.34)
    static let brandAmbient = Color(red: 0.96, green: 0.46, blue: 0.23)
    static let workspaceAmbient = Color(red: 0.30, green: 0.50, blue: 0.88)
    static let activityAmbient = Color(red: 0.58, green: 0.72, blue: 0.94)
    static let settingsAmbient = Color(red: 0.74, green: 0.78, blue: 0.88)
    static let warningAmbient = Color(red: 0.88, green: 0.62, blue: 0.25)
    static let dangerAmbient = Color(red: 0.90, green: 0.33, blue: 0.31)
    static let backgroundUIColor = UIColor(red: 0.027, green: 0.035, blue: 0.051, alpha: 1)
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

enum MGBackdropTone {
    case neutral
    case brand
    case activity
    case workspace
    case settings
    case warning
    case danger

    var primaryGlow: Color {
        switch self {
        case .neutral: MGTheme.settingsAmbient
        case .brand: MGTheme.brandAmbient
        case .activity: MGTheme.activityAmbient
        case .workspace: MGTheme.workspaceAmbient
        case .settings: MGTheme.settingsAmbient
        case .warning: MGTheme.warningAmbient
        case .danger: MGTheme.dangerAmbient
        }
    }

    var secondaryGlow: Color {
        switch self {
        case .neutral: MGTheme.workspaceAmbient
        case .brand: MGTheme.settingsAmbient
        case .activity: MGTheme.brandAmbient
        case .workspace: MGTheme.activityAmbient
        case .settings: MGTheme.brandAmbient
        case .warning: MGTheme.brandAmbient
        case .danger: MGTheme.warningAmbient
        }
    }
}

extension MGAppSection {
    var backdropTone: MGBackdropTone {
        switch self {
        case .spaces: .brand
        case .activity: .activity
        case .workspace: .workspace
        case .settings: .settings
        }
    }
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

extension JSONDecoder {
    static let mgDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateStr) {
                return date
            }
            
            let formatter2 = ISO8601DateFormatter()
            formatter2.formatOptions = [.withInternetDateTime]
            if let date = formatter2.date(from: dateStr) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateStr)")
        }
        return decoder
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

    func mgNavigationChrome() -> some View {
        modifier(MGNavigationChromeModifier())
    }
}

private struct MGReadableSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                MGTheme.elevatedSurface.opacity(0.98),
                                MGTheme.denseSurface.opacity(0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.05), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(20, cornerRadius * 0.85))
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
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
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.035),
                                    Color.white.opacity(0.01)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        } else {
            #if canImport(LiquidGlassKit)
            MGLiquidGlassRepresentable()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    MGTheme.elevatedSurface.opacity(0.28),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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
                        .frame(height: max(28, cornerRadius))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            #else
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.06),
                                    MGTheme.elevatedSurface.opacity(0.26),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: max(28, cornerRadius))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            #endif
        }
    }
}

private struct MGNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct MGPressableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 22
    var foreground: Color = MGTheme.primaryText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct MGPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.94, green: 0.93, blue: 0.90))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.62), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.18), radius: configuration.isPressed ? 5 : 12, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.945 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.30, dampingFraction: 0.58), value: configuration.isPressed)
    }
}

struct MGSecondaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MGTheme.primaryText)
            .frame(minWidth: 44, minHeight: 44)
            .padding(2)
            .mgInteractiveGlass(cornerRadius: 18)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.52), value: configuration.isPressed)
    }
}

struct MGAppBackground: View {
    var tone: MGBackdropTone = .neutral

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [
                        MGTheme.backgroundSecondary,
                        MGTheme.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ambientGlow(
                    color: tone.primaryGlow,
                    opacity: 0.13,
                    center: UnitPoint(x: 0.18, y: 0.16),
                    radius: max(size.width, size.height) * 0.48
                )

                ambientGlow(
                    color: tone.secondaryGlow,
                    opacity: 0.08,
                    center: UnitPoint(x: 0.84, y: 0.28),
                    radius: max(size.width, size.height) * 0.34
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.03),
                        Color.clear,
                        Color.black.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private func ambientGlow(color: Color, opacity: Double, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [
                color.opacity(opacity),
                color.opacity(opacity * 0.45),
                Color.clear
            ],
            center: center,
            startRadius: radius * 0.02,
            endRadius: radius
        )
        .blur(radius: 28)
    }
}

struct MGGlassCluster<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
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
