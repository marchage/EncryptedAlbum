import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
    @AppStorage("privacyBackgroundStyle") private var privacyBackgroundStyle: PrivacyBackgroundStyle = .classic

    @State private var healthReport: SecurityHealthReport?
    @State private var isCheckingHealth = false
    @State private var healthCheckError: String?

    var body: some View {
        ZStack {
            PrivacyOverlayBackground(asBackground: true)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("General")
                    .font(.headline)

                HStack {
                    Text("Privacy Screen Style")
                    Spacer()
                    Picker("", selection: $privacyBackgroundStyle) {
                        ForEach(PrivacyBackgroundStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Divider()

                HStack {
                    Text("Undo banner timeout")
                    Spacer()
                    Text("\(Int(undoTimeoutSeconds))s")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $undoTimeoutSeconds, in: 2...20, step: 1)

                Divider()

                Text("Security")
                    .font(.headline)

                Toggle("Secure Deletion (Overwrite)", isOn: $albumManager.secureDeletionEnabled)
                Text("When enabled, deleted files are overwritten 3 times. This is slower but more secure. Disable for instant deletion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Diagnostics")
                    .font(.headline)

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

                Spacer()
            }
            .padding(20)
        }
        .frame(minWidth: 360, minHeight: 450)
        .onChange(of: albumManager.secureDeletionEnabled) { _ in
            albumManager.saveSettings()
        }
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch privacyBackgroundStyle {
        case .light, .bh90210:
            return .light
        case .dark, .rainbow, .mesh, .nightTown, .nineties, .webOne:
            return .dark
        case .classic, .glass:
            return nil // Follow system
        }
    }

    private func runHealthCheck() {
        isCheckingHealth = true
        healthReport = nil
        healthCheckError = nil

        Task {
            do {
                let report = try await albumManager.performSecurityHealthCheck()
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

struct HealthCheckRow: View {
    let label: String
    let passed: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .environmentObject(AlbumManager.shared)
    }
}
