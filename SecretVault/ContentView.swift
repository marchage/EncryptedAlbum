import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var captureInProgress = false
    @State private var exportInProgress = false

    var body: some View {
        ZStack {
            if vaultManager.hasPassword() {
                if vaultManager.isUnlocked {
                    MainVaultView(
                        captureInProgress: $captureInProgress,
                        exportInProgress: $exportInProgress
                    )
                } else {
                    UnlockView()
                }
            } else {
                SetupPasswordView()
            }
            
            // Progress overlays stay visible even when locked
            if captureInProgress {
                ProgressOverlayPlaceholder(message: "Import in progress…")
            }
            if exportInProgress {
                ProgressOverlayPlaceholder(message: "Export in progress…")
            }
            if vaultManager.restorationProgress.isRestoring {
                RestorationProgressOverlay(progress: vaultManager.restorationProgress)
            }
        }
        #if os(macOS)
            .frame(minWidth: 900, minHeight: 600)
        #endif
        .id(vaultManager.viewRefreshId)  // Force view recreation when refreshId changes
    }
}

// MARK: - Progress Overlay Placeholder

private struct ProgressOverlayPlaceholder: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Operation continues in background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(.ultraThickMaterial)
            .cornerRadius(16)
            .shadow(radius: 18)
        }
        .transition(.opacity)
    }
}

private struct RestorationProgressOverlay: View {
    @ObservedObject var progress: RestorationProgress
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                if progress.totalItems > 0 {
                    ProgressView(value: Double(progress.processedItems), total: Double(max(progress.totalItems, 1)))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)
                }
                
                Text(progress.statusMessage.isEmpty ? "Restoring items…" : progress.statusMessage)
                    .font(.headline)
                
                if progress.totalItems > 0 {
                    Text("\(progress.processedItems) of \(progress.totalItems)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.ultraThickMaterial)
            .cornerRadius(16)
            .shadow(radius: 18)
        }
        .transition(.opacity)
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
