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
                            decryptingView
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
                            decryptingView
                        }
    
                        @ViewBuilder
                        private var decryptingView: some View {
                            VStack(spacing: 10) {
                                if albumManager.viewerProgress.bytesTotal > 0 {
                                    ProgressView(value: albumManager.viewerProgress.percentComplete)
                                        .scaleEffect(1.2)
                                    Text(albumManager.viewerProgress.statusMessage.isEmpty ? "Decrypting…" : albumManager.viewerProgress.statusMessage)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    // Show byte counts and percent
                                    Text("
                                        \(ByteCountFormatter.string(fromByteCount: albumManager.viewerProgress.bytesProcessed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: albumManager.viewerProgress.bytesTotal, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text(albumManager.viewerProgress.statusMessage.isEmpty ? "Decrypting…" : albumManager.viewerProgress.statusMessage)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            albumManager.suspendIdleTimer(reason: .viewing)
        }
        .onDisappear {
            albumManager.resumeIdleTimer(reason: .viewing)
        }
    }

    private func loadFullImage() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                await MainActor.run {
                    albumManager.viewerProgress.start("Decrypting \(photo.filename)…")
                }
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
                albumManager.viewerProgress.finish()
            }
        }
    }

    private func loadVideo() {
        cancelDecryptTask()
        decryptTask = Task {
            do {
                // Start viewer-level progress. If we have a known file size, expose it
                await MainActor.run {
                    let total = photo.fileSize
                    albumManager.viewerProgress.start("Decrypting \(photo.filename)…", totalBytes: total)
                }

                let tempURL = try await albumManager.decryptPhotoToTemporaryURL(photo) { bytes in
                    // Update viewer progress with bytes processed
                    Task { @MainActor in
                        albumManager.viewerProgress.update(bytesProcessed: bytes)
                    }
                }
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
                    albumManager.viewerProgress.finish()
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

// decryptingPlaceholder removed — replaced by PhotoViewerSheet.decryptingView
