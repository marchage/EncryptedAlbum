import SwiftUI

struct PhotoThumbnailView: View {
    let photo: SecurePhoto
    let isSelected: Bool
    let privacyModeEnabled: Bool
    @EnvironmentObject var albumManager: AlbumManager
    @State private var thumbnailImage: Image?
    @State private var loadTask: Task<Void, Never>?
    @State private var failedToLoad: Bool = false
    @State private var isBlurRevealed: Bool = false

    /// Whether to blur this thumbnail based on privacy mode + setting + reveal state
    private var shouldBlur: Bool {
        privacyModeEnabled && albumManager.thumbnailPrivacy == "blur" && !isBlurRevealed
    }
    
    /// Whether to show hidden placeholder
    private var shouldHide: Bool {
        privacyModeEnabled && albumManager.thumbnailPrivacy == "hide"
    }

    var body: some View {
        // Use aspectRatio(1) for the image area so the grid's column width drives
        // the square image size. This avoids GeometryReader collapsing to zero height
        // and keeps a stable layout across different cells.
        let labelAreaHeight: CGFloat = 36

        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if shouldHide {
                        // Privacy ON + Hide setting = placeholder
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(systemName: "eye.slash.fill")
                                    .font(albumManager.compactLayoutEnabled ? .caption : .title3)
                                    .foregroundStyle(.secondary)
                            }
                    } else if let image = thumbnailImage {
                        // Show thumbnail (with optional blur when privacy ON + blur setting)
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: shouldBlur ? 20 : 0)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 2)
                            .overlay {
                                // Tap hint when blurred
                                if shouldBlur {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                if photo.mediaType == .video && !shouldBlur {
                                    HStack(spacing: 4) {
                                        Image(systemName: "play.fill")
                                            .font(.caption2)
                                        if let duration = photo.duration {
                                            Text(formatDuration(duration))
                                                .font(.caption2)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.6))
                                    .cornerRadius(4)
                                    .padding(6)
                                }
                            }
                            .onTapGesture {
                                if shouldBlur {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isBlurRevealed = true
                                    }
                                }
                            }
                    } else if failedToLoad {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                Image(
                                    systemName: photo.mediaType == .video
                                        ? "video.slash" : "exclamationmark.triangle.fill"
                                )
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                VStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Decrypting...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.accentColor).padding(3))
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            // Keep label area fixed height so rows align even when filenames wrap.
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)

                if let album = photo.sourceAlbum {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: labelAreaHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.horizontal, 0)
            .padding(.bottom, 0)
            .fixedSize(horizontal: false, vertical: true)
        }

        // note: moved label layout into the geometry-based layout above
        .onAppear {
            // Load thumbnail unless it's hidden (privacy ON + hide setting)
            if !shouldHide {
                loadThumbnail()
            }
        }
        .onChange(of: privacyModeEnabled) { newValue in
            // Privacy mode toggled - reload if now visible and not loaded
            if !shouldHide && thumbnailImage == nil {
                failedToLoad = false
                loadThumbnail()
            }
            // Reset blur reveal when entering privacy mode
            if newValue {
                isBlurRevealed = false
            }
        }
        .onChange(of: albumManager.thumbnailPrivacy) { newValue in
            // When switching away from "hide", force load thumbnails
            if newValue != "hide" && thumbnailImage == nil {
                failedToLoad = false
                loadThumbnail()
            }
            // Reset blur reveal state when switching to blur mode
            if newValue == "blur" && privacyModeEnabled {
                isBlurRevealed = false
            }
        }
        .onChange(of: albumManager.isUnlocked) { isUnlocked in
            if !isUnlocked {
                thumbnailImage = nil
                isBlurRevealed = false
            } else if !shouldHide {
                loadThumbnail()
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadThumbnail() {
        loadTask = Task {

            do {
                // Use a stable public wrapper to avoid intermittent visibility problems
                let data = try await AlbumManager.shared.loadThumbnailData(for: photo)

                if data.isEmpty {
                    AppLog.debugPrivate(
                        "Thumbnail data empty for photo id=\(photo.id), thumbnailPath=\(photo.thumbnailPath), encryptedThumb=\(photo.encryptedThumbnailPath ?? "nil")"
                    )
                    await MainActor.run {
                        failedToLoad = true
                    }
                    return
                }

                await MainActor.run {
                    if let image = Image(data: data) {
                        thumbnailImage = image
                    } else {
                        AppLog.debugPrivate("Failed to create Image from decrypted data for photo id=\(photo.id)")
                        failedToLoad = true
                    }
                }
            } catch {
                AppLog.error("Error decrypting thumbnail for photo id=\(photo.id): \(error.localizedDescription)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

}
