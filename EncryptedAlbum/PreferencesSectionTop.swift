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
    
    @State private var showPrivacyStyleSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Privacy style & Undo timeout
            // Use an in-app sheet for the privacy style selection rather than a system menu.
            // System menus sometimes render in a system overlay and can be positioned under
            // the status bar or other UI, making rows hard to tap. The sheet stays within
            // the app's view hierarchy and respects safe-area insets.
            HStack {
                Text("Privacy Screen Style")
                Spacer()
                Button(action: { showPrivacyStyleSheet = true }) {
                    HStack(spacing: 6) {
                        Text(privacyBackgroundStyle.displayName)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .sheet(isPresented: $showPrivacyStyleSheet) {
                    PrivacyStylePickerSheet(
                        selectedStyle: $privacyBackgroundStyle,
                        isPresented: $showPrivacyStyleSheet,
                        onSave: { albumManager.saveSettings() }
                    )
                }
                #else
                .popover(isPresented: $showPrivacyStyleSheet, arrowEdge: .bottom) {
                    PrivacyStylePickerSheet(
                        selectedStyle: $privacyBackgroundStyle,
                        isPresented: $showPrivacyStyleSheet,
                        onSave: { albumManager.saveSettings() }
                    )
                    .frame(width: 200, height: 480)
                }
                #endif
            }
            .padding(.top, 8)

            Text("Sets the app's visual theme and the background shown when the app is locked or switching away.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

            Text("The album will automatically lock after this many seconds without any taps, clicks, or interactions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Require Passcode On Launch", isOn: $storedRequirePasscodeOnLaunch)
                .onChange(of: storedRequirePasscodeOnLaunch) { _ in
                    albumManager.requirePasscodeOnLaunch = storedRequirePasscodeOnLaunch
                    albumManager.saveSettings()
                }

            HStack {
                Text("Biometric Policy")
                Spacer()
                Picker("", selection: $storedBiometricPolicy) {
                    Text("Prefer").tag("biometrics_preferred")
                    Text("Require").tag("biometrics_required")
                    Text("Disabled").tag("biometrics_disabled")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .onChange(of: storedBiometricPolicy) { _ in
                albumManager.biometricPolicy = storedBiometricPolicy
                albumManager.saveSettings()
            }

            Text(
                storedBiometricPolicy == "biometrics_preferred"
                    ? "Try Face ID / Touch ID first; if unavailable or cancelled, fall back to password."
                    : storedBiometricPolicy == "biometrics_required"
                        ? "Only biometrics can unlock. If unavailable, you cannot access the album."
                        : "Biometrics disabled. Password only."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle("Require Re-authentication on Return", isOn: $requireForegroundReauthentication)

            Text(
                "When enabled, switching away from the app (e.g., pressing Home or switching apps) will lock the album. You'll need to authenticate again when you return."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            // Auto-wipe & recovery key
            Toggle(
                "Auto-wipe after failed unlock attempts",
                isOn: Binding(
                    get: { albumManager.autoWipeOnFailedAttemptsEnabled },
                    set: {
                        albumManager.autoWipeOnFailedAttemptsEnabled = $0
                        albumManager.saveSettings()
                    }
                ))

            if albumManager.autoWipeOnFailedAttemptsEnabled {
                HStack {
                    Text("Failed attempts before wipe")
                    Spacer()
                    Stepper(
                        "\(albumManager.autoWipeFailedAttemptsThreshold) attempts",
                        value: Binding(
                            get: { albumManager.autoWipeFailedAttemptsThreshold },
                            set: {
                                albumManager.autoWipeFailedAttemptsThreshold = $0
                                albumManager.saveSettings()
                            }), in: 3...100
                    )
                    .labelsHidden()
                }

                Text(
                    "⚠️ DANGER: After \(albumManager.autoWipeFailedAttemptsThreshold) consecutive wrong passwords, ALL encrypted data will be permanently and irrecoverably deleted. This cannot be undone."
                )
                .font(.caption)
                .foregroundStyle(.red)
            } else {
                Text("When enabled, entering the wrong password too many times will permanently delete all album data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Enable Recovery Key",
                isOn: Binding(
                    get: { albumManager.enableRecoveryKey },
                    set: {
                        albumManager.enableRecoveryKey = $0
                        albumManager.saveSettings()
                    }
                ))

            Text(
                "When enabled, the app keeps an encrypted recovery key to help recover an interrupted password-change operation. This is internal and does not display a recovery code in the menus — it is used only during password-change recovery."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle(
                "Secure Deletion (Overwrite)",
                isOn: Binding(
                    get: { albumManager.secureDeletionEnabled },
                    set: { albumManager.secureDeletionEnabled = $0 }
                ))

            Text(
                "When enabled, deleted files are overwritten 3 times. This is slower but more secure. Note: on modern devices (APFS / SSD) overwrites may not always guarantee physical erasure — see app documentation for details. Secure overwrite is limited to the first \(ByteCountFormatter.string(fromByteCount: CryptoConstants.maxSecureDeleteSize, countStyle: .file)) of each file; larger files will be removed but only the first chunk will be overwritten."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            Text("Appearance").font(.headline)

            Toggle("Compact Layout", isOn: $storedCompactLayoutEnabled)
                .onChange(of: storedCompactLayoutEnabled) { _ in
                    albumManager.compactLayoutEnabled = storedCompactLayoutEnabled
                    albumManager.saveSettings()
                }

            Text("Reduces thumbnail size. Overall layout spacing remains similar.")
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

            Text("Changes the color of toolbar buttons and key interactive elements. Does not affect all text or links.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Text("Camera").font(.headline)
            Toggle("Capture at maximum quality", isOn: $storedCameraMaxQuality)
                .onChange(of: storedCameraMaxQuality) { _ in
                    albumManager.cameraMaxQuality = storedCameraMaxQuality
                    albumManager.saveSettings()
                }

            Text(
                storedCameraMaxQuality
                    ? "Photos and videos are captured at the device's highest resolution. Files will be larger but preserve maximum detail."
                    : "Photos and videos are captured at a balanced quality. Files will be smaller but may lose some detail."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            Text("App Icon").font(.headline)
            Text("Choose from ~20 alternative icons to make the app less recognizable or match your style.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        let selected =
                            (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                        // Use deferred selection to avoid the system alert dismissing settings
                        appIconService.selectDeferred(iconName: selected)
                    }
                    .disabled(!UIApplication.shared.supportsAlternateIcons)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                #else
                    Button("Set") {
                        let selected =
                            (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
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
                        let selected =
                            (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                        // Clear previous error so user receives fresh status
                        appIconService.clearLastIconApplyError()

                        // Force apply uses immediate selection (shows system alert but sometimes needed)
                        appIconService.select(iconName: selected)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                #endif
                // If we have a last apply error, expose an explicit Try again control
                if appIconService.lastIconApplyError != nil {
                    Button("Try again") {
                        // Re-attempt the same selection
                        let selected =
                            (uiSelectedAppIcon == "AppIcon" || uiSelectedAppIcon.isEmpty) ? nil : uiSelectedAppIcon
                        appIconService.clearLastIconApplyError()
                        appIconService.select(iconName: selected)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            #if os(iOS)
                Text(
                    "Note: iOS will only change the Home screen icon if alternate icons are declared in Info.plist (CFBundleAlternateIcons). If you don't see a system change, the app is using the default icon."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
                Text("On macOS this will update the Dock/window icon immediately for the chosen set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #endif
        }
        // Only present a modal alert for non-benign errors. User / system cancellations
        // are considered benign and will not show a modal alert (they remain available
        // in `lastIconApplyError` for diagnostic / retry purposes).
        .alert(
            isPresented: Binding(
                get: { appIconService.shouldPresentLastIconApplyError },
                set: { if !$0 { appIconService.clearLastIconApplyError() } })
        ) {
            Alert(
                title: Text("App Icon"), message: Text(appIconService.lastIconApplyError ?? ""),
                dismissButton: .default(Text("OK")))
        }
        .onAppear {
            uiSelectedAppIcon = appIconService.selectedIconName.isEmpty ? "AppIcon" : appIconService.selectedIconName

            // Diagnostics: if we don't have a runtime image and the asset lookup fails,
            // log a helpful message once on appear (avoid returning Void inside the view builder).
            if appIconService.runtimeMarketingImage == nil {
                #if os(iOS)
                    if UIImage(named: "AppIcon") == nil {
                        AppLog.debugPublic(
                            "PreferencesSectionTop: No image named 'AppIcon' found in asset catalog. Consider adding a preview image (e.g., AppIconPreview or AppIcon-1024) or rely on runtimeMarketingImage."
                        )
                    }
                #endif
            }
        }
    }
}

// MARK: - Privacy Style Picker Sheet

private struct PrivacyStylePickerSheet: View {
    @Binding var selectedStyle: PrivacyBackgroundStyle
    @Binding var isPresented: Bool
    var onSave: () -> Void
    
    private let allStyles: [PrivacyBackgroundStyle] = PrivacyBackgroundStyle.allCases.map { $0 }
    
    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(allStyles, id: \.rawValue) { style in
                Button {
                    selectedStyle = style
                    onSave()
                    isPresented = false
                } label: {
                    HStack {
                        Text(style.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if style == selectedStyle {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.001))
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                if style != allStyles.last {
                    Divider()
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 8)
        #else
        NavigationView {
            List {
                ForEach(allStyles, id: \.rawValue) { style in
                    Button {
                        selectedStyle = style
                        onSave()
                        isPresented = false
                    } label: {
                        HStack {
                            Text(style.displayName)
                            Spacer()
                            if style == selectedStyle {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                        }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Privacy Screen Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        #endif
    }
}
