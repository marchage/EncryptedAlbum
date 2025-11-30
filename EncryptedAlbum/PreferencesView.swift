import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var albumManager: AlbumManager
    
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
    
    @State private var showChangePasswordSheet = false
    @State private var currentPasswordInput = ""
    @State private var newPasswordInput = ""
    @State private var confirmPasswordInput = ""
    @State private var changePasswordError: String?
    @State private var isChangingPassword = false
    @State private var changePasswordProgress: String?
    
    // New settings states for backup and UX
    @AppStorage("autoLockTimeoutSeconds") private var storedAutoLockTimeout: Double = CryptoConstants.idleTimeout
    @AppStorage("requirePasscodeOnLaunch") private var storedRequirePasscodeOnLaunch: Bool = false
    @AppStorage("biometricPolicy") private var storedBiometricPolicy: String = "biometrics_preferred"
    @AppStorage("appTheme") private var storedAppTheme: String = "default"
    @AppStorage("compactLayoutEnabled") private var storedCompactLayoutEnabled: Bool = false
    @AppStorage("accentColorName") private var storedAccentColorName: String = "blue"
    @AppStorage("cameraMaxQuality") private var storedCameraMaxQuality: Bool = true
    @AppStorage("cameraAutoRemoveFromPhotos") private var storedCameraAutoRemoveFromPhotos: Bool = false
    @AppStorage("keepScreenAwakeWhileUnlocked") private var storedKeepScreenAwakeWhileUnlocked: Bool = false
    @AppStorage("keepScreenAwakeDuringSuspensions") private var storedKeepScreenAwakeDuringSuspensions: Bool = true
    @AppStorage("lockdownModeEnabled") private var storedLockdownMode: Bool = false
    
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0
    // Allow user to force fallback to legacy Keychain behavior if Data Protection Keychain causes issues
    @AppStorage("security.useDataProtectionKeychain") private var useDataProtectionKeychain: Bool = true

    // App Icon selection service
    @ObservedObject private var appIconService = AppIconService.shared
    @State private var uiSelectedAppIcon: String = "AppIcon"
    
    @State private var showLockdownConfirm: Bool = false
    
    @State private var showBackupSheet = false
    @State private var backupPassword = ""
    @State private var backupPasswordConfirm = ""
    @State private var backupError: String?
    @State private var isBackingUp = false
    @State private var backupResultURL: URL?
    @State private var showBackupSuccessAlert = false
    @State private var showShareSheet = false
    @State private var showCameraAutoRemoveConfirm = false
    @State private var pendingCameraAutoRemoveValue: Bool = false
    
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
#endif
    
#if os(macOS)
    @Binding var isPresented: Bool
    private let isSheet: Bool
#endif
    
    init() {
#if os(macOS)
        self._isPresented = .constant(true)
        self.isSheet = false
#endif
    }
    
#if os(macOS)
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self.isSheet = true
    }
