import SwiftUI

enum PrivacyBackgroundStyle: String, CaseIterable, Identifiable {
    case rainbow
    case dark
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .dark: return "Dark"
        }
    }
}

/// Shared background used by every privacy cover in the app.
struct PrivacyOverlayBackground: View {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .rainbow

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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
