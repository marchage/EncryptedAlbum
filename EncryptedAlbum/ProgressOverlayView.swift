import SwiftUI

struct ProgressOverlayView: View {
    let title: String
    let statusMessage: String
    let detailMessage: String

    let itemsProcessed: Int
    let totalItems: Int

    let bytesProcessed: Int64
    let totalBytes: Int64

    let cancelRequested: Bool
    let onCancel: () -> Void

    // Optional: Success/Failure counts for restoration
    var successCount: Int = 0
    var failureCount: Int = 0

    // Optional: Whether the app is active (affects display of bytes)
    var isAppActive: Bool = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Items Progress
                if totalItems > 0 {
                    ProgressView(value: Double(itemsProcessed), total: Double(max(totalItems, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                }

                // Bytes Progress
                if totalBytes > 0 {
                    ProgressView(
                        value: Double(bytesProcessed),
                        total: Double(max(totalBytes, 1))
                    )
                    .progressViewStyle(.linear)
                    .frame(maxWidth: UIConstants.progressCardWidth)

                    if isAppActive {
                        Text("\(formattedBytes(bytesProcessed)) of \(formattedBytes(totalBytes))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        let percent = Double(bytesProcessed) / Double(max(totalBytes, 1))
                        Text(String(format: "%.0f%%", percent * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if bytesProcessed > 0 {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: UIConstants.progressCardWidth)
                    Text("\(formattedBytes(bytesProcessed)) processed…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // Only show "Preparing..." if we don't have items progress showing activity
                    if totalItems == 0 {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .frame(maxWidth: UIConstants.progressCardWidth)
                        Text("Preparing...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(statusMessage.isEmpty ? title : statusMessage)
                    .font(.headline)

                if totalItems > 0 {
                    Text("\(itemsProcessed) of \(totalItems)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if successCount > 0 || failureCount > 0 {
                    Text("\(successCount) restored • \(failureCount) failed")
                        .font(.caption2)
                        .foregroundStyle(failureCount > 0 ? Color.orange : .secondary)
                }

                if !detailMessage.isEmpty && isAppActive {
                    Text(detailMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if cancelRequested {
                    Text("Cancel requested… finishing current item")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(cancelRequested)
            }
            .padding(24)
            .frame(maxWidth: UIConstants.progressCardWidth)
            .background(.ultraThickMaterial)
            .cornerRadius(16)
            .shadow(radius: 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Progress overlay")
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private func formattedBytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [statusMessage.isEmpty ? title : statusMessage]

        if totalItems > 0 {
            parts.append("\(itemsProcessed) of \(totalItems) items")
        }

        if totalBytes > 0 {
            parts.append(
                "\(formattedBytes(bytesProcessed)) of \(formattedBytes(totalBytes)) processed"
            )
        } else if bytesProcessed > 0 {
            parts.append("\(formattedBytes(bytesProcessed)) processed")
        }

        if successCount > 0 || failureCount > 0 {
            parts.append("\(successCount) restored, \(failureCount) failed")
        }

        if cancelRequested {
            parts.append("Cancellation requested")
        }

        if !detailMessage.isEmpty {
            parts.append(detailMessage)
        }

        return parts.joined(separator: ", ")
    }
}
