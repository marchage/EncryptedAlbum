#if os(iOS)
import Combine
import SwiftUI
import UIKit

/// Coordinates the immediate hardware-level privacy cover and background sanitization tasks.

@MainActor
final class UltraPrivacyCoordinator: ObservableObject {
    static let shared = UltraPrivacyCoordinator()

    private let defaults = UserDefaults.standard
    private var overlayWindow: UIWindow?
    private var hostingController: UIHostingController<UltraPrivacyCoverView>?
    private var observers: [NSObjectProtocol] = []
    private var trustedModalDepth: Int = 0 {
        didSet {
            let isActive = trustedModalDepth > 0
            if isTrustedModalActive != isActive {
                isTrustedModalActive = isActive
                if isActive {
                    hideImmediateCover()
                }
            }
        }
    }

    @Published private(set) var isTrustedModalActive = false

    private init() {}

    /// Sets up observers and primes the overlay window so it can be shown without delay.
    func start() {
        guard observers.isEmpty else { return }
        registerDefaults()
        registerObservers()
        primeOverlayWindowIfPossible()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            "vaultPrivacyModeEnabled": true,
            "requireForegroundReauthentication": true,
        ])
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        addObserver(center, name: UIScene.willDeactivateNotification) { coordinator, note in
            coordinator.handleWillDeactivate(scene: note.object as? UIScene)
        }

        addObserver(center, name: UIScene.didActivateNotification) { coordinator, _ in
            coordinator.hideImmediateCover()
        }

        addObserver(center, name: UIScene.didEnterBackgroundNotification) { coordinator, note in
            coordinator.handleDidEnterBackground(scene: note.object as? UIScene)
        }

        addObserver(center, name: UIScene.willEnterForegroundNotification) { coordinator, note in
            coordinator.primeOverlayWindowIfPossible(for: note.object as? UIScene)
        }

        addObserver(center, name: UIApplication.willResignActiveNotification) { coordinator, _ in
            coordinator.handleWillDeactivate(scene: nil)
        }
    }

    private func addObserver(
        _ center: NotificationCenter, name: Notification.Name,
        handler: @escaping @MainActor (UltraPrivacyCoordinator, Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            MainActor.assumeIsolated {
                handler(self, note)
            }
        }
        observers.append(token)
    }

    private func handleWillDeactivate(scene: UIScene?) {
        showImmediateCover(for: scene)
        enforcePrivacyMode()
        VaultManager.shared.prepareForBackground()
        if shouldRequireReauthentication {
            VaultManager.shared.lock()
        }
    }

    private func handleDidEnterBackground(scene: UIScene?) {
        showImmediateCover(for: scene)
    }

    private func enforcePrivacyMode() {
        if defaults.bool(forKey: "vaultPrivacyModeEnabled") == false {
            defaults.set(true, forKey: "vaultPrivacyModeEnabled")
        }
    }

    private func showImmediateCover(for scene: UIScene?) {
        guard !isTrustedModalActive else { return }
        primeOverlayWindowIfPossible(for: scene)
        guard let overlayWindow = overlayWindow else { return }
        overlayWindow.isHidden = false
        overlayWindow.alpha = 1
    }

    private func hideImmediateCover() {
        overlayWindow?.isHidden = true
    }

    private func primeOverlayWindowIfPossible(for scene: UIScene? = nil) {
        let targetScene = resolveScene(from: scene)
        guard let windowScene = targetScene else { return }
        if let existingWindow = overlayWindow, existingWindow.windowScene === windowScene {
            return
        }

        let hosting = UIHostingController(rootView: UltraPrivacyCoverView())
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.isHidden = true
        window.isUserInteractionEnabled = false
        window.rootViewController = hosting

        overlayWindow = window
        hostingController = hosting
    }

    private func resolveScene(from scene: UIScene?) -> UIWindowScene? {
        if let windowScene = scene as? UIWindowScene {
            return windowScene
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState != .unattached })
    }

    private var shouldRequireReauthentication: Bool {
        defaults.bool(forKey: "requireForegroundReauthentication") && !isTrustedModalActive
    }

    func beginTrustedModal() {
        trustedModalDepth += 1
    }

    func endTrustedModal() {
        trustedModalDepth = max(trustedModalDepth - 1, 0)
        if trustedModalDepth == 0 {
            hideImmediateCover()
        }
    }
}

private struct UltraPrivacyCoverView: View {
    @ObservedObject private var vaultManager = VaultManager.shared

    private var overlayIconName: String {
        vaultManager.authenticationPromptActive ? "lock.circle.fill" : "eye.slash.fill"
    }

    var body: some View {
        ZStack {
            PrivacyOverlayBackground()
            VStack(spacing: 16) {
                Image(systemName: overlayIconName)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
                Text("SecretVault Locked")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Return to the app to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
#endif
