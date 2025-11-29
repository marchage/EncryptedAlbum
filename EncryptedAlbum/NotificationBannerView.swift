import SwiftUI

/// Reusable notification banner used across multiple screens. Reads `AlbumManager.hideNotification`.
struct NotificationBannerView: View {
    @EnvironmentObject var albumManager: AlbumManager
    // Interestingly this view intentionally mirrors the UI in `MainAlbumView` so we keep behaviour consistent.

    var body: some View {
        Group {
            if let note = albumManager.hideNotification {
                HStack(spacing: 12) {
                    Image(systemName: iconName(for: note.type))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(iconColor(for: note.type)))

                    Text(note.message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let validPhotos = note.photos?.filter({ p in
                        albumManager.hiddenPhotos.contains(where: { $0.id == p.id })
                    }), !validPhotos.isEmpty {
                        Button("Undo") {
                            Task { @MainActor in
                                do {
                                    try await albumManager.batchRestorePhotos(validPhotos, restoreToSourceAlbum: true)
                                } catch {
                                    AppLog.error("Undo restore failed: \(error.localizedDescription)")
                                }
                                withAnimation { albumManager.hideNotification = nil }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button("Open Photos App") {
                        #if os(macOS)
                        NSWorkspace.shared.open(URL(string: "photos://")!)
                        #endif
                        withAnimation { albumManager.hideNotification = nil }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(backgroundColor(for: note.type))
                .cornerRadius(8)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // persist for user-configured duration (default to 5s)
                        var timeout = UserDefaults.standard.double(forKey: "undoTimeoutSeconds")
                        if timeout <= 0 { timeout = 5.0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                        withAnimation { albumManager.hideNotification = nil }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func iconColor(for type: HideNotificationType) -> Color {
        switch type {
        case .success: return .green
        case .failure: return .red
        case .info: return .gray
        }
    }

    private func iconName(for type: HideNotificationType) -> String {
        switch type {
        case .success: return "checkmark.seal.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func backgroundColor(for type: HideNotificationType) -> Color {
        switch type {
        case .success: return Color.green.opacity(0.14)
        case .failure: return Color.red.opacity(0.14)
        case .info: return Color.gray.opacity(0.12)
        }
    }
}

// A tiny helper so the view can trigger the same restore code path — this keeps the undo behaviour compact.
fileprivate extension MainAlbumView {
    static func startRestorationTaskStatic(_ body: @escaping () -> Void) -> Bool {
        // For tests / quick reuse: always dispatch the body asynchronously and return true
        DispatchQueue.global(qos: .userInitiated).async { body() }
        return true
    }
}
