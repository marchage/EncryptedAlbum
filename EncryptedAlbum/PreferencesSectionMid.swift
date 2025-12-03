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
    @State private var showLockdownDisableConfirm: Bool = false
    @State private var lockdownDisableAuthFailed: Bool = false
    @State private var lockdownDisableAuthErrorMessage: String? = nil

    // Air-Gapped Mode state
    @AppStorage("airGappedModeEnabled") private var storedAirGappedMode: Bool = false
    @State private var showAirGappedConfirm: Bool = false
    @State private var showAirGappedDisableConfirm: Bool = false

    // Cloud-Native Mode state
    @AppStorage("cloudNativeModeEnabled") private var storedCloudNativeMode: Bool = false
    @State private var showCloudNativeConfirm: Bool = false
    @State private var showCloudNativeDisableConfirm: Bool = false

    var body: some View {
        Group {
            Toggle(
                "Auto-remove from Photos after import",
                isOn: Binding(
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
                )
            )
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
                Text(
                    "Enabling this will automatically remove photos from the Photos app after they are securely imported into Encrypted Album. This is potentially destructive — make sure you have backups and understand the behaviour."
                )
            }

            Text(
                "Note: this operation requires Photos permission and will permanently remove items from the system Photos library (it moves items to the Recently Deleted album). You may be prompted to grant access when first used."
            )
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

            // Lockdown Mode section with status indicator
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Lockdown Mode")
                            .font(.headline)
                        if albumManager.lockdownModeEnabled {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    Text("Restricts imports, exports & iCloud sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.lockdownModeEnabled },
                        set: { newValue in
                            if newValue && !albumManager.lockdownModeEnabled {
                                // Turning ON - ask for confirmation
                                showLockdownConfirm = true
                            } else if !newValue && albumManager.lockdownModeEnabled {
                                // Turning OFF - require re-auth to confirm disabling lockdown
                                showLockdownDisableConfirm = true
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .red))
            }
            .accessibilityIdentifier("lockdownToggle")
            .padding(.vertical, 8)
            .alert("Enable Lockdown Mode?", isPresented: $showLockdownConfirm) {
                Button("Enable Lockdown", role: .destructive) {
                    albumManager.lockdownModeEnabled = true
                    storedLockdownMode = true
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {
                    // Do nothing - toggle stays off
                }
            } message: {
                Text(
                    "Lockdown Mode will:\n\n• Block all imports (files, photos, camera)\n• Block all exports\n• Disable iCloud sync\n• Block Share Extension\n\nYou can turn this off at any time from this settings screen."
                )
            }

            // Disable flow: require authentication before disabling lockdown
            .alert("Disable Lockdown?", isPresented: $showLockdownDisableConfirm) {
                Button("Disable Lockdown", role: .destructive) {
                    Task {
                        do {
                            // Ask AlbumManager to perform biometric/password retrieval
                            _ = try await albumManager.authenticateAndRetrievePassword()
                            albumManager.lockdownModeEnabled = false
                            storedLockdownMode = false
                            albumManager.saveSettings()
                        } catch {
                            lockdownDisableAuthErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Authentication failed or cancelled."
                            lockdownDisableAuthFailed = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    // revert toggle visually (no-op here since toggle binding does not toggle until change)
                }
            } message: {
                Text("Disabling Lockdown will allow data to be imported/exported and enable cloud sync. You must re-authenticate to confirm.")
            }

            .alert(lockdownDisableAuthErrorMessage ?? "Authentication failed or cancelled.", isPresented: $lockdownDisableAuthFailed) {
                Button("OK", role: .cancel) {}
            }

            Text(
                albumManager.lockdownModeEnabled
                    ? "🔒 LOCKDOWN ACTIVE: No data can enter or leave this album until you disable Lockdown Mode above."
                    : "When enabled, the app refuses all data movement — no imports, exports, or cloud sync. Use this for maximum isolation."
            )
            .font(.caption)
            .foregroundStyle(albumManager.lockdownModeEnabled ? .red : .secondary)

            // Air-Gapped Mode section with orange theme
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Air-Gapped Mode")
                            .font(.headline)
                        if albumManager.airGappedModeEnabled {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    Text("Blocks all network operations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.airGappedModeEnabled },
                        set: { newValue in
                            if newValue && !albumManager.airGappedModeEnabled {
                                showAirGappedConfirm = true
                            } else if !newValue && albumManager.airGappedModeEnabled {
                                showAirGappedDisableConfirm = true
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .disabled(albumManager.lockdownModeEnabled) // Lockdown supersedes Air-Gapped
            }
            .accessibilityIdentifier("airGappedToggle")
            .padding(.vertical, 8)
            .alert("Enable Air-Gapped Mode?", isPresented: $showAirGappedConfirm) {
                Button("Enable Air-Gapped", role: .destructive) {
                    albumManager.airGappedModeEnabled = true
                    storedAirGappedMode = true
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Air-Gapped Mode will:\n\n• Block all iCloud sync operations\n• Block cloud verification\n• Block any future network features\n\nLocal imports and exports remain enabled. Use this for field/military scenarios where network access is a security risk."
                )
            }
            .alert("Disable Air-Gapped Mode?", isPresented: $showAirGappedDisableConfirm) {
                Button("Disable", role: .destructive) {
                    albumManager.airGappedModeEnabled = false
                    storedAirGappedMode = false
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Disabling Air-Gapped Mode will allow iCloud sync and network operations.")
            }

            Text(
                albumManager.airGappedModeEnabled
                    ? "📡 AIR-GAPPED: No network requests. Local imports/exports still work."
                    : albumManager.lockdownModeEnabled
                        ? "Air-Gapped Mode is superseded by Lockdown Mode."
                        : "Blocks all network operations while still allowing local file transfers. For military/field use."
            )
            .font(.caption)
            .foregroundStyle(albumManager.airGappedModeEnabled ? .orange : .secondary)

            // Cloud-Native Mode section with blue theme
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cloud-Native Mode")
                            .font(.headline)
                        if albumManager.cloudNativeModeEnabled {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue))
                        }
                    }
                    Text("Device = viewer only, data lives in cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { albumManager.cloudNativeModeEnabled },
                        set: { newValue in
                            if newValue && !albumManager.cloudNativeModeEnabled {
                                showCloudNativeConfirm = true
                            } else if !newValue && albumManager.cloudNativeModeEnabled {
                                showCloudNativeDisableConfirm = true
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .disabled(albumManager.lockdownModeEnabled || albumManager.airGappedModeEnabled)
            }
            .accessibilityIdentifier("cloudNativeToggle")
            .padding(.vertical, 8)
            .alert("Enable Cloud-Native Mode?", isPresented: $showCloudNativeConfirm) {
                Button("Enable Cloud-Native", role: .destructive) {
                    albumManager.cloudNativeModeEnabled = true
                    storedCloudNativeMode = true
                    // Auto-enable iCloud sync when going cloud-native
                    albumManager.encryptedCloudSyncEnabled = true
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Cloud-Native Mode will:\n\n• Prioritize cloud storage over local\n• Auto-enable encrypted iCloud sync\n• Treat device as a viewer/cache\n• Keep data safe even if device is wiped\n\nYour data lives in YOUR iCloud container — isolated from other devices, even with the same Apple ID."
                )
            }
            .alert("Disable Cloud-Native Mode?", isPresented: $showCloudNativeDisableConfirm) {
                Button("Disable", role: .destructive) {
                    albumManager.cloudNativeModeEnabled = false
                    storedCloudNativeMode = false
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Disabling Cloud-Native Mode will return to normal local-first storage. Your cloud data will remain but won't be prioritized.")
            }

            Text(
                albumManager.cloudNativeModeEnabled
                    ? "☁️ CLOUD-NATIVE: Device is a viewer. Data lives in your isolated iCloud container."
                    : albumManager.lockdownModeEnabled || albumManager.airGappedModeEnabled
                        ? "Cloud-Native Mode is incompatible with Lockdown/Air-Gapped."
                        : "Device becomes a viewer/cache. Data lives in iCloud, isolated from other devices. For traveling professionals."
            )
            .font(.caption)
            .foregroundStyle(albumManager.cloudNativeModeEnabled ? .blue : .secondary)

            Toggle(
                "Show status indicators",
                isOn: Binding(
                    get: { albumManager.showStatusIndicators },
                    set: {
                        albumManager.showStatusIndicators = $0
                        albumManager.saveSettings()
                    }
                )
            )
            
            Text("Shows the status pill (sync, importing, keep awake) in the bottom-left corner. Turn off if you don't want to know what's happening.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Show status on lock screen",
                isOn: Binding(
                    get: { albumManager.showStatusOnLockScreen },
                    set: {
                        albumManager.showStatusOnLockScreen = $0
                        albumManager.saveSettings()
                    }
                )
            )
            .disabled(!albumManager.showStatusIndicators)
            
            Text("Shows sync, importing, and encryption status on the unlock screen. Disabled by default for privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Import & Export").font(.headline)

            Toggle(
                "Require re-auth for exports",
                isOn: Binding(
                    get: { albumManager.requireReauthForExports },
                    set: {
                        albumManager.requireReauthForExports = $0
                        albumManager.saveSettings()
                    }
                )
            )
            .disabled(albumManager.lockdownModeEnabled)

            HStack {
                Text("Backup Schedule")
                Spacer()
                Picker(
                    "Backup",
                    selection: Binding(
                        get: { albumManager.backupSchedule },
                        set: {
                            albumManager.backupSchedule = $0
                            albumManager.saveSettings()
                        })
                ) {
                    Text("Manual").tag("manual")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .disabled(albumManager.lockdownModeEnabled)

            Text(
                albumManager.backupSchedule == "manual"
                    ? "Backups are only created when you manually export. Use 'Export Encrypted Key Backup' below to create a backup file you can store anywhere."
                    : "The app will automatically create encrypted backup archives (password-protected .tar.gz) to your iCloud Drive on a \(albumManager.backupSchedule) basis."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle(
                "Encrypt iCloud Sync",
                isOn: Binding(
                    get: { albumManager.encryptedCloudSyncEnabled },
                    set: {
                        albumManager.encryptedCloudSyncEnabled = $0
                        albumManager.saveSettings()
                    })
            )
            .disabled(albumManager.lockdownModeEnabled || albumManager.airGappedModeEnabled)

            Text(
                albumManager.encryptedCloudSyncEnabled
                    ? "✅ Your album is synced to iCloud with client-side AES-GCM encryption. Apple cannot read your data — only devices with your password can decrypt it."
                    : "❌ iCloud sync is disabled. Your album exists only on this device. Enable this to back up encrypted data to iCloud and sync across your devices."
            )
            .font(.caption)
            .foregroundStyle(albumManager.encryptedCloudSyncEnabled ? .green : .secondary)

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
                        Text(
                            "Last sync: \(DateFormatter.localizedString(from: last, dateStyle: .short, timeStyle: .short))"
                        )
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
                    .disabled(
                        albumManager.lockdownModeEnabled || albumManager.airGappedModeEnabled || !albumManager.encryptedCloudSyncEnabled
                            || albumManager.cloudSyncStatus == .syncing)
                }

                HStack {
                    Button(action: {
                        Task { _ = try? await AlbumManager.shared.performQuickEncryptedCloudVerification() }
                    }) {
                        Text("Verify encryption")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        albumManager.lockdownModeEnabled || albumManager.airGappedModeEnabled || !albumManager.encryptedCloudSyncEnabled
                            || albumManager.cloudSyncStatus == .syncing)

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
                Picker(
                    "Thumbnail",
                    selection: Binding(
                        get: { albumManager.thumbnailPrivacy },
                        set: {
                            albumManager.thumbnailPrivacy = $0
                            albumManager.saveSettings()
                        })
                ) {
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
