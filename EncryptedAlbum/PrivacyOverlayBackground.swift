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
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .dark: return "Dark"
        case .mesh: return "Mesh"
        case .classic: return "Classic"
        case .glass: return "Glass"
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
                if asBackground {
                    Color.clear // Allow system window background to show
                } else {
                    #if os(macOS)
                    Color(nsColor: .windowBackgroundColor)
                    #else
                    Color(uiColor: .systemBackground)
                    #endif
                }
            case .glass:
                ZStack {
                    if asBackground {
                        // For the app background, we use a subtle material
                        // This requires the window to be configured as transparent to see the desktop,
                        // but even without that, it gives a nice native matte look.
                        Rectangle().fill(.ultraThinMaterial)
                    } else {
                        // For privacy overlay, we use a thicker material to obscure content
                        Rectangle().fill(.regularMaterial)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
