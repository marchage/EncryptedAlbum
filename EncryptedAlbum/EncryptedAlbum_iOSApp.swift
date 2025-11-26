import SwiftUI
import UIKit

@main
struct EncryptedAlbumApp_iOS: App {
    @StateObject private var albumManager = AlbumManager.shared
    @StateObject private var screenshotBlocker = ScreenshotBlocker.shared
    @ObservedObject private var privacyCoordinator = UltraPrivacyCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

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
                    
                    // Privacy overlay for App Switcher
                    if scenePhase != .active && !privacyCoordinator.isTrustedModalActive {
                        PrivacyOverlayBackground()
                        VStack(spacing: 16) {
                            Image(systemName: "lock.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.white)
                            Text("Encrypted Album")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    
                    ScreenshotBlockerOverlay()
                        .environmentObject(screenshotBlocker)
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
            }
        }
    }
}

/// Controls screenshot/recording blocks using UIWindow.secure.
@MainActor
final class ScreenshotBlocker: ObservableObject {
    static let shared = ScreenshotBlocker()

    @Published private(set) var overlayVisible = false
    private var isBlocking = false

    private init() {}

    func enableBlocking() {
        guard !isBlocking else { return }
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
            if screenshotBlocker.overlayVisible {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Screen capture disabled")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Stop recording or screenshots to continue using Encrypted Album.")
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

// SecureWrapper moved to SecureWrapper.swift

