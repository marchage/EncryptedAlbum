import SwiftUI

struct PreferencesSectionMid: View {
    @EnvironmentObject var albumManager: AlbumManager

    @AppStorage("stealthModeEnabled") private var stealthModeEnabled: Bool = false
    @AppStorage("decoyPasswordHash") private var decoyPasswordHash: String = ""

    // Bindings to parent for sheet/alert triggers
    @Binding var showChangePasswordSheet: Bool
    @Binding var showDecoyPasswordSheet: Bool
    @Binding var showCameraAutoRemoveConfirm: Bool
    @Binding var pendingCameraAutoRemoveValue: Bool

    // Lockdown state (AppStorage)
    @AppStorage("lockdownModeEnabled") private var storedLockdownMode: Bool = false
    @Binding var showLockdownConfirm: Bool

    var body: some View {
        Group {
            Toggle("Auto-remove from Photos after import", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "cameraAutoRemoveFromPhotos") },
                set: { newValue in
                    if newValue {
                        pendingCameraAutoRemoveValue = true
                        showCameraAutoRemoveConfirm = true
                    } else {
                        UserDefaults.standard.set(false, forKey: "cameraAutoRemoveFromPhotos")
                        albumManager.cameraAutoRemoveFromPhotos = false
                        albumManager.saveSettings()
                    }
                }
            ))
            .alert("Enable Auto-remove from Photos?", isPresented: $showCameraAutoRemoveConfirm) {
                Button("Enable", role: .destructive) {
                    UserDefaults.standard.set(true, forKey: "cameraAutoRemoveFromPhotos")
                    albumManager.cameraAutoRemoveFromPhotos = true
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {
                    pendingCameraAutoRemoveValue = false
                }
            } message: {
                Text("Enabling this will automatically remove photos from the Photos app after they are securely imported into Encrypted Album. This is potentially destructive — make sure you have backups and understand the behaviour.")
            }

            Text("Note: this operation requires Photos permission and will permanently remove items from the system Photos library (it moves items to the Recently Deleted album). You may be prompted to grant access when first used.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Change Album Password") {
                showChangePasswordSheet = true
            }
            .buttonStyle(.bordered)

            Text("Change your album password. This will re-encrypt all data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Stealth Features").font(.headline)
            Toggle("Stealth Mode (Fake Crash)", isOn: $stealthModeEnabled)
            Text("When enabled, the app will appear to crash or freeze on launch. Long press the screen for 1.5 seconds to unlock.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Decoy Password")
                Spacer()
                if !decoyPasswordHash.isEmpty {
                    Button("Remove") {
                        AlbumManager.shared.clearDecoyPassword()
                        decoyPasswordHash = ""
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Change") {
                        // parent will present a sheet
                        showDecoyPasswordSheet = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Set Decoy Password") {
                        showDecoyPasswordSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("A decoy password unlocks an empty album. Use this if forced to unlock your device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Lockdown Mode (restrict imports/exports & iCloud)", isOn: $storedLockdownMode)
                .accessibilityIdentifier("lockdownToggle")
                .onChange(of: storedLockdownMode) { isOn in
                    if isOn {
                        // ask for confirmation and revert until confirmed
                        showLockdownConfirm = true
                        storedLockdownMode = false
                    } else {
                        albumManager.lockdownModeEnabled = false
                        albumManager.saveSettings()
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .red))
                .padding(.vertical)
                .alert("Enable Lockdown Mode?", isPresented: $showLockdownConfirm) {
                    Button("Enable", role: .destructive) {
                        storedLockdownMode = true
                        albumManager.lockdownModeEnabled = true
                        albumManager.saveSettings()
                    }
                    Button("Cancel", role: .cancel) {
                        storedLockdownMode = false
                    }
                } message: {
                    Text("Lockdown Mode will disable iCloud sync, imports and exports. Use this when you need to minimize external connectivity and data movement.")
                }

            Text("While Lockdown Mode is enabled the app will refuse imports, exports, and iCloud verification. Share extensions will be blocked from depositing files into the album's inbox.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Import & Export").font(.headline)

            Toggle("Require re-auth for exports", isOn: Binding(
                get: { albumManager.requireReauthForExports },
                set: { albumManager.requireReauthForExports = $0; albumManager.saveSettings() }
            ))
            .disabled(albumManager.lockdownModeEnabled)

            HStack {
                Text("Backup Schedule")
                Spacer()
                Picker("Backup", selection: Binding(get: { albumManager.backupSchedule }, set: { albumManager.backupSchedule = $0; albumManager.saveSettings() })) {
                    Text("Manual").tag("manual")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .disabled(albumManager.lockdownModeEnabled)

            Toggle("Encrypted iCloud Sync", isOn: Binding(get: { albumManager.encryptedCloudSyncEnabled }, set: { albumManager.encryptedCloudSyncEnabled = $0; albumManager.saveSettings() }))
                .disabled(albumManager.lockdownModeEnabled)

            // Cloud sync UI (small group)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("iCloud Sync")
                    Spacer()
                    Text(albumManager.cloudSyncStatus.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let last = albumManager.lastCloudSync {
                        Text("Last sync: \(DateFormatter.localizedString(from: last, dateStyle: .short, timeStyle: .short))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Last sync: —")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        Task { _ = try? await AlbumManager.shared.performManualCloudSync() }
                    }) {
                        Text("Sync now")
                    }
                    .buttonStyle(.bordered)
                    .disabled(albumManager.lockdownModeEnabled || !albumManager.encryptedCloudSyncEnabled || albumManager.cloudSyncStatus == .syncing)
                }

                HStack {
                    Button(action: {
                        Task { _ = try? await AlbumManager.shared.performQuickEncryptedCloudVerification() }
                    }) {
                        Text("Verify encryption")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(albumManager.lockdownModeEnabled || !albumManager.encryptedCloudSyncEnabled || albumManager.cloudSyncStatus == .syncing)

                    Spacer()

                    Text(albumManager.cloudVerificationStatus.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let cloudMessage = albumManager.cloudSyncErrorMessage {
                    Text(cloudMessage)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    Text("Encryption status")
                    Spacer()
                    Text(albumManager.encryptedCloudSyncEnabled ? "Client-side encrypted (AES-GCM)" : "Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Thumbnail Privacy")
                Spacer()
                Picker("Thumbnail", selection: Binding(get: { albumManager.thumbnailPrivacy }, set: { albumManager.thumbnailPrivacy = $0; albumManager.saveSettings() })) {
                    Text("Blur").tag("blur")
                    Text("Hide").tag("hide")
                    Text("None").tag("none")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
