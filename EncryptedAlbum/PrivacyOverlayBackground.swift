import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PrivacyBackgroundStyle: String, CaseIterable, Identifiable {
    case rainbow
    case dark
    case mesh
    case classic
    case glass
    case light
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .dark: return "Dark"
        case .mesh: return "Mesh"
        case .classic: return "Classic"
        case .glass: return "Glass"
        case .light: return "Light"
        }
    }
}

/// Shared background used by every privacy cover in the app.
struct PrivacyOverlayBackground: View {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .rainbow
    
    /// If true, this view is being used as the main app background (behind content).
    /// If false, it is being used as a privacy overlay (obscuring content).
    var asBackground: Bool = false

    var body: some View {
        Group {
            switch style {
            case .rainbow:
                LinearGradient(
                    colors: [.pink, .orange, .yellow, .green, .mint, .blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Color.black.opacity(0.45)
                )
            case .dark:
                LinearGradient(
                    colors: [Color(white: 0.12), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .mesh:
                ZStack {
                    Color.black
                    
                    // Blue/Purple orb
                    RadialGradient(
                        colors: [.blue.opacity(0.6), .clear],
                        center: .topLeading,
                        startRadius: 100,
                        endRadius: 600
                    )
                    
                    // Pink/Red orb
                    RadialGradient(
                        colors: [.pink.opacity(0.5), .clear],
                        center: .bottomTrailing,
                        startRadius: 100,
                        endRadius: 500
                    )
                    
                    // Cyan/Mint orb
                    RadialGradient(
                        colors: [.cyan.opacity(0.4), .clear],
                        center: .bottomLeading,
                        startRadius: 50,
                        endRadius: 400
                    )
                    
                    // Orange orb
                    RadialGradient(
                        colors: [.orange.opacity(0.3), .clear],
                        center: .topTrailing,
                        startRadius: 50,
                        endRadius: 400
                    )
                }
                .blur(radius: 60)
            case .classic:
                #if os(macOS)
                if asBackground {
                    Color.clear // Allow system window background to show
                } else {
                    WindowBackgroundView()
                }
                #else
                Color(uiColor: .systemBackground)
                #endif
            case .glass:
                ZStack {
                    // A subtle gradient to give it some "body" so it's not just the system background color
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.1),
                            Color.purple.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    if asBackground {
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    } else {
                        #if os(macOS)
                        Rectangle().fill(.regularMaterial)
                        #else
                        Rectangle().fill(.regularMaterial)
                        #endif
                    }
                    
                    // Shine/Reflection
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .light:
                Color.white
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

#if os(macOS)
private struct WindowBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}
#endif

struct PrivacyCardBackground: ViewModifier {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .rainbow
    
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    switch style {
                    case .glass:
                        ZStack {
                            Color.white.opacity(0.05)
                            #if os(macOS)
                            Rectangle().fill(.ultraThinMaterial)
                            #else
                            Rectangle().fill(.ultraThinMaterial)
                            #endif
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    case .dark:
                        Color.black.opacity(0.6)
                    case .light:
                        Color.white.opacity(0.8)
                    case .classic:
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    default:
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style == .glass ? Color.white.opacity(0.3) : (style == .light ? Color.black.opacity(0.1) : Color.clear),
                        lineWidth: 1
                    )
            )
            .shadow(color: style == .glass ? Color.black.opacity(0.1) : (style == .light ? Color.black.opacity(0.05) : Color.clear), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func privacyCardStyle() -> some View {
        modifier(PrivacyCardBackground())
    }
}
