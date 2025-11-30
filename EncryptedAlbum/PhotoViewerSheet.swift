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
    @State private var showDecryptErrorAlert = false
    @State private var decryptErrorMessage: String? = nil
    @State private var isMaximized: Bool = false
    
    var body: some View {
#if os(macOS)
        viewerContent.frame(minWidth: 800, minHeight: 600)
#else
        viewerContent
#endif
    }
    
    private var viewerContent: some View {
        return SecureWrapper {
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
                    }
                }
                
            }
            .onAppear {
                // start viewer behavior and suspend idle timer
                albumManager.suspendIdleTimer(reason: .viewing)
                if photo.mediaType == .video {
                    loadVideo()
                } else {
                    loadFullImage()
                }
            }
            .onDisappear {
                // ensure in-flight decrypts are cancelled and timer resumed when leaving
                cancelDecryptTask()
                cleanupVideo()
                albumManager.resumeIdleTimer(reason: .viewing)
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else {
                    dismissViewer()
                    return
                }
            }
            .alert("Failed to decrypt media", isPresented: $showDecryptErrorAlert, actions: {
                Button("Retry") {
                    // Retry current operation
                    decryptErrorMessage = nil
                    showDecryptErrorAlert = false
                    if photo.mediaType == .video {
                        loadVideo()
                    } else {
                        loadFullImage()
                    }
                }
                Button("Dismiss", role: .cancel) {
                    decryptErrorMessage = nil
                    showDecryptErrorAlert = false
                    cancelDecryptTask()
                }
                Button("Copy details") {
                    if let message = decryptErrorMessage {
#if os(iOS)
                        UIPasteboard.general.string = message
#else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
#endif
                    }
                }
            }, message: {
                if let msg = decryptErrorMessage {
                    Text(msg)
                } else {
                    Text("An unknown error occurred while decrypting the media.")
                }
            })
        }
        
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

                Text("\(ByteCountFormatter.string(fromByteCount: albumManager.viewerProgress.bytesProcessed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: albumManager.viewerProgress.bytesTotal, countStyle: .file))")
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

    func loadFullImage() {
            cancelDecryptTask()
            let manager: AlbumManager = albumManager
            decryptTask = Task {
                do {
                    await MainActor.run {
                        manager.viewerProgress.start("Decrypting \(photo.filename)…")
                    }
                    let decryptedData = try await manager.decryptPhoto(photo)
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
                    await MainActor.run {
                        decryptErrorMessage = error.localizedDescription
                        showDecryptErrorAlert = true
                    }
                }
                    await MainActor.run {
                        decryptTask = nil
                        manager.viewerProgress.finish()
                    }
            }
        }
        
        func loadVideo() {
            cancelDecryptTask()
            let manager: AlbumManager = albumManager
            decryptTask = Task {
                do {
                    // Start viewer-level progress. If we have a known file size, expose it
                    await MainActor.run {
                        let total = photo.fileSize
                        manager.viewerProgress.start("Decrypting \(photo.filename)…", totalBytes: total)
                    }
                    
                    let tempURL = try await manager.decryptPhotoToTemporaryURL(photo) { bytes in
                        // Update viewer progress with bytes processed
                        Task { @MainActor in
                            manager.viewerProgress.update(bytesProcessed: bytes)
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
                    await MainActor.run {
                        decryptErrorMessage = error.localizedDescription
                        showDecryptErrorAlert = true
                    }
                }
                    await MainActor.run {
                        decryptTask = nil
                        manager.viewerProgress.finish()
                    }
            }
        }
        
    func cleanupVideo() {
        if let url = videoURL {
            _ = try? FileManager.default.removeItem(at: url)
        }
        videoURL = nil
    }
    func cancelDecryptTask() {
        decryptTask?.cancel()
        decryptTask = nil
    }

    func dismissViewer() {
        cancelDecryptTask()
        cleanupVideo()
        dismiss()
    }

    func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // decryptingPlaceholder removed — replaced by PhotoViewerSheet.decryptingView
    
