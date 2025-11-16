import SwiftUI
import LocalAuthentication
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct UnlockView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var password = ""
    @State private var showError = false
    @State private var biometricType: LABiometryType = .none
    
    var body: some View {
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
            
            Text("Secret Vault")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Enter your password to unlock")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        unlock()
                    }
                
                if showError {
                    Text("Incorrect password")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                
                HStack(spacing: 12) {
                    if biometricType != .none {
                        Button {
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
                        unlock()
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
                resetVaultForDevelopment()
            } label: {
                Text("🔧 Reset Vault (Dev)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .ignoresSafeArea(.keyboard)
        #endif
        .onAppear {
            checkBiometricAvailability()
            // Auto-trigger biometric authentication if available
            if biometricType != .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    authenticateWithBiometrics()
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 36)
        }
    }
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        let reason = "Unlock your Secret Vault"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    // User authenticated successfully - get stored password
                    if let storedPassword = vaultManager.getBiometricPassword() {
                        password = storedPassword
                        unlock()
                    }
                } else {
                    // Authentication failed
                    if let error = error as? LAError {
                        switch error.code {
                        case .userCancel, .userFallback:
                            // User cancelled or wants to use password
                            break
                        default:
                            showError = true
                        }
                    }
                }
            }
        }
    }
    
    private func unlock() {
        if vaultManager.unlock(password: password) {
            showError = false
        } else {
            showError = true
            password = ""
        }
    }
    
    #if DEBUG
    private func resetVaultForDevelopment() {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Reset Vault? (Development)"
        alert.informativeText = "This will delete all vault data, the password, and return to setup. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset Vault")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Delete all vault files from the correct vault location
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: vaultManager.vaultBaseURL)
            print("Deleted vault directory: \(vaultManager.vaultBaseURL.path)")
            
            // Delete password hash from UserDefaults
            UserDefaults.standard.removeObject(forKey: "passwordHash")
            
            // Delete Keychain entries (both regular and biometric passwords)
            let keychainQueries = [
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.secretvault.password"
                ],
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: "SecretVault.BiometricPassword"
                ]
            ]
            
            for query in keychainQueries {
                SecItemDelete(query as CFDictionary)
            }
            
            // Reset vault manager state
            vaultManager.passwordHash = ""
            vaultManager.objectWillChange.send() // Immediate notification
            vaultManager.isUnlocked = false
            vaultManager.hiddenPhotos = []
            vaultManager.saveSettings() // Persist the empty state
            
            // Force view refresh
            vaultManager.viewRefreshId = UUID()
        }
        #else
        // iOS implementation - dismiss keyboard first to avoid constraint conflicts
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        let alert = UIAlertController(
            title: "Reset Vault? (Development)",
            message: "This will delete all vault data, the password, and return to setup. This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Reset Vault", style: .destructive) { _ in
            // Delete all vault files from the correct iOS location
            let fileManager = FileManager.default
            
            // Delete from iCloud if available
            if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
                let vaultDirectory = iCloudURL.appendingPathComponent("SecretVault", isDirectory: true)
                try? fileManager.removeItem(at: vaultDirectory)
                print("Deleted vault from iCloud: \(vaultDirectory.path)")
            }
            
            // Also delete from local documents as fallback
            if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let vaultDirectory = documentsURL.appendingPathComponent("SecretVault", isDirectory: true)
                try? fileManager.removeItem(at: vaultDirectory)
                print("Deleted vault from local documents: \(vaultDirectory.path)")
            }
            
            // Delete password hash from UserDefaults
            UserDefaults.standard.removeObject(forKey: "passwordHash")
            
            // Delete Keychain entries (both regular and biometric passwords)
            let keychainQueries = [
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.secretvault.password"
                ],
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: "SecretVault.BiometricPassword"
                ]
            ]
            
            for query in keychainQueries {
                SecItemDelete(query as CFDictionary)
            }
            
            // Reset vault manager state
            vaultManager.passwordHash = ""
            vaultManager.objectWillChange.send() // Immediate notification
            vaultManager.isUnlocked = false
            vaultManager.hiddenPhotos = []
            vaultManager.saveSettings() // Persist the empty state
            
            // Force view refresh
            vaultManager.viewRefreshId = UUID()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
        #endif
    }
    #endif
}
