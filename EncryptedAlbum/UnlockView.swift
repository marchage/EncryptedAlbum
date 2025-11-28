import LocalAuthentication
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct UnlockView: View {
    @EnvironmentObject var albumManager: AlbumManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = "Incorrect password"
    @State private var biometricType: LABiometryType = .none
    @State private var autoBiometricWorkItem: DispatchWorkItem?
    @State private var hasAutoBiometricAttempted = false
    @State private var biometricsReady = false
    @AppStorage("stealthModeEnabled") private var stealthModeEnabled = false
    @State private var showFakeCrash = false

    private func appIconView() -> some View {
        #if os(macOS)
        if let appIcon = NSImage(named: "AppIcon") {
            // Force loading the 2x representation if available (512px for 256pt @2x)
            if let bitmapRep = appIcon.representations.first(where: { 
                ($0 as? NSBitmapImageRep)?.pixelsWide == 512 
            }) as? NSBitmapImageRep {
                let highResImage = NSImage(size: NSSize(width: 256, height: 256))
                highResImage.addRepresentation(bitmapRep)
                return AnyView(Image(nsImage: highResImage)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 256, maxHeight: 256)
                    // .padding(.top, 36)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
            } else {
                return AnyView(Image(nsImage: appIcon)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 256, maxHeight: 256)
                    // .padding(.top, 36)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
            }
        }
        return AnyView(EmptyView())
        #else
        // On iOS the AppIcon entries in AppIcon.appiconset are not always addressable
        // by filename. Try the generated "AppIcon" name first (other views use this),
        // and fall back to the marketing filename if available.
        // Helpful debug logging — no DEBUG guard required; AppLog handles gating.
        let attemptNames = ["AppIconMarketingRuntime", "AppIcon", "app-icon~ios-marketing"]

        // Try a runtime image set first (recommended). Fall back to AppIcon and marketing asset names.
        let appIcon = UIImage(named: "AppIconMarketingRuntime") ?? UIImage(named: "AppIcon") ?? UIImage(named: "app-icon~ios-marketing")
        if appIcon == nil {
            AppLog.debugPublic("UnlockView: could not load app icon using names: \(attemptNames)")
        } else {
            AppLog.debugPublic("UnlockView: loaded app icon using a fallback name")
        }
        if let appIcon = appIcon {
            return AnyView(Image(uiImage: appIcon)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 256, maxHeight: 256)
                // .padding(.top, 24)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
        }
        return AnyView(EmptyView())
        #endif
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer()

                        appIconView()

                        Text("Encrypted Album")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Enter your password to unlock")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                // allow the field to shrink on narrow devices (e.g. iPhone SE)
                                .frame(maxWidth: 300)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                #endif
                                .onSubmit {
                                    Task {
                                        await unlock()
                                    }
                                }

                            if showError {
                                Text(errorMessage)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.red.opacity(0.12))
                                    )
                                    .frame(maxWidth: 260)
                            }

                            HStack(spacing: 12) {
                                    // Choose sensible button sizing for compact layout vs roomy layout.
                                    // On compact layout we reduce controlSize and slightly reduce button widths.
                                    let compact = albumManager.compactLayoutEnabled

                                    if biometricType != .none {
                                        Button {
                                        cancelAutoBiometricScheduling()
                                        authenticateWithBiometrics()
                                    } label: {
                                        HStack {
                                            Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                                            Text(biometricType == .faceID ? "Use Face ID" : "Use Touch ID")
                                        }
                                        .frame(width: compact ? 120 : 145)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(compact ? .regular : .large)
                                }

                                Button {
                                    Task {
                                        await unlock()
                                    }
                                } label: {
                                    Text("Unlock")
                                        .frame(width: biometricType != .none ? (compact ? 140 : 145) : (compact ? 160 : 200))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(compact ? .regular : .large)
                                .disabled(password.isEmpty)
                            }
                            // Ensure there is at least a small inset so buttons aren't flush at the edges
                            // Respect user's compact layout setting - compact layout reduces padding.
                            .padding(.horizontal, albumManager.compactLayoutEnabled ? 6 : 10)
                        }

                        Spacer()

                        #if DEBUG
                            Button {
                                resetAlbumForDevelopment()
                            } label: {
                                Text("🔧 Reset Album (Dev)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                        #endif
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }

            if showFakeCrash {
                FakeCrashView()
                    .onLongPressGesture(minimumDuration: 1.5) {
                        withAnimation {
                            showFakeCrash = false
                        }
                    }
                    .zIndex(999)
            }
        }
        .background(Color.clear)
        .onAppear {
            if stealthModeEnabled {
                showFakeCrash = true
            }
            biometricsReady = checkBiometricAvailability()
            if scenePhase == .active && !showFakeCrash {
                scheduleAutoBiometricIfNeeded(isReady: biometricsReady)
            }
        }
        .onDisappear {
            cancelAutoBiometricScheduling()
            hasAutoBiometricAttempted = false
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if !showFakeCrash {
                    scheduleAutoBiometricIfNeeded(isReady: biometricsReady)
                }
            case .inactive, .background:
                cancelAutoBiometricScheduling()
                hasAutoBiometricAttempted = false
                if stealthModeEnabled {
                    showFakeCrash = true
                }
            @unknown default:
                break
            }
        }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if !showFakeCrash {
                    scheduleAutoBiometricIfNeeded(isReady: biometricsReady)
                }
            }
        #endif
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 36)
        }
    }

    @discardableResult
    private func checkBiometricAvailability() -> Bool {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
            return biometricType != .none
        }

        biometricType = .none
        return false
    }

    private func authenticateWithBiometrics() {
        cancelAutoBiometricScheduling()
        Task {
            do {
                // On both iOS and macOS, we now use SecAccessControl which handles the prompt
                let password = try await albumManager.authenticateAndRetrievePassword()
                self.password = password
                await unlock()
            } catch let error as AlbumError {
                switch error {
                case .biometricCancelled:
                    // User cancelled, do nothing
                    break
                case .biometricNotAvailable:
                    self.errorMessage = "Biometric authentication not available."
                    self.showError = true
                default:
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            } catch {
                self.errorMessage = "Biometric authentication failed."
                self.showError = true
            }
        }
    }

    private func unlock() async {
        do {
            // Normalize UI input so users aren't confused by composed/decomposed unicode forms
            let normalized = PasswordService.normalizePassword(password)
            // Update the field so the user sees the normalized value as confirmation
            password = normalized
            try await albumManager.unlock(password: normalized)
            showError = false
            errorMessage = "Incorrect password"
            #if os(macOS)
                await MainActor.run {
                    bringAppToFrontIfNeeded()
                }
            #endif
        } catch let error as AlbumError {
            errorMessage = error.localizedDescription
            showError = true
            password = ""
        } catch {
            errorMessage = "An unexpected error occurred"
            showError = true
            password = ""
        }
    }

    private func scheduleAutoBiometricIfNeeded(isReady: Bool) {
        guard isReady, scenePhase == .active, !hasAutoBiometricAttempted, autoBiometricWorkItem == nil else { return }
        hasAutoBiometricAttempted = true

        let workItem = DispatchWorkItem {
            guard scenePhase == .active else {
                hasAutoBiometricAttempted = false
                autoBiometricWorkItem = nil
                return
            }
            #if os(macOS)
                guard NSApplication.shared.isActive else {
                    hasAutoBiometricAttempted = false
                    autoBiometricWorkItem = nil
                    return
                }
            #endif
            authenticateWithBiometrics()
            autoBiometricWorkItem = nil
        }
        autoBiometricWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func cancelAutoBiometricScheduling() {
        autoBiometricWorkItem?.cancel()
        autoBiometricWorkItem = nil
    }

    #if os(macOS)
        @MainActor
        private func bringAppToFrontIfNeeded() {
            guard !NSApplication.shared.isActive else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    #endif

    #if DEBUG
        private func resetAlbumForDevelopment() {
            #if os(macOS)
                let alert = NSAlert()
                alert.messageText = "Reset Album? (Development)"
                alert.informativeText =
                    "This will delete all album data, the password, and return to setup. This action cannot be undone."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Reset Album")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    albumManager.nukeAllData()
                }
            #else
                // iOS implementation - dismiss keyboard first to avoid constraint conflicts
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                let alert = UIAlertController(
                    title: "Reset Album? (Development)",
                    message:
                        "This will delete all album data, the password, and return to setup. This action cannot be undone.",
                    preferredStyle: .alert
                )

                alert.addAction(
                    UIAlertAction(title: "Reset Album", style: .destructive) { _ in
                        albumManager.nukeAllData()
                    })

                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

                // Present the alert
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let window = windowScene.windows.first,
                    let rootViewController = window.rootViewController
                {
                    rootViewController.present(alert, animated: true)
                }
            #endif
        }
    #endif
}
