import SwiftUI

#if os(macOS)
@MainActor
final class MacPrivacyCoordinator: ObservableObject {
    static let shared = MacPrivacyCoordinator()

    @Published private(set) var isTrustedModalActive = false
    private var modalDepth = 0

    func beginTrustedModal() {
        modalDepth += 1
        updateState()
    }

    func endTrustedModal() {
        modalDepth = max(modalDepth - 1, 0)
        updateState()
    }

    private func updateState() {
        let isActive = modalDepth > 0
        if isTrustedModalActive != isActive {
            isTrustedModalActive = isActive
        }
    }
}

struct InactiveAppOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowIsKey = true
    @State private var appIsActive = true
    @ObservedObject private var privacyCoordinator = MacPrivacyCoordinator.shared

    private var isObscured: Bool {
        guard !privacyCoordinator.isTrustedModalActive else { return false }
        let obscured = !appIsActive || scenePhase != .active || !windowIsKey
        return obscured
    }

    var body: some View {
        ZStack {
            if isObscured {
                PrivacyOverlayBackground()
                    .overlay(content: overlayContent)
                    .transition(.opacity)
                    .zIndex(9999) // Force top z-index
            }
        }
        .background(WindowFocusObserver(isKey: $windowIsKey))
        .animation(.easeInOut(duration: 0.25), value: isObscured)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true
        }
        .onAppear {
            appIsActive = NSApplication.shared.isActive
        }
    }

    @ViewBuilder
    private func overlayContent() -> some View {
        PrivacyContentOverlay()
    }
}

struct PrivacyContentOverlay: View {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .rainbow
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(style == .light ? .black : .white)
            
            Text("Encrypted Album is obscured")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(style == .light ? .black : .white)
        }
        .padding(24)
    }
}

private struct WindowFocusObserver: NSViewRepresentable {
    @Binding var isKey: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onKeyChange = { update in
            DispatchQueue.main.async {
                self.isKey = update
            }
        }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onKeyChange = { update in
            DispatchQueue.main.async {
                self.isKey = update
            }
        }
    }

    final class ObserverView: NSView {
        var onKeyChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()

            guard let window = window else {
                onKeyChange?(false)
                return
            }

            onKeyChange?(window.isKeyWindow)

            let center = NotificationCenter.default
            let become = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onKeyChange?(true)
            }

            let resign = center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onKeyChange?(false)
            }

            tokens.append(contentsOf: [become, resign])
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
#else
struct InactiveAppOverlay: View {
    var body: some View { EmptyView() }
}
#endif
