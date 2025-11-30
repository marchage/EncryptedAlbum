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

    // App icon UI is now handled by `PreferencesSectionTop` subview
    
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
                        PreferencesSectionTop()
                        PreferencesSectionMid(
                            showChangePasswordSheet: $showChangePasswordSheet,
                            showDecoyPasswordSheet: $showDecoyPasswordSheet,
                            showCameraAutoRemoveConfirm: $showCameraAutoRemoveConfirm,
                            pendingCameraAutoRemoveValue: $pendingCameraAutoRemoveValue,
                            showLockdownConfirm: $showLockdownConfirm
                        )
                        PreferencesSectionBottom(showBackupSheet: $showBackupSheet)
                        
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
            // App icon picker state is now managed by the PreferencesSectionTop subview
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