#endif
    
    var body: some View {
#if os(iOS)
        content
#else
        content
#endif
    }
    
    private var content: some View {
        ZStack {
            PrivacyOverlayBackground(asBackground: true)
            
            if albumManager.isUnlocked {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 🔮 Paste all your UI elements here
                        sectionTop
                        sectionMid
                        sectionBottom
                        
                        Group {
                            Toggle("Auto-remove from Photos after import", isOn: Binding(
                                get: { storedCameraAutoRemoveFromPhotos },
                                set: { newValue in
                                    // Show confirmation when enabling auto-remove to respect Photos policy
                                    if newValue {
                                        pendingCameraAutoRemoveValue = true
                                        showCameraAutoRemoveConfirm = true
                                    } else {
                                        storedCameraAutoRemoveFromPhotos = false
                                        albumManager.cameraAutoRemoveFromPhotos = false
                                        albumManager.saveSettings()
                                    }
                                }
                            ))
                            
                            Divider()
                        }
                        // Confirmation alert for camera auto-remove
                        .alert("Enable Auto-remove from Photos?", isPresented: $showCameraAutoRemoveConfirm) {
                            Button("Enable", role: .destructive) {
                                storedCameraAutoRemoveFromPhotos = true
                                albumManager.cameraAutoRemoveFromPhotos = true
                                albumManager.saveSettings()
                            }
                            Button("Cancel", role: .cancel) {
                                // Revert
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
                                    AlbumManager.shared.clearDecoyPassword()
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
                        
                        Toggle("Lockdown Mode (restrict imports/exports & iCloud)", isOn: $storedLockdownMode)
                            .accessibilityIdentifier("lockdownToggle")
                            .onChange(of: storedLockdownMode) { isOn in
                                if isOn {
                                    // Ask for confirmation before enabling
                                    showLockdownConfirm = true
                                    // revert until confirmed
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
                        
                        Text("Import & Export")
                            .font(.headline)
                        
                        // Export & privacy controls
                        Toggle("Require re-auth for exports", isOn: $albumManager.requireReauthForExports)
                            .disabled(albumManager.lockdownModeEnabled)
                            .onChange(of: albumManager.requireReauthForExports) { _ in
                                albumManager.saveSettings()
                            }
                        
                        HStack {
                            Text("Backup Schedule")
                            Spacer()
                            Picker("Backup", selection: $albumManager.backupSchedule) {
                                Text("Manual").tag("manual")
                                Text("Weekly").tag("weekly")
                                Text("Monthly").tag("monthly")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .disabled(albumManager.lockdownModeEnabled)
                        .onChange(of: albumManager.backupSchedule) { _ in
                            albumManager.saveSettings()
                        }
                        
                        Toggle("Encrypted iCloud Sync", isOn: $albumManager.encryptedCloudSyncEnabled)
                            .disabled(albumManager.lockdownModeEnabled)
                            .onChange(of: albumManager.encryptedCloudSyncEnabled) { _ in
                                albumManager.saveSettings()
                            }
                        
                        // Cloud sync controls — last sync, manual sync, encryption status
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
                                    Task {
                                        let _ = try? await AlbumManager.shared.performManualCloudSync()
                                    }
                                }) {
                                    Text("Sync now")
                                }
                                .buttonStyle(.bordered)
                                .disabled(albumManager.lockdownModeEnabled || !albumManager.encryptedCloudSyncEnabled || albumManager.cloudSyncStatus == .syncing)
                            }
                            
                            // Quick encrypted sync verification (writes a short encrypted file to iCloud container and verifies round-trip)
                            HStack {
                                Button(action: {
                                    Task {
                                        let _ = try? await AlbumManager.shared.performQuickEncryptedCloudVerification()
                                        // no-op; AlbumManager updates state for UI
                                    }
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
                            
                            // Show whether encryption is performed client-side for items pushed to cloud
                            HStack {
                                Text("Encryption status")
                                Spacer()
                                // If cloud sync is enabled, we display that client-side encryption is used (the app encrypts files locally)
                                Text(albumManager.encryptedCloudSyncEnabled ? "Client-side encrypted (AES-GCM)" : "Disabled")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Thumbnail Privacy")
                            Spacer()
                            Picker("Thumbnail", selection: $albumManager.thumbnailPrivacy) {
                                Text("Blur").tag("blur")
                                Text("Hide").tag("hide")
                                Text("None").tag("none")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .onChange(of: albumManager.thumbnailPrivacy) { _ in
                            albumManager.saveSettings()
                        }
                        
                        Toggle("Strip metadata on export", isOn: $albumManager.stripMetadataOnExport)
                            .disabled(albumManager.lockdownModeEnabled)
                            .onChange(of: albumManager.stripMetadataOnExport) { _ in
                                albumManager.saveSettings()
                            }
                        
                        Toggle("Password-protect exports", isOn: $albumManager.exportPasswordProtect)
                            .disabled(albumManager.lockdownModeEnabled)
                            .onChange(of: albumManager.exportPasswordProtect) { _ in
                                albumManager.saveSettings()
                            }
                        
                        HStack {
                            Text("Export expiry (days)")
                            Spacer()
                            Stepper("\(albumManager.exportExpiryDays)", value: $albumManager.exportExpiryDays, in: 1...365)
                                .labelsHidden()
                        }
                        .disabled(albumManager.lockdownModeEnabled)
                        .onChange(of: albumManager.exportExpiryDays) { _ in
                            albumManager.saveSettings()
                        }
                        
                        Toggle("Enable verbose logging", isOn: $albumManager.enableVerboseLogging)
                            .onChange(of: albumManager.enableVerboseLogging) { _ in
                                albumManager.saveSettings()
                            }
                        
                        HStack {
                            Text("Passphrase minimum length")
                            Spacer()
                            Stepper("\(albumManager.passphraseMinLength)", value: $albumManager.passphraseMinLength, in: 6...64)
                                .labelsHidden()
                        }
                        .onChange(of: albumManager.passphraseMinLength) { _ in
                            albumManager.saveSettings()
                        }
                        
                        Toggle("Telemetry (opt-in)", isOn: $albumManager.telemetryEnabled)
                            .onChange(of: albumManager.telemetryEnabled) { _ in
                                albumManager.saveSettings()
                            }
                        
                        Toggle("Auto-remove duplicates on import", isOn: $albumManager.autoRemoveDuplicatesOnImport)
                        
                        Divider()
                        
                        // Screen sleep behaviour
                        Toggle("Keep screen awake while unlocked", isOn: $storedKeepScreenAwakeWhileUnlocked)
                            .onChange(of: storedKeepScreenAwakeWhileUnlocked) { newValue in
                                // Save to user defaults (AppStorage already persists), nothing else needed here.
                                // AlbumManager will read the setting when suspensions end to decide behavior.
                                albumManager.saveSettings()
                            }
                        Toggle("Prevent system sleep during imports & viewing", isOn: $storedKeepScreenAwakeDuringSuspensions)
                            .onChange(of: storedKeepScreenAwakeDuringSuspensions) { newValue in
                                albumManager.saveSettings()
                            }
                        Text("Automatically skip importing photos that are already in the album.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Toggle("Enable import notifications", isOn: $albumManager.enableImportNotifications)
                        Text("Show system notifications when batch imports complete.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        Text("Diagnostics")
                            .font(.headline)
                        
                        HStack {
                            Text("Lockdown Mode")
                            Spacer()
                            Text(albumManager.lockdownModeEnabled ? "Enabled" : "Disabled")
                                .font(.caption2)
                                .foregroundStyle(albumManager.lockdownModeEnabled ? .red : .secondary)
                        }
                        
                        HStack(spacing: 10) {
                            Text("Choose app icon")
                            Spacer()
                            Picker("App Icon", selection: $uiSelectedAppIcon) {
                                ForEach(appIconService.availableIcons, id: \ .self) { name in
                                    Text(appIconService.displayName(for: name)).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 220)

                            // Provide an explicit Apply/Set button so the user can force the system change
                            Button("Set") {
                                let selected = (uiSelectedAppIcon == "AppIcon") ? nil : uiSelectedAppIcon
                                appIconService.select(iconName: selected)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .onChange(of: uiSelectedAppIcon) { newValue in
                            // Keep UI state in sync but require explicit Set to apply system icon.
                            // This avoids accidentally changing the user's icon on simple UI navigation.
                        }

                        // Show current system/app service state and a force-apply button (iOS specific)
                        HStack {
                            Text("Current icon")
                            Spacer()
                            Text(appIconService.selectedIconName.isEmpty ? "Default" : appIconService.selectedIconName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            #if os(iOS)
                            Button("Force apply") {
                                // Re-attempt an explicit system call regardless of stored state.
                                let selected = (uiSelectedAppIcon == "AppIcon") ? nil : uiSelectedAppIcon
                                UIApplication.shared.setAlternateIconName(selected) { error in
                                    if let error = error {
                                        AppLog.debugPrivate("PreferencesView: force set alternate icon failed: \(error.localizedDescription)")
                                    } else {
                                        AppLog.debugPrivate("PreferencesView: force set alternate icon success")
                                        // Update our persisted value so other UIs match
                                        appIconService.select(iconName: selected)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            #endif
                        }
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
                        
                        Text("Key Management")
                            .font(.headline)

                        #if os(macOS)
                        Toggle("Use Data Protection Keychain (macOS)", isOn: $useDataProtectionKeychain)
                            .onChange(of: useDataProtectionKeychain) { _ in
                                // No-op: SecurityService reads the UserDefaults value at runtime
                            }
                        Text("When enabled the app probes for and prefers the Data Protection Keychain domain (stronger protection). If this causes problems, turn it OFF to fall back to the legacy login keychain behaviour immediately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        #endif
                        
                        HStack {
                            Button("Export Encrypted Key Backup") {
                                backupPassword = ""
                                backupPasswordConfirm = ""
                                backupError = nil
                                showBackupSheet = true
                            }
                            .disabled(albumManager.lockdownModeEnabled)
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        
                        .sheet(isPresented: $showBackupSheet) {
                            VStack(spacing: 16) {
                                Text("Export Encrypted Key Backup")
                                    .font(.headline)
                                Text("Enter a password to protect the exported key backup file.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                SecureField("Backup Password", text: $backupPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 320)
                                SecureField("Confirm Password", text: $backupPasswordConfirm)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 320)
                                
                                if let error = backupError {
                                    Text(error)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                                
                                HStack(spacing: 16) {
                                    Button("Cancel") { showBackupSheet = false }
                                        .buttonStyle(.bordered)
                                    
                                    Button {
                                        guard !backupPassword.isEmpty else {
                                            backupError = "Password cannot be empty"
                                            return
                                        }
                                        guard backupPassword == backupPasswordConfirm else {
                                            backupError = "Passwords do not match"
                                            return
                                        }
                                        
                                        isBackingUp = true
                                        backupError = nil
                                        Task {
                                            let manager: AlbumManager = albumManager
                                            do {
                                                let url = try await manager.exportMasterKeyBackup(backupPassword: backupPassword)
                                                backupResultURL = url
                                                showBackupSheet = false
                                                // Present share sheet on iOS; on macOS the alert will remain as fallback
                                                showShareSheet = true
                                            } catch {
                                                backupError = error.localizedDescription
                                            }
                                            isBackingUp = false
                                        }
                                    } label: {
                                        if isBackingUp { ProgressView().controlSize(.small) }
                                        else { Text("Export") }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding()
                            .presentationDetents([.height(320)])
                        }
                        
                        // Share sheet for exported backup (iOS). After successful sharing we remove the temp file.
                        .sheet(isPresented: $showShareSheet) {
                            if let url = backupResultURL {
                                ActivityView(activityItems: [url]) { completed in
                                        if completed {
                                        // Attempt to securely remove the temporary file after successful share
                                        _ = try? FileManager.default.removeItem(at: url)
                                    }
                                    // Clear state
                                    backupResultURL = nil
                                    showShareSheet = false
                                }
                            } else {
                                EmptyView()
                            }
                        }
                        
                        Spacer()
                        
#if os(iOS)
                        Divider()
                        
                        HStack {
                            Spacer()
                            Button("Close") {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
#endif
                        
#if os(macOS)
                        if isSheet {
                            Divider()
                            
                            HStack {
                                Spacer()
                                Button("Close") {
                                    isPresented = false
                                }
                                .buttonStyle(.borderedProminent)
                                Spacer()
                            }
                        }
#endif
                        
                        
                    }
                    .padding(20)
                }
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
#if os(macOS)
        .navigationTitle("Settings")
#endif
        .onChange(of: albumManager.secureDeletionEnabled) { _ in
            albumManager.saveSettings()
        }
        .onChange(of: albumManager.autoRemoveDuplicatesOnImport) { _ in
            albumManager.saveSettings()
        }
        .onChange(of: albumManager.enableImportNotifications) { _ in
            albumManager.saveSettings()
        }
        .onAppear {
            // Ensure UI toggle reflects manager state on first load
            storedLockdownMode = albumManager.lockdownModeEnabled
            // Initialize local picker state for app icon
            uiSelectedAppIcon = appIconService.selectedIconName.isEmpty ? "AppIcon" : appIconService.selectedIconName
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
        .sheet(isPresented: $showChangePasswordSheet) {
            VStack(spacing: 20) {
                Text("Change Album Password")
                    .font(.headline)
                
                SecureField("Current Password", text: $currentPasswordInput)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .frame(maxWidth: 300)
                
                SecureField("New Password", text: $newPasswordInput)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textContentType(.newPassword)
#endif
                    .frame(maxWidth: 300)
                
                SecureField("Confirm New Password", text: $confirmPasswordInput)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textContentType(.newPassword)
#endif
                    .frame(maxWidth: 300)
                
                if let error = changePasswordError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
                
                if let progress = changePasswordProgress {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 20) {
                    Button("Cancel") {
                        showChangePasswordSheet = false
                        currentPasswordInput = ""
                        newPasswordInput = ""
                        confirmPasswordInput = ""
                        changePasswordError = nil
                        changePasswordProgress = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Change") {
                        if newPasswordInput.isEmpty {
                            changePasswordError = "New password cannot be empty"
                        } else if newPasswordInput != confirmPasswordInput {
                            changePasswordError = "New passwords do not match"
                        } else {
                            isChangingPassword = true
                            changePasswordError = nil
                            changePasswordProgress = nil
                            Task {
                                do {
                                    try await albumManager.changePassword(
                                        currentPassword: currentPasswordInput,
                                        newPassword: newPasswordInput
                                    ) { progress in
                                        Task { @MainActor in
                                            changePasswordProgress = progress
                                        }
                                    }
                                    await MainActor.run {
                                        showChangePasswordSheet = false
                                        currentPasswordInput = ""
                                        newPasswordInput = ""
                                        confirmPasswordInput = ""
                                        isChangingPassword = false
                                        changePasswordProgress = nil
                                    }
                                } catch {
                                    await MainActor.run {
                                        changePasswordError = error.localizedDescription
                                        isChangingPassword = false
                                        changePasswordProgress = nil
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChangingPassword)
                }
                .padding(.top, 10)
            }
            .padding()
            .presentationDetents([.height(400)])
        }
        .preferredColorScheme(colorScheme)
    }
    
    // Split large view into smaller computed subviews to help the Swift type checker
    @ViewBuilder
    private var sectionTop: some View {
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
            .onChange(of: storedAppTheme) { _ in
                albumManager.appTheme = storedAppTheme
                albumManager.saveSettings()
            }
            .labelsHidden()
        }
        
        Divider()
        
        // App icon selection & preview
        HStack(alignment: .center, spacing: 12) {
            Text("App Icon")
            Spacer()
            // Preview image (generated 1024 marketing image when available)
            if let platformImg = appIconService.runtimeMarketingImage {
                Image(platformImage: platformImg)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.7), lineWidth: 1))
            } else {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.7), lineWidth: 1))
            }

            Picker("App Icon", selection: $uiSelectedAppIcon) {
                ForEach(appIconService.availableIcons, id: \.self) { name in
                    Text(appIconService.displayName(for: name)).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: uiSelectedAppIcon) { newValue in
                // Treat the default AppIcon as no alternate (nil)
                if newValue == "AppIcon" || newValue.isEmpty {
                    appIconService.select(iconName: nil)
                } else {
                    appIconService.select(iconName: newValue)
                }
            }
        }

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
        
        HStack {
            Text("Auto-lock timeout")
            Spacer()
            Text("\(Int(storedAutoLockTimeout))s")
                .foregroundStyle(.secondary)
        }
        Slider(value: $storedAutoLockTimeout, in: 30...3600, step: 30) {
        }
        .onChange(of: storedAutoLockTimeout) { _ in
            albumManager.autoLockTimeoutSeconds = storedAutoLockTimeout
            albumManager.saveSettings()
        }
        
        Toggle("Require Passcode On Launch", isOn: $storedRequirePasscodeOnLaunch)
            .onChange(of: storedRequirePasscodeOnLaunch) { _ in
                albumManager.requirePasscodeOnLaunch = storedRequirePasscodeOnLaunch
                albumManager.saveSettings()
            }
        
        HStack {
            Text("Biometric Policy")
            Spacer()
            Picker("", selection: $storedBiometricPolicy) {
                Text("Prefer Biometrics").tag("biometrics_preferred")
                Text("Require Biometrics").tag("biometrics_required")
                Text("Disable Biometrics").tag("biometrics_disabled")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .onChange(of: storedBiometricPolicy) { _ in
            albumManager.biometricPolicy = storedBiometricPolicy
            albumManager.saveSettings()
        }
        
        Toggle("Require Re-authentication", isOn: $requireForegroundReauthentication)
        Text("When enabled, the album will lock when the app goes to the background or is inactive.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        // Auto-wipe on failed unlock attempts
        Toggle("Auto-wipe on repeated failed unlocks", isOn: $albumManager.autoWipeOnFailedAttemptsEnabled)
            .onChange(of: albumManager.autoWipeOnFailedAttemptsEnabled) { _ in
                albumManager.saveSettings()
            }
        
        if albumManager.autoWipeOnFailedAttemptsEnabled {
            HStack {
                Text("Wipe threshold")
                Spacer()
                Stepper("\(albumManager.autoWipeFailedAttemptsThreshold)", value: $albumManager.autoWipeFailedAttemptsThreshold, in: 1...100)
                    .labelsHidden()
            }
            .onChange(of: albumManager.autoWipeFailedAttemptsThreshold) { _ in
                albumManager.saveSettings()
            }
        }
        
        Toggle("Enable Recovery Key", isOn: $albumManager.enableRecoveryKey)
            .onChange(of: albumManager.enableRecoveryKey) { _ in
                albumManager.saveSettings()
            }
        Text("When enabled, the app keeps an encrypted recovery key to help recover an interrupted password-change operation. This is internal and does not display a recovery code in the menus — it is used only during password-change recovery.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        Toggle("Secure Deletion (Overwrite)", isOn: $albumManager.secureDeletionEnabled)
        Text(
            "When enabled, deleted files are overwritten 3 times. This is slower but more secure. Note: on modern devices (APFS / SSD) overwrites may not always guarantee physical erasure — see app documentation for details. Secure overwrite is limited to the first \(ByteCountFormatter.string(fromByteCount: CryptoConstants.maxSecureDeleteSize, countStyle: .file)) of each file; larger files will be removed but only the first chunk will be overwritten."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        
        Divider()
        Text("Appearance")
            .font(.headline)
        
        Toggle("Compact Layout", isOn: $storedCompactLayoutEnabled)
            .onChange(of: storedCompactLayoutEnabled) { _ in
                albumManager.compactLayoutEnabled = storedCompactLayoutEnabled
                albumManager.saveSettings()
            }
        Text("Enables a denser layout in some screens (e.g. smaller buttons and tighter paddings). Effects are visible in a few places such as the unlock screen and lists.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        HStack {
            Text("Accent Color")
            Spacer()
            Picker("Accent", selection: $storedAccentColorName) {
                Text("Blue").tag("blue")
                Text("Green").tag("green")
                Text("Pink").tag("pink")
                Text("Winamp").tag("winamp")
                Text("System").tag("system")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .onChange(of: storedAccentColorName) { _ in
            albumManager.accentColorName = storedAccentColorName
            albumManager.saveSettings()
        }
        Text("Choose the app accent color used for highlighted UI elements across the app. Choosing 'System' defers to the platform default accent color.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        Divider()
        
        Text("Camera")
            .font(.headline)
        
        Toggle("Capture at max quality", isOn: $storedCameraMaxQuality)
            .onChange(of: storedCameraMaxQuality) { _ in
                albumManager.cameraMaxQuality = storedCameraMaxQuality
                albumManager.saveSettings()
            }

        // App Icon selection
        Divider()
        Text("App Icon")
            .font(.headline)

        HStack {
            Text("Choose app icon")
            Spacer()
            Picker("App Icon", selection: $uiSelectedAppIcon) {
                ForEach(appIconService.availableIcons, id: \.self) { name in
                    Text(appIconService.displayName(for: name)).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 220)

            // Explicit apply button: changing the picker should not immediately
            // trigger a system icon update (prevents accidental changes). User
            // must press Set to apply their chosen icon.
            Button("Set") {
                let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                appIconService.select(iconName: selected)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        // Keep the UI state in-sync with selection changes, but require an explicit
        // Set action to perform the system call (safer UX). Leave the onChange
        // handler lightweight so we don't accidentally execute cross-platform
        // API calls in unexpected contexts.
        .onChange(of: uiSelectedAppIcon) { _ in
            /* no-op: Set button applies the selection */
        }

        // iOS-only helpers: allow the user to see/add a force apply if the system
        // icon didn't update; this calls UIApplication.setAlternateIconName and
        // ensures our AppIconService state matches the actual system state.
        #if os(iOS)
        HStack {
            Text("Current icon")
            Spacer()
            Text(appIconService.selectedIconName.isEmpty ? "Default" : appIconService.selectedIconName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Force apply") {
                let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                UIApplication.shared.setAlternateIconName(selected) { error in
                    if let error = error {
                        AppLog.debugPrivate("PreferencesView: force set alternate icon failed: \(error.localizedDescription)")
                    } else {
                        AppLog.debugPrivate("PreferencesView: force set alternate icon success")
                        appIconService.select(iconName: selected)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        #endif

        #if os(iOS)
        Text("Note: iOS will only change the Home screen icon if alternate icons are declared in Info.plist (CFBundleAlternateIcons). If you don't see a system change, the app is using the default icon.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #else
        Text("On macOS this will update the Dock/window icon immediately for the chosen set.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
    
    @ViewBuilder
    private var sectionMid: some View {
        Toggle("Auto-remove from Photos after import", isOn: Binding(
            get: { storedCameraAutoRemoveFromPhotos },
            set: { newValue in
                // Show confirmation when enabling auto-remove to respect Photos policy
                if newValue {
                    pendingCameraAutoRemoveValue = true
                    showCameraAutoRemoveConfirm = true
                } else {
                    storedCameraAutoRemoveFromPhotos = false
                    albumManager.cameraAutoRemoveFromPhotos = false
                    albumManager.saveSettings()
                }
            }
        ))
        
        Divider()
        
        // Confirmation alert for camera auto-remove
            .alert("Enable Auto-remove from Photos?", isPresented: $showCameraAutoRemoveConfirm) {
                Button("Enable", role: .destructive) {
                    storedCameraAutoRemoveFromPhotos = true
                    albumManager.cameraAutoRemoveFromPhotos = true
                    albumManager.saveSettings()
                }
                Button("Cancel", role: .cancel) {
                    // Revert
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
                    AlbumManager.shared.clearDecoyPassword()
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
        
        Toggle("Lockdown Mode (restrict imports/exports & iCloud)", isOn: $storedLockdownMode)
            .accessibilityIdentifier("lockdownToggle")
            .onChange(of: storedLockdownMode) { isOn in
                if isOn {
                    // Ask for confirmation before enabling
                    showLockdownConfirm = true
                    // revert until confirmed
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
        
        Text("Import & Export")
            .font(.headline)
        
        // Export & privacy controls
        Toggle("Require re-auth for exports", isOn: $albumManager.requireReauthForExports)
            .disabled(albumManager.lockdownModeEnabled)
            .onChange(of: albumManager.requireReauthForExports) { _ in
                albumManager.saveSettings()
            }
        
        HStack {
            Text("Backup Schedule")
            Spacer()
            Picker("Backup", selection: $albumManager.backupSchedule) {
                Text("Manual").tag("manual")
                Text("Weekly").tag("weekly")
                Text("Monthly").tag("monthly")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .disabled(albumManager.lockdownModeEnabled)
        .onChange(of: albumManager.backupSchedule) { _ in
            albumManager.saveSettings()
        }
        
        Toggle("Encrypted iCloud Sync", isOn: $albumManager.encryptedCloudSyncEnabled)
            .disabled(albumManager.lockdownModeEnabled)
            .onChange(of: albumManager.encryptedCloudSyncEnabled) { _ in
                albumManager.saveSettings()
            }
        
        // Cloud sync controls — last sync, manual sync, encryption status
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
                    Task {
                        let _ = try? await AlbumManager.shared.performManualCloudSync()
                    }
                }) {
                    Text("Sync now")
                }
                .buttonStyle(.bordered)
                .disabled(albumManager.lockdownModeEnabled || !albumManager.encryptedCloudSyncEnabled || albumManager.cloudSyncStatus == .syncing)
            }
            
            // Quick encrypted sync verification (writes a short encrypted file to iCloud container and verifies round-trip)
            HStack {
                Button(action: {
                    Task {
                        let _ = try? await AlbumManager.shared.performQuickEncryptedCloudVerification()
                        // no-op; AlbumManager updates state for UI
                    }
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
            
            // Show whether encryption is performed client-side for items pushed to cloud
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
            Picker("Thumbnail", selection: $albumManager.thumbnailPrivacy) {
                Text("Blur").tag("blur")
                Text("Hide").tag("hide")
                Text("None").tag("none")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .onChange(of: albumManager.thumbnailPrivacy) { _ in
            albumManager.saveSettings()
        }
    }
    
    @ViewBuilder
    private var sectionBottom: some View {
        Toggle("Strip metadata on export", isOn: $albumManager.stripMetadataOnExport)
            .disabled(albumManager.lockdownModeEnabled)
            .onChange(of: albumManager.stripMetadataOnExport) { _ in
                albumManager.saveSettings()
            }
        
        Toggle("Password-protect exports", isOn: $albumManager.exportPasswordProtect)
            .disabled(albumManager.lockdownModeEnabled)
            .onChange(of: albumManager.exportPasswordProtect) { _ in
                albumManager.saveSettings()
            }
        
        HStack {
            Text("Export expiry (days)")
            Spacer()
            Stepper("\(albumManager.exportExpiryDays)", value: $albumManager.exportExpiryDays, in: 1...365)
                .labelsHidden()
        }
        .disabled(albumManager.lockdownModeEnabled)
        .onChange(of: albumManager.exportExpiryDays) { _ in
            albumManager.saveSettings()
        }
        
        Toggle("Enable verbose logging", isOn: $albumManager.enableVerboseLogging)
            .onChange(of: albumManager.enableVerboseLogging) { _ in
                albumManager.saveSettings()
            }
        
        HStack {
            Text("Passphrase minimum length")
            Spacer()
            Stepper("\(albumManager.passphraseMinLength)", value: $albumManager.passphraseMinLength, in: 6...64)
                .labelsHidden()
        }
        .onChange(of: albumManager.passphraseMinLength) { _ in
            albumManager.saveSettings()
        }
        
        Toggle("Telemetry (opt-in)", isOn: $albumManager.telemetryEnabled)
            .onChange(of: albumManager.telemetryEnabled) { _ in
                albumManager.saveSettings()
            }
        
        Toggle("Auto-remove duplicates on import", isOn: $albumManager.autoRemoveDuplicatesOnImport)
        
        Divider()
        
        // Screen sleep behaviour
        Toggle("Keep screen awake while unlocked", isOn: $storedKeepScreenAwakeWhileUnlocked)
            .onChange(of: storedKeepScreenAwakeWhileUnlocked) { newValue in
                albumManager.saveSettings()
            }
        Toggle("Prevent system sleep during imports & viewing", isOn: $storedKeepScreenAwakeDuringSuspensions)
            .onChange(of: storedKeepScreenAwakeDuringSuspensions) { newValue in
                albumManager.saveSettings()
            }
        Text("Automatically skip importing photos that are already in the album.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        Toggle("Enable import notifications", isOn: $albumManager.enableImportNotifications)
        Text("Show system notifications when batch imports complete.")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        Divider()
        
        Text("Diagnostics")
            .font(.headline)
        
        HStack {
            Text("Lockdown Mode")
            Spacer()
            Text(albumManager.lockdownModeEnabled ? "Enabled" : "Disabled")
                .font(.caption2)
                .foregroundStyle(albumManager.lockdownModeEnabled ? .red : .secondary)
        }
        
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
        
        Divider()
        
        Text("Key Management")
            .font(.headline)
        
        HStack {
            Button("Export Encrypted Key Backup") {
                backupPassword = ""
                backupPasswordConfirm = ""
                backupError = nil
                showBackupSheet = true
            }
            .disabled(albumManager.lockdownModeEnabled)
            .buttonStyle(.bordered)
            Spacer()
        }
        
        // share/export sheet handled in content's chaining (unchanged)
    }
    
    private var colorScheme: ColorScheme? {
        switch privacyBackgroundStyle {
        case .followSystem:
            return nil
        case .light, .retroTV:
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
        
        let manager: AlbumManager = albumManager
        Task {
            do {
                let report = try await manager.performSecurityHealthCheck()
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
