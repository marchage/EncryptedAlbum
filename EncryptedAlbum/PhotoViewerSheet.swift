import AVKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif
#if os(iOS)
    import UIKit
#endif

struct PhotoViewerSheet: View {
    let photo: SecurePhoto
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var albumManager: AlbumManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var fullImage: PlatformImage?
    @State private var videoURL: URL?
    @State private var decryptTask: Task<Void, Never>?
    @State private var failedToLoad = false
    @State private var isMaximized: Bool = false

    var body: some View {
        SecureWrapper {
            ZStack {
                PrivacyOverlayBackground(asBackground: true)

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text(photo.filename)
                                .font(.headline)
                            HStack {
                                if let album = photo.sourceAlbum {
                                    Text("From: \(album)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if photo.mediaType == .video, let duration = photo.duration {
                                    Text("• \(formatDuration(duration))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            #if os(iOS)
                                .padding(.top, -6)
                            #endif
                        }

                        Spacer()

                        Button {
                            cancelDecryptTask()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    // Media content
                    if photo.mediaType == .video {
                        if let url = videoURL {
                            ZStack(alignment: .topTrailing) {
                                CustomVideoPlayer(url: url)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                // Maximize button for iOS to present a full-screen player
                                #if os(iOS)
                                Button(action: { isMaximized = true }) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                .padding(12)
                                #endif
                            }
                            #if os(iOS)
                                .fullScreenCover(isPresented: $isMaximized) {
                                    CustomVideoPlayer(url: url)
                                        .edgesIgnoringSafeArea(.all)
                                }
                            #endif
                        } else {
                            decryptingPlaceholder
                        }
                    } else {
                        if let image = fullImage {
                            #if os(macOS)
                                ZoomableImageView(image: image)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            #else
                                ZoomableImageView(image: image)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            #endif
                        } else if failedToLoad {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Failed to load image")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            decryptingPlaceholder
                        }
                    }
                }
                #if os(macOS)
                    .frame(minWidth: 800, minHeight: 600)
                #endif
                .onAppear {
                    if photo.mediaType == .video {
                        loadVideo()
                    } else {
                        loadFullImage()
                    }
                }
                .onDisappear {
                    cancelDecryptTask()
                    cleanupVideo()
                }
                .onChange(of: scenePhase) { newPhase in
                    guard newPhase == .active else {
                        dismissViewer()
                        return
                    }
                }
            }
        }
        .onAppear {
            albumManager.suspendIdleTimer()
        }
        .onDisappear {
            albumManager.resumeIdleTimer()
        }
    }

    private func loadFullImage() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                let decryptedData = try await albumManager.decryptPhoto(photo)
                try Task.checkCancellation()

                #if os(macOS)
                    if let image = NSImage(data: decryptedData) {
                        await MainActor.run {
                            fullImage = image
                        }
                    } else {
                        await MainActor.run { failedToLoad = true }
                    }
                #else
                    if let image = UIImage(data: decryptedData) {
                        await MainActor.run {
                            fullImage = image
                        }
                    } else {
                        await MainActor.run { failedToLoad = true }
                    }
                #endif
            } catch is CancellationError {
                // Cancellation is expected when the viewer is dismissed mid-decrypt
            } catch {
                AppLog.error("Failed to decrypt photo: \(error.localizedDescription)")
            }
            await MainActor.run {
                decryptTask = nil
            }
        }
    }

    private func loadVideo() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                let tempURL = try await albumManager.decryptPhotoToTemporaryURL(photo)
                try Task.checkCancellation()
                await MainActor.run {
                    self.videoURL = tempURL
                }
            } catch is CancellationError {
                // Expected when the viewer is dismissed; partial temp files are cleaned up downstream
            } catch {
                AppLog.error("Failed to decrypt video: \(error.localizedDescription)")
            }
            await MainActor.run {
                decryptTask = nil
            }
        }
    }

    private func cleanupVideo() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        videoURL = nil
    }

    private func cancelDecryptTask() {
        decryptTask?.cancel()
        decryptTask = nil
    }

    private func dismissViewer() {
        cancelDecryptTask()
        cleanupVideo()
        dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private var decryptingPlaceholder: some View {
    VStack(spacing: 10) {
        ProgressView()
            .scaleEffect(1.2)
        Text("Decrypting...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
