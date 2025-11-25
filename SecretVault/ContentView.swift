import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        ZStack {
            if vaultManager.hasPassword() {
                if vaultManager.isUnlocked {
                    MainVaultView()
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

// MARK: - Secure Wrapper

/// A view wrapper that prevents screenshots and screen recording on iOS.
/// On macOS, it passes the content through unchanged (as window-level protection is handled differently).
struct SecureWrapper<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        #if os(iOS)
        IOSSecureView {
            content
        }
        #else
        content
            .overlay(InactiveAppOverlay())
        #endif
    }
}

#if os(iOS)
import UIKit

struct IOSSecureView<Content: View>: UIViewRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeUIView(context: Context) -> UIView {
        let secureField = SecureContainerField()
        secureField.isSecureTextEntry = true
        
        let hostingController = context.coordinator.hostingController
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Try to find the secure container (UITextLayoutCanvasView or similar)
        if let secureContainer = secureField.subviews.first {
            secureContainer.addSubview(hostingController.view)
            
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: secureContainer.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: secureContainer.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: secureContainer.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: secureContainer.trailingAnchor)
            ])
        } else {
            // Fallback if internal structure changes
            secureField.addSubview(hostingController.view)
             NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: secureField.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: secureField.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: secureField.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: secureField.trailingAnchor)
            ])
        }
        
        return secureField
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }
    
    class Coordinator {
        let hostingController: UIHostingController<Content>
        
        init(content: Content) {
            self.hostingController = UIHostingController(rootView: content)
        }
    }
    
    private class SecureContainerField: UITextField {
        override var canBecomeFirstResponder: Bool {
            return false
        }
        
        override func caretRect(for position: UITextPosition) -> CGRect {
            return .zero
        }
        
        override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
            return []
        }
        
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            return false
        }
    }
}
#endif
