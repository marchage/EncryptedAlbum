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
            Group {
                if SecureWrapperConfig.disableSecureScreens {
                    content
                } else {
                    IOSSecureContainer(content: content)
                }
            }
            .ignoresSafeArea()
        #else
            content
                .overlay(InactiveAppOverlay())
        #endif
    }
}

#if os(iOS)
import UIKit

private enum SecureWrapperConfig {
    static let disableSecureScreens: Bool = {
        #if DEBUG
            if CommandLine.arguments.contains("--disable-secure-wrapper") {
                return true
            }
            if ProcessInfo.processInfo.environment["SECRET_VAULT_DISABLE_SECURE_WRAPPER"] == "1" {
                return true
            }
        #endif
        return false
    }()
}

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
    private let contentContainer = UIView()
    private let hostingController: UIHostingController<Content>

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
        secureField.borderStyle = .none
        secureField.insetsLayoutMarginsFromSafeArea = false
        secureField.translatesAutoresizingMaskIntoConstraints = true
        view = secureField
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .clear
        secureField.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: secureField.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: secureField.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: secureField.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: secureField.trailingAnchor)
        ])

        contentContainer.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    func update(rootView: Content) {
        hostingController.rootView = rootView
    }
}

private final class SecureContainerField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        borderStyle = .none
        clearsOnBeginEditing = false
        contentVerticalAlignment = .fill
        contentHorizontalAlignment = .fill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { false }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }

    override var textInputContextIdentifier: String? { nil }
}
#endif
