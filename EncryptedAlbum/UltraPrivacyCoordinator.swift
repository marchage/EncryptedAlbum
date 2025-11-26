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
            "albumPrivacyModeEnabled": true,
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
        AlbumManager.shared.prepareForBackground()
        if shouldRequireReauthentication {
            AlbumManager.shared.lock()
        }
    }

    private func handleDidEnterBackground(scene: UIScene?) {
        showImmediateCover(for: scene)
    }

    private func enforcePrivacyMode() {
        if defaults.bool(forKey: "albumPrivacyModeEnabled") == false {
            defaults.set(true, forKey: "albumPrivacyModeEnabled")
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
    var body: some View {
        ZStack {
            PrivacyOverlayBackground()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("Encrypted Album Locked")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
