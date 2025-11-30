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
            Toggle("Strip metadata on export", isOn: Binding(get: { albumManager.stripMetadataOnExport }, set: { albumManager.stripMetadataOnExport = $0; albumManager.saveSettings() }))
                .disabled(albumManager.lockdownModeEnabled)

            Toggle("Password-protect exports", isOn: Binding(get: { albumManager.exportPasswordProtect }, set: { albumManager.exportPasswordProtect = $0; albumManager.saveSettings() }))
                .disabled(albumManager.lockdownModeEnabled)

            HStack {
                Text("Export expiry (days)")
                Spacer()
                Stepper("\(albumManager.exportExpiryDays)", value: Binding(get: { albumManager.exportExpiryDays }, set: { albumManager.exportExpiryDays = $0; albumManager.saveSettings() }), in: 1...365)
                    .labelsHidden()
            }
            .disabled(albumManager.lockdownModeEnabled)

            Toggle("Enable verbose logging", isOn: Binding(get: { albumManager.enableVerboseLogging }, set: { albumManager.enableVerboseLogging = $0; albumManager.saveSettings() }))

            HStack {
                Text("Passphrase minimum length")
                Spacer()
                Stepper("\(albumManager.passphraseMinLength)", value: Binding(get: { albumManager.passphraseMinLength }, set: { albumManager.passphraseMinLength = $0; albumManager.saveSettings() }), in: 6...64)
                    .labelsHidden()
            }

            Toggle("Telemetry (opt-in)", isOn: Binding(get: { albumManager.telemetryEnabled }, set: { albumManager.telemetryEnabled = $0; albumManager.saveSettings() }))

            Toggle("Auto-remove duplicates on import", isOn: Binding(get: { albumManager.autoRemoveDuplicatesOnImport }, set: { albumManager.autoRemoveDuplicatesOnImport = $0 }))

            Divider()

            // Screen sleep behaviour
            Toggle("Keep screen awake while unlocked", isOn: $storedKeepScreenAwakeWhileUnlocked)
                .onChange(of: storedKeepScreenAwakeWhileUnlocked) { _ in albumManager.saveSettings() }
            Toggle("Prevent system sleep during imports & viewing", isOn: $storedKeepScreenAwakeDuringSuspensions)
                .onChange(of: storedKeepScreenAwakeDuringSuspensions) { _ in albumManager.saveSettings() }

            Text("Automatically skip importing photos that are already in the album.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enable import notifications", isOn: Binding(get: { albumManager.enableImportNotifications }, set: { albumManager.enableImportNotifications = $0; albumManager.saveSettings() }))

            Divider()

            Text("Diagnostics").font(.headline)

            HStack {
                Text("Lockdown Mode")
                Spacer()
                Text(albumManager.lockdownModeEnabled ? "Enabled" : "Disabled")
                    .font(.caption2)
                    .foregroundStyle(albumManager.lockdownModeEnabled ? .red : .secondary)
            }

            Button { runHealthCheck() } label: {
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

            Divider()

            Text("Key Management").font(.headline)

            HStack {
                Button("Export Encrypted Key Backup") {
                    showBackupSheet = true
                }
                .disabled(albumManager.lockdownModeEnabled)
                .buttonStyle(.bordered)
                Spacer()
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
