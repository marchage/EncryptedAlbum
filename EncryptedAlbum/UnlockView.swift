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

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()

                    // App Icon
                    #if os(macOS)
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .renderingMode(.original)
                                .interpolation(.high)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: 120, maxHeight: 120)
                                // .padding(.top, 36)
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        } else {
                            // Fallback to gradient circle with lock
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(maxWidth: 140)
                                    .padding(.top, 16)

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white)
                            }
                        }
                    #else
                        if let appIcon = UIImage(named: "AppIcon") {
                            Image(uiImage: appIcon)
                                .resizable()
                                .renderingMode(.original)
                                .interpolation(.high)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: 140, maxHeight: 140)
                                // .padding(.top, 24)
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        } else {
                            // Fallback to gradient circle with lock
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(maxWidth: 120)
                                // .padding(.top, 36)

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white)
                            }
                        }
                    #endif

                    Text("Encrypted Album")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Enter your password to unlock")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
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
                            if biometricType != .none {
                                Button {
                                    cancelAutoBiometricScheduling()
                                    authenticateWithBiometrics()
                                } label: {
                                    HStack {
                                        Image(systemName: biometricType == .faceID ? "faceid" : "touchid")
                                        Text(biometricType == .faceID ? "Use Face ID" : "Use Touch ID")
                                    }
                                    .frame(width: 145)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }

                            Button {
                                Task {
                                    await unlock()
                                }
                            } label: {
                                Text("Unlock")
                                    .frame(width: biometricType != .none ? 145 : 200)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(password.isEmpty)
                        }
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
        }
        .onAppear {
            biometricsReady = checkBiometricAvailability()
            if scenePhase == .active {
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
                scheduleAutoBiometricIfNeeded(isReady: biometricsReady)
            case .inactive, .background:
                cancelAutoBiometricScheduling()
                hasAutoBiometricAttempted = false
            @unknown default:
                break
            }
        }
        #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                scheduleAutoBiometricIfNeeded(isReady: biometricsReady)
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
            try await albumManager.unlock(password: password)
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
