import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// Non-blocking progress banner for long-running operations like exports, imports, restoration.
/// Shows at the top of the screen and allows continued interaction with the app.
struct ProgressBannerView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @ObservedObject var directImportProgress: DirectImportProgress

    var body: some View {
        VStack(spacing: 8) {
            // Export progress banner
            if albumManager.exportProgress.isExporting {
                ProgressBanner(
                    title: "Exporting",
                    icon: "square.and.arrow.up",
                    iconColor: .blue,
                    statusMessage: albumManager.exportProgress.statusMessage,
                    detailMessage: albumManager.exportProgress.detailMessage,
                    itemsProcessed: albumManager.exportProgress.itemsProcessed,
                    totalItems: albumManager.exportProgress.itemsTotal,
                    bytesProcessed: albumManager.exportProgress.bytesProcessed,
                    totalBytes: albumManager.exportProgress.bytesTotal,
                    cancelRequested: albumManager.exportProgress.cancelRequested,
                    onCancel: { albumManager.cancelExport() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Direct import progress banner (file/photos picker)
            if directImportProgress.isImporting {
                ProgressBanner(
                    title: "Importing",
                    icon: "square.and.arrow.down",
                    iconColor: .green,
                    statusMessage: directImportProgress.statusMessage,
                    detailMessage: directImportProgress.detailMessage,
                    itemsProcessed: directImportProgress.itemsProcessed,
                    totalItems: directImportProgress.itemsTotal,
                    bytesProcessed: directImportProgress.bytesProcessed,
                    totalBytes: directImportProgress.bytesTotal,
                    cancelRequested: directImportProgress.cancelRequested,
                    onCancel: { directImportProgress.cancelRequested = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Background import progress banner (share extension)
            if albumManager.importProgress.isImporting {
                ProgressBanner(
                    title: "Importing",
                    icon: "square.and.arrow.down",
                    iconColor: .green,
                    statusMessage: albumManager.importProgress.statusMessage,
                    detailMessage: albumManager.importProgress.detailMessage,
                    itemsProcessed: albumManager.importProgress.processedItems,
                    totalItems: albumManager.importProgress.totalItems,
                    bytesProcessed: albumManager.importProgress.currentBytesProcessed,
                    totalBytes: albumManager.importProgress.currentBytesTotal,
                    cancelRequested: albumManager.importProgress.cancelRequested,
                    onCancel: { albumManager.importProgress.cancelRequested = true }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Restoration progress banner
            if albumManager.restorationProgress.isRestoring {
                ProgressBanner(
                    title: "Restoring",
                    icon: "arrow.uturn.backward",
                    iconColor: .orange,
                    statusMessage: albumManager.restorationProgress.statusMessage,
                    detailMessage: albumManager.restorationProgress.detailMessage,
                    itemsProcessed: albumManager.restorationProgress.processedItems,
                    totalItems: albumManager.restorationProgress.totalItems,
                    bytesProcessed: albumManager.restorationProgress.currentBytesProcessed,
                    totalBytes: albumManager.restorationProgress.currentBytesTotal,
                    cancelRequested: albumManager.restorationProgress.cancelRequested,
                    onCancel: {
                        albumManager.restorationProgress.cancelRequested = true
                        albumManager.restorationProgress.statusMessage = "Canceling…"
                    },
                    successCount: albumManager.restorationProgress.successItems,
                    failureCount: albumManager.restorationProgress.failedItems
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: albumManager.exportProgress.isExporting)
        .animation(.easeInOut(duration: 0.25), value: directImportProgress.isImporting)
        .animation(.easeInOut(duration: 0.25), value: albumManager.importProgress.isImporting)
        .animation(.easeInOut(duration: 0.25), value: albumManager.restorationProgress.isRestoring)
    }
}

/// Individual progress banner component
private struct ProgressBanner: View {
    let title: String
    let icon: String
    let iconColor: Color
    let statusMessage: String
    let detailMessage: String
    let itemsProcessed: Int
    let totalItems: Int
    let bytesProcessed: Int64
    let totalBytes: Int64
    let cancelRequested: Bool
    let onCancel: () -> Void
    var successCount: Int = 0
    var failureCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(iconColor))

            // Progress info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if totalItems > 0 {
                        Text("(\(itemsProcessed)/\(totalItems))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if successCount > 0 || failureCount > 0 {
                        Text("• \(successCount)✓ \(failureCount)✗")
                            .font(.caption2)
                            .foregroundStyle(failureCount > 0 ? .orange : .secondary)
                    }
                }

                // Compact progress bar
                if totalItems > 0 || totalBytes > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.15))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(iconColor)
                                .frame(width: geometry.size.width * progressFraction, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Bytes processed (compact)
            if totalBytes > 0 {
                Text(formattedProgress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            // Cancel button
            if cancelRequested {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: bannerMaxWidth)  // Compact toast width for bottom-right corner
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private var progressFraction: Double {
        if totalBytes > 0 {
            return min(1.0, Double(bytesProcessed) / Double(max(totalBytes, 1)))
        }
        if totalItems > 0 {
            return min(1.0, Double(itemsProcessed) / Double(max(totalItems, 1)))
        }
        return 0
    }

    private var formattedProgress: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        if totalBytes > 0 {
            return "\(formatter.string(fromByteCount: bytesProcessed))/\(formatter.string(fromByteCount: totalBytes))"
        } else if bytesProcessed > 0 {
            return formatter.string(fromByteCount: bytesProcessed)
        }
        return ""
    }

    #if os(iOS)
        private var bannerMaxWidth: CGFloat {
            // Fit within the available screen width while keeping a comfortable maximum.
            // The 0.9 factor leaves room for padding so it won't cover adjacent chips/badges.
            let screenWidth = UIScreen.main.bounds.width
            return min(max(screenWidth * 0.9, 220), 320)
        }
    #else
        private var bannerMaxWidth: CGFloat { 320 }
    #endif
}
