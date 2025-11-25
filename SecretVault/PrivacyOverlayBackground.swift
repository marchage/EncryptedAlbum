import SwiftUI

/// Shared rainbow background used by every privacy cover in the app.
struct PrivacyOverlayBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.pink, .orange, .yellow, .green, .mint, .blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Color.black.opacity(0.45)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .ignoresSafeArea()
    }
}
