import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        ZStack {
            if vaultManager.hasPassword() {
                if vaultManager.isUnlocked {
                    MainVaultView(directImportProgress: vaultManager.directImportProgress)
                } else {
                    UnlockView()
                }
            } else {
                SetupPasswordView()
            }
        }
        #if os(macOS)
            .frame(minWidth: 900, minHeight: 600)
        #endif
        .id(vaultManager.viewRefreshId)  // Force view recreation when refreshId changes
    }
}
/// A view wrapper that prevents screenshots and screen recording on iOS.
/// On macOS, it passes the content through unchanged (as window-level protection is handled differently).
struct SecureWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        #if os(iOS)
            IOSSecureContainer(content: content)
        #else
            content
                .overlay(InactiveAppOverlay())
        #endif
    }
}

#if os(iOS)
import UIKit

private struct IOSSecureContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> SecureHostingController<Content> {
        SecureHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: SecureHostingController<Content>, context: Context) {
        uiViewController.update(rootView: content)
    }
}

private final class SecureHostingController<Content: View>: UIViewController {
    private let secureField = SecureContainerField()
    private let hostingController: UIHostingController<Content>
    private var hostedConstraints: [NSLayoutConstraint] = []

    init(rootView: Content) {
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        secureField.isSecureTextEntry = true
        secureField.backgroundColor = .clear
        view = secureField
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        attachHostedView()
        hostingController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachHostedView()
    }

    func update(rootView: Content) {
        hostingController.rootView = rootView
    }

    private func attachHostedView() {
        let container = secureField.subviews.first ?? secureField
        guard hostingController.view.superview !== container else { return }

        hostingController.view.removeFromSuperview()
        NSLayoutConstraint.deactivate(hostedConstraints)
        container.addSubview(hostingController.view)

        hostedConstraints = [
            hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }
}

private final class SecureContainerField: UITextField {
    override var canBecomeFirstResponder: Bool { false }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }

    override var textInputContextIdentifier: String? { nil }
}
#endif
