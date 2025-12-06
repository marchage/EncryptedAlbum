import SwiftUI

#if os(iOS)
    import UIKit
#endif

#if os(iOS)
    @main
    struct EncryptedAlbumApp_iOS: App {
        @StateObject private var albumManager = AlbumManager.shared
        @StateObject private var screenshotBlocker = ScreenshotBlocker.shared
        @ObservedObject private var privacyCoordinator = UltraPrivacyCoordinator.shared
        @Environment(\.scenePhase) private var scenePhase
        @AppStorage("keepScreenAwakeWhileUnlocked") private var keepScreenAwakeWhileUnlocked: Bool = false

        init() {
            #if os(iOS)
                UltraPrivacyCoordinator.shared.start()
            #endif
        }

        var body: some Scene {
            WindowGroup {
                SecureWrapper {
                    ZStack {
                        ContentView()
                            .environmentObject(albumManager)
                            .environmentObject(screenshotBlocker)

                        // If the user requires passcode on launch and the album has a password,
                        // present the `UnlockView` modally above the content until unlocked.
                        if albumManager.requirePasscodeOnLaunch && albumManager.showUnlockPrompt
                            && !albumManager.isUnlocked
                        {
                            UnlockView()
                                .environmentObject(albumManager)
                                .zIndex(1000)
                                .transition(.opacity)
                        }

                        // Privacy overlay for App Switcher
                        if scenePhase != .active && !privacyCoordinator.isTrustedModalActive {
                            PrivacyOverlayBackground()
                            VStack(spacing: 16) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white)
                                Text("Obscura")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        ScreenshotBlockerOverlay()
                            .environmentObject(screenshotBlocker)
                    }
                    // Apply user-selected accent color across the top-level view
                    .accentColor(albumManager.accentColorResolved)
                    .tint(albumManager.accentColorResolved)

                    // Ensure AlbumManager is authoritative about idle state when app appears
                    .onAppear {
                        Task { @MainActor in
                            albumManager.updateSystemIdleState()
                        }
                    }
                    .onAppear {
                        screenshotBlocker.enableBlocking()
                    }
                    .onDisappear {
                        screenshotBlocker.disableBlocking()
                    }
                    .onChange(of: scenePhase) { newPhase in
                        if newPhase == .active {
                            albumManager.checkAppGroupInbox()
                        }
                    }
                    // System idle timer is managed centrally by AlbumManager (preferences + suspensions)
                }
            }
        }
    }
#endif

#if os(iOS)
    /// Controls screenshot/recording blocks using UIWindow.secure.
    @MainActor
    final class ScreenshotBlocker: ObservableObject {
        static let shared = ScreenshotBlocker()

        private enum Config {
            static let disableBlocking: Bool = {
                #if DEBUG
                    // Allow several debug toggles to align with existing secure-wrapper flags.
                    let args = CommandLine.arguments
                    let env = ProcessInfo.processInfo.environment

                    if args.contains("--disable-screen-blocker") || args.contains("--disable-secure-wrapper") {
                        return true
                    }

                    if env["SECRET_VAULT_DISABLE_SCREEN_BLOCKER"] == "1"
                        || env["SECRET_VAULT_DISABLE_SECURE_WRAPPER"] == "1"
                        || env["SECRET_VAULT_DISABLE_CAPTURE_OVERLAY"] == "1" {
                        return true
                    }
                #endif
                return false
            }()
        }

        /// Expose whether blocking is disabled (for overlay gating).
        static var isDisabled: Bool { Config.disableBlocking }

        @Published private(set) var overlayVisible = false
        private var isBlocking = false

        private init() {}

        func enableBlocking() {
            guard !isBlocking else { return }
            guard !Config.disableBlocking else {
                isBlocking = false
                overlayVisible = false
                return
            }
            isBlocking = true
            updateSecureFlag(true)
            subscribeToNotifications()
        }

        func disableBlocking() {
            guard isBlocking else { return }
            isBlocking = false
            updateSecureFlag(false)
            overlayVisible = false
            unsubscribeFromNotifications()
        }

        private func subscribeToNotifications() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenCaptureChanged),
                name: UIScreen.capturedDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applySecureFlag),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        private func unsubscribeFromNotifications() {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func screenCaptureChanged() {
            guard isBlocking else { return }
            guard !Config.disableBlocking else {
                overlayVisible = false
                return
            }
            overlayVisible = isAnyScreenCaptured()
        }

        @objc private func applySecureFlag() {
            guard isBlocking else { return }
            // updateSecureFlag(true) // Removed invalid call
        }

        private func updateSecureFlag(_ secure: Bool) {
            // This method relied on a non-existent API (window.isSecure).
            // We now use SecureView wrapper in the UI hierarchy instead.
        }

        private func isAnyScreenCaptured() -> Bool {
            if #available(iOS 16.0, *) {
                return UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .contains { $0.screen.isCaptured }
            } else {
                return UIScreen.screens.contains { $0.isCaptured }
            }
        }

    }

    struct ScreenshotBlockerOverlay: View {
        @EnvironmentObject private var screenshotBlocker: ScreenshotBlocker

        var body: some View {
            ZStack {
                if screenshotBlocker.overlayVisible && !ScreenshotBlocker.isDisabled {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Screen capture disabled")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Stop recording or screenshots to continue using Obscura.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: screenshotBlocker.overlayVisible)
        }
    }

#endif

// SecureWrapper moved to SecureWrapper.swift
