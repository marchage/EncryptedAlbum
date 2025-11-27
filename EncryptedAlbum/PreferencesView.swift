import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
    @AppStorage("privacyBackgroundStyle") private var privacyBackgroundStyle: PrivacyBackgroundStyle = .classic
    @AppStorage("requireForegroundReauthentication") private var requireForegroundReauthentication: Bool = true
    @AppStorage("stealthModeEnabled") private var stealthModeEnabled: Bool = false
    @AppStorage("decoyPasswordHash") private var decoyPasswordHash: String = ""

    @State private var healthReport: SecurityHealthReport?
    @State private var isCheckingHealth = false
    @State private var healthCheckError: String?

    @State private var showDecoyPasswordSheet = false
    @State private var decoyPasswordInput = ""
    @State private var decoyPasswordConfirm = ""
    @State private var decoyPasswordError: String?

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(iOS)
        NavigationView {
            content
        }
        .navigationViewStyle(.stack)
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            PrivacyOverlayBackground(asBackground: true)

            if albumManager.isUnlocked {
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

                    Toggle("Require Re-authentication", isOn: $requireForegroundReauthentication)
                    Text("When enabled, the album will lock when the app goes to the background or is inactive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Secure Deletion (Overwrite)", isOn: $albumManager.secureDeletionEnabled)
                    Text(
                        "When enabled, deleted files are overwritten 3 times. This is slower but more secure. Disable for instant deletion."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    Text("Stealth Features")
                        .font(.headline)

                    Toggle("Stealth Mode (Fake Crash)", isOn: $stealthModeEnabled)
                    Text(
                        "When enabled, the app will appear to crash or freeze on launch. Long press the screen for 1.5 seconds to unlock."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Decoy Password")
                        Spacer()
                        if !decoyPasswordHash.isEmpty {
                            Button("Remove") {
                                albumManager.clearDecoyPassword()
                                // Force update since AppStorage might not sync immediately with direct UserDefaults modification in manager
                                decoyPasswordHash = ""
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)

                            Button("Change") {
                                decoyPasswordInput = ""
                                decoyPasswordConfirm = ""
                                decoyPasswordError = nil
                                showDecoyPasswordSheet = true
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Set Decoy Password") {
                                decoyPasswordInput = ""
                                decoyPasswordConfirm = ""
                                decoyPasswordError = nil
                                showDecoyPasswordSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("A decoy password unlocks an empty album. Use this if forced to unlock your device.")
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
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Settings Locked")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Please unlock the album to access settings.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(minWidth: 360, minHeight: 450)
        .navigationTitle("Settings")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        #endif
        .onChange(of: albumManager.secureDeletionEnabled) { _ in
            albumManager.saveSettings()
        }
        .sheet(isPresented: $showDecoyPasswordSheet) {
            VStack(spacing: 20) {
                Text("Set Decoy Password")
                    .font(.headline)

                Text("Enter a password that will unlock a fake, empty album.")
                    .multilineTextAlignment(.center)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                SecureField("Decoy Password", text: $decoyPasswordInput)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .frame(maxWidth: 300)

                SecureField("Confirm Password", text: $decoyPasswordConfirm)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .frame(maxWidth: 300)

                if let error = decoyPasswordError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack(spacing: 20) {
                    Button("Cancel") {
                        showDecoyPasswordSheet = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        if decoyPasswordInput.isEmpty {
                            decoyPasswordError = "Password cannot be empty"
                        } else if decoyPasswordInput != decoyPasswordConfirm {
                            decoyPasswordError = "Passwords do not match"
                        } else {
                            albumManager.setDecoyPassword(decoyPasswordInput)
                            // Manually update the AppStorage to reflect the change immediately
                            if let hash = UserDefaults.standard.string(forKey: "decoyPasswordHash") {
                                decoyPasswordHash = hash
                            }
                            showDecoyPasswordSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 10)
            }
            .padding()
            .presentationDetents([.height(300)])
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
            return nil  // Follow system
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
