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
        // Prefer the running application's icon first (it reflects the
        // actual icon macOS is using at runtime). Fall back to named AppIcon
        // resources if for some reason the runtime icon is not available.
        if let runtimeIcon = NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
            // Prefer the highest-resolution representation available (ideally 1024px)
            // so the icon renders crisply at larger sizes, but avoid forcing a
            // small rounded corner at 26px which makes the asset look baked-in.
            if let bestRep = runtimeIcon.representations
                .compactMap({ $0 as? NSBitmapImageRep })
                .sorted(by: { $0.pixelsWide > $1.pixelsWide })
                .first
            {
                let px = bestRep.pixelsWide
                // create a target image scaled appropriately to avoid odd scaling artifacts
                let size = NSSize(width: px/2, height: px/2)
                let highResImage = NSImage(size: size)
                highResImage.addRepresentation(bestRep)
                return AnyView(Image(nsImage: highResImage)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 256, maxHeight: 256)
                    // Do not force a large corner radius here — prefer the icon
                    // to render as bundled. If the asset is pre-rounded, showing
                    // it as-is avoids the repeated rounded look.
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
            } else {
                return AnyView(Image(nsImage: runtimeIcon)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 256, maxHeight: 256)
                    // Show runtime icon as-is (no forced corner radius)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
            }
        }
        // If we couldn't load an app icon, fall back to a friendly lock symbol
        return AnyView(
            Image(systemName: "lock.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        #else
        // On iOS the AppIcon entries in AppIcon.appiconset are not always addressable
        // by filename. Try the generated "AppIcon" name first (other views use this),
        // and fall back to the marketing filename if available.
        // Helpful debug logging — no DEBUG guard required; AppLog handles gating.
        // Prefer generated AppIcon entries and the high-res 1024 file if present.
        // Avoid preferring the 512@2x 'marketing' asset because it often includes
        // rounded corners baked-in which gives the same rounded corner every time.
        let attemptNames = ["AppIcon", "AppIcon-1024", "AppIcon1024", "AppIcon-512@2x"]

        // First try to load explicit high-resolution bundle files (preferred):
        // check common large filenames first so we get the true full-res PNG instead
        // of an image set resolution that may be lower.
        let bundleAttemptNames = ["AppIcon-1024", "AppIcon-512@2x", "AppIcon1024", "AppIcon-512"]
        var appIcon: UIImage? = nil
        for name in bundleAttemptNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data, scale: UIScreen.main.scale)
            {
                appIcon = img
                AppLog.debugPublic("UnlockView: loaded high-res app icon from bundle file \(name).png")
                break
            }
        }

        // If we still don't have an explicit bundle PNG, fall back to UIImage(named:)
        if appIcon == nil {
            appIcon = attemptNames.compactMap { UIImage(named: $0) }.first
        }

        // If appIcon is nil here, we'll log and return an EmptyView later.
        func isHighRes(_ img: UIImage?) -> Bool {
            guard let img = img else { return false }
            // Prefer at least 512px on the longest side for crisp rendering in our 256pt frame
            let px = max(img.size.width * img.scale, img.size.height * img.scale)
            return px >= 512.0
        }

        if !isHighRes(appIcon) {
            let bundleNames = ["AppIcon-1024", "AppIcon1024"]
            for name in bundleNames {
                if let url = Bundle.main.url(forResource: name, withExtension: "png"),
                   let data = try? Data(contentsOf: url),
                   // Use screen scale so the image reports correct scale
                   let img = UIImage(data: data, scale: UIScreen.main.scale) {
                    appIcon = img
                    AppLog.debugPublic("UnlockView: loaded high-res app icon from bundle file \(name).png")
                    break
                }
            }
        } else if appIcon != nil {
            AppLog.debugPublic("UnlockView: loaded app icon using a runtime asset name")
        } else {
            AppLog.debugPublic("UnlockView: could not load app icon using names: \(attemptNames)")
        }

        if let appIcon = appIcon {
            // Constrain icon size on phones so it doesn't dominate the screen.
            #if os(iOS)
                let maxDimension = min(256, UIScreen.main.bounds.width * 0.35)
            #else
                let maxDimension: CGFloat = 256
            #endif

            return AnyView(Image(uiImage: appIcon)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: maxDimension, maxHeight: maxDimension)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5))
        }
        // If no app icon could be loaded, show a neutral lock symbol instead of an empty view
        return AnyView(
            Image(systemName: "lock.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 120, maxHeight: 120)
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
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

                            // Test hook: expose an invisible control for UI tests to fill the
                            // password field deterministically (avoids relying on keyboard focus).
                            if ProcessInfo.processInfo.arguments.contains("--ui-tests") {
                                Button(action: {
                                    password = ProcessInfo.processInfo.environment["UI_TEST_PASSWORD"] ?? "TestPass123!"
                                }) {
                                    Text("")
                                }
                                .accessibilityIdentifier("test.fillUnlockPassword")
                                .frame(width: 1, height: 1)
                                .opacity(0.001)
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
                                        .frame(width: compact ? 110 : 130)
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
                                        .frame(width: biometricType != .none ? (compact ? 130 : 140) : (compact ? 150 : 180))
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
        let manager: AlbumManager = albumManager
        Task {
            do {
                // Clear suppression — user explicitly tapped the biometric button so we should
                // allow biometric flow even if the album was manually locked previously.
                manager.clearSuppressAutoBiometric()

                // On both iOS and macOS, we now use SecAccessControl which handles the prompt
                let password = try await manager.authenticateAndRetrievePasswordPublic()
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
        // User actively attempting to unlock — clear suppression so future auto-biometric attempts
        // are again permitted in standard circumstances.
        let manager: AlbumManager = albumManager
        manager.clearSuppressAutoBiometric()

        do {
            // Normalize UI input so users aren't confused by composed/decomposed unicode forms
            let normalized = PasswordService.normalizePassword(password)
            // Update the field so the user sees the normalized value as confirmation
            password = normalized
            try await manager.unlock(password: normalized)
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
        // Avoid scheduling automatic biometric if the user manually locked the album and we
        // intentionally suppressed auto-biometrics to avoid surprising prompts.
        guard isReady, scenePhase == .active, !hasAutoBiometricAttempted, autoBiometricWorkItem == nil,
              !albumManager.suppressAutoBiometricAfterManualLock else { return }
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
