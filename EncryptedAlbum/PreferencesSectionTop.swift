import SwiftUI

struct PreferencesSectionTop: View {
    @EnvironmentObject var albumManager: AlbumManager

    @AppStorage("privacyBackgroundStyle") private var privacyBackgroundStyle: PrivacyBackgroundStyle = .classic
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0

    // Track whether the app requires re-auth on foreground; other views use AppStorage too
    @AppStorage("requireForegroundReauthentication") private var requireForegroundReauthentication: Bool = true

    @AppStorage("autoLockTimeoutSeconds") private var storedAutoLockTimeout: Double = CryptoConstants.idleTimeout
    @AppStorage("requirePasscodeOnLaunch") private var storedRequirePasscodeOnLaunch: Bool = false
    @AppStorage("biometricPolicy") private var storedBiometricPolicy: String = "biometrics_preferred"

    @AppStorage("compactLayoutEnabled") private var storedCompactLayoutEnabled: Bool = false
    @AppStorage("accentColorName") private var storedAccentColorName: String = "blue"
    @AppStorage("cameraMaxQuality") private var storedCameraMaxQuality: Bool = true

    @ObservedObject private var appIconService = AppIconService.shared
    @State private var uiSelectedAppIcon: String = "AppIcon"
    // Use service error so we can show failures originating from setSystemIcon retries

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Privacy style & Undo timeout
            HStack {
                Text("Privacy Screen Style")
                Spacer()
                Picker("", selection: $privacyBackgroundStyle) {
                    ForEach(PrivacyBackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: privacyBackgroundStyle) { _ in
                    // privacyBackgroundStyle is stored via AppStorage (shared key across views).
                    // AlbumManager doesn't own this setting; just trigger a save in case other settings changed.
                    albumManager.saveSettings()
                }
                .labelsHidden()
            }

            HStack {
                Text("Undo banner timeout")
                Spacer()
                Text("\(Int(undoTimeoutSeconds))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $undoTimeoutSeconds, in: 2...20, step: 1)

            Divider()

            // Security
            Text("Security").font(.headline)

            HStack {
                Text("Auto-lock timeout")
                Spacer()
                Text("\(Int(storedAutoLockTimeout))s").foregroundStyle(.secondary)
            }

            Slider(value: $storedAutoLockTimeout, in: 30...3600, step: 30)
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
                .disabled(false)

            // Auto-wipe & recovery key
            Toggle("Auto-wipe on repeated failed unlocks", isOn: Binding(
                get: { albumManager.autoWipeOnFailedAttemptsEnabled },
                set: { albumManager.autoWipeOnFailedAttemptsEnabled = $0; albumManager.saveSettings() }
            ))

            if albumManager.autoWipeOnFailedAttemptsEnabled {
                HStack {
                    Text("Wipe threshold")
                    Spacer()
                    Stepper("\(albumManager.autoWipeFailedAttemptsThreshold)", value: Binding(get: { albumManager.autoWipeFailedAttemptsThreshold }, set: { albumManager.autoWipeFailedAttemptsThreshold = $0; albumManager.saveSettings() }), in: 1...100)
                        .labelsHidden()
                }
            }

            Toggle("Enable Recovery Key", isOn: Binding(
                get: { albumManager.enableRecoveryKey },
                set: { albumManager.enableRecoveryKey = $0; albumManager.saveSettings() }
            ))

            Text("When enabled, the app keeps an encrypted recovery key to help recover an interrupted password-change operation. This is internal and does not display a recovery code in the menus — it is used only during password-change recovery.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Secure Deletion (Overwrite)", isOn: Binding(
                get: { albumManager.secureDeletionEnabled },
                set: { albumManager.secureDeletionEnabled = $0 }
            ))

            Text("When enabled, deleted files are overwritten 3 times. This is slower but more secure. Note: on modern devices (APFS / SSD) overwrites may not always guarantee physical erasure — see app documentation for details. Secure overwrite is limited to the first \(ByteCountFormatter.string(fromByteCount: CryptoConstants.maxSecureDeleteSize, countStyle: .file)) of each file; larger files will be removed but only the first chunk will be overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Text("Appearance").font(.headline)

            Toggle("Compact Layout", isOn: $storedCompactLayoutEnabled)
                .onChange(of: storedCompactLayoutEnabled) { _ in
                    albumManager.compactLayoutEnabled = storedCompactLayoutEnabled
                    albumManager.saveSettings()
                }

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

            Divider()
            Text("Camera").font(.headline)
            Toggle("Capture at max quality", isOn: $storedCameraMaxQuality)
                .onChange(of: storedCameraMaxQuality) { _ in
                    albumManager.cameraMaxQuality = storedCameraMaxQuality
                    albumManager.saveSettings()
                }

            Divider()
            Text("App Icon").font(.headline)
            HStack {
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
                .frame(maxWidth: 220)
                .onChange(of: uiSelectedAppIcon) { newValue in
                    // no-op; Set button in parent will apply
                }

                #if os(iOS)
                Button("Set") {
                    let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                    // Let the service drive the apply+retry behavior so failures are surfaced
                    // via appIconService.lastIconApplyError.
                    appIconService.select(iconName: selected)
                }
                .disabled(!UIApplication.shared.supportsAlternateIcons)
                .buttonStyle(.bordered)
                .controlSize(.small)
                #else
                Button("Set") {
                    let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                    appIconService.select(iconName: selected)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif
            }

            HStack {
                Text("Current icon")
                Spacer()
                Text(appIconService.selectedIconName.isEmpty ? "Default" : appIconService.selectedIconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if os(iOS)
                Button("Force apply") {
                    // Use the central AppIconService for force-apply so the retry/backoff and
                    // last-error publishing behavior is consistent with the regular Set flow.
                    let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                    // Clear previous error so user receives fresh status
                    appIconService.clearLastIconApplyError()

                    // Calling select will drive the same apply+retry logic already used by the Set button
                    appIconService.select(iconName: selected)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif
                // If we have a last apply error, expose an explicit Try again control
                if appIconService.lastIconApplyError != nil {
                    Button("Try again") {
                        // Re-attempt the same selection
                        let selected = (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                        appIconService.clearLastIconApplyError()
                        appIconService.select(iconName: selected)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

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
        .alert(isPresented: Binding(get: { appIconService.lastIconApplyError != nil }, set: { if !$0 { appIconService.clearLastIconApplyError() } })) {
            Alert(title: Text("App Icon"), message: Text(appIconService.lastIconApplyError ?? ""), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            uiSelectedAppIcon = appIconService.selectedIconName.isEmpty ? "AppIcon" : appIconService.selectedIconName

            // Diagnostics: if we don't have a runtime image and the asset lookup fails,
            // log a helpful message once on appear (avoid returning Void inside the view builder).
            if appIconService.runtimeMarketingImage == nil {
                #if os(iOS)
                if UIImage(named: "AppIcon") == nil {
                    AppLog.debugPublic("PreferencesSectionTop: No image named 'AppIcon' found in asset catalog. Consider adding a preview image (e.g., AppIconPreview or AppIcon-1024) or rely on runtimeMarketingImage.")
                }
                #endif
            }
        }
    }
}
