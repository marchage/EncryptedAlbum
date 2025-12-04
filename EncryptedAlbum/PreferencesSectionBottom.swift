import SwiftUI

struct PreferencesSectionBottom: View {
    @EnvironmentObject var albumManager: AlbumManager

    @Binding var showBackupSheet: Bool

    @AppStorage("keepScreenAwakeWhileUnlocked") private var storedKeepScreenAwakeWhileUnlocked: Bool = false
    @AppStorage("keepScreenAwakeDuringSuspensions") private var storedKeepScreenAwakeDuringSuspensions: Bool = true

    @State private var isCheckingHealth = false
    @State private var healthReport: SecurityHealthReport?
    @State private var healthCheckError: String?

    var body: some View {
        Group {
            HStack {
                Text("Strip metadata on export")
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.stripMetadataOnExport },
                        set: {
                            albumManager.stripMetadataOnExport = $0
                            albumManager.saveSettings()
                        })
                )
                .labelsHidden()
            }
            .disabled(albumManager.lockdownModeEnabled)

            Text("Removes EXIF data (location, camera info) from exported photos for privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Telemetry (opt-in)")
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.telemetryEnabled },
                        set: {
                            albumManager.telemetryEnabled = $0
                            albumManager.saveSettings()
                        })
                )
                .labelsHidden()
            }

            Text("Anonymous usage data to help improve the app. No personal data is collected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Skip duplicate imports")
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.autoRemoveDuplicatesOnImport },
                        set: { albumManager.autoRemoveDuplicatesOnImport = $0 })
                )
                .labelsHidden()
            }

            Text("Automatically skip importing photos that are already in the album (detected by file hash).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Screen sleep behaviour
            HStack {
                Text("Keep screen awake while unlocked")
                Spacer()
                Toggle("", isOn: $storedKeepScreenAwakeWhileUnlocked)
                    .labelsHidden()
                    .onChange(of: storedKeepScreenAwakeWhileUnlocked) { _ in albumManager.saveSettings() }
            }

            HStack {
                Text("Prevent sleep during imports & viewing")
                Spacer()
                Toggle("", isOn: $storedKeepScreenAwakeDuringSuspensions)
                    .labelsHidden()
                    .onChange(of: storedKeepScreenAwakeDuringSuspensions) { _ in albumManager.saveSettings() }
            }

            HStack {
                Text("Import notifications")
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.enableImportNotifications },
                        set: {
                            albumManager.enableImportNotifications = $0
                            albumManager.saveSettings()
                        })
                )
                .labelsHidden()
            }

            Text("Shows an in-app banner when photos finish importing. This is not a system notification — you need to have the app open to see it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Diagnostics").font(.headline)

            Button {
                runHealthCheck()
            } label: {
                if isCheckingHealth {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Run Security Health Check")
                }
            }
            .disabled(isCheckingHealth)

            if let report = healthReport {
                VStack(alignment: .leading, spacing: 8) {
                    HealthCheckRow(label: "Random Generation (Entropy)", passed: report.randomGenerationHealthy)
                    HealthCheckRow(label: "Crypto Operations", passed: report.cryptoOperationsHealthy)
                    HealthCheckRow(label: "File System Security", passed: report.fileSystemSecure)
                    HealthCheckRow(label: "Memory Security", passed: report.memorySecurityHealthy)
                    Divider()
                    HStack {
                        Text("Overall Status:")
                        Spacer()
                        Text(report.overallHealthy ? "PASSED" : "FAILED")
                            .fontWeight(.bold)
                            .foregroundStyle(report.overallHealthy ? .green : .red)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }

            if let error = healthCheckError {
                Text("Check failed: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

        }
    }

    private func runHealthCheck() {
        isCheckingHealth = true
        healthReport = nil
        healthCheckError = nil

        Task {
            do {
                let report = try await AlbumManager.shared.performSecurityHealthCheck()
                await MainActor.run {
                    self.healthReport = report
                    self.isCheckingHealth = false
                }
            } catch {
                await MainActor.run {
                    self.healthCheckError = error.localizedDescription
                    self.isCheckingHealth = false
                }
            }
        }
    }
}
