import Foundation
import SwiftUI

/// Observable state for the vault
class VaultState: ObservableObject {
    // MARK: - Authentication State
    @Published var isUnlocked = false
    @Published var isBiometricAvailable = false
    @Published var isSettingUpPassword = false
    @Published var passwordSetupProgress: Double = 0.0

    // MARK: - Vault Content State
    @Published var hiddenPhotos: [SecurePhoto] = []
    @Published var isLoadingPhotos = false
    @Published var selectedPhoto: SecurePhoto?

    // MARK: - UI State
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false
    @Published var successMessage = ""

    // MARK: - Settings State
    @Published var vaultLocation: URL?
    @Published var idleTimeout: TimeInterval = CryptoConstants.idleTimeout
    @Published var biometricEnabled = false
    @Published var autoLockEnabled = true

    // MARK: - Security State
    @Published var securityHealthReport: SecurityHealthReport?
    @Published var lastSecurityCheck: Date?

    // MARK: - Operation State
    @Published var isPerformingOperation = false
    @Published var operationProgress: Double = 0.0
    @Published var operationDescription = ""

    // MARK: - Methods

    func showError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
        }
    }

    func showSuccess(_ message: String) {
        DispatchQueue.main.async {
            self.successMessage = message
            self.showSuccess = true
        }
    }

    func startOperation(description: String) {
        DispatchQueue.main.async {
            self.isPerformingOperation = true
            self.operationDescription = description
            self.operationProgress = 0.0
        }
    }

    func updateOperationProgress(_ progress: Double) {
        DispatchQueue.main.async {
            self.operationProgress = progress
        }
    }

    func endOperation() {
        DispatchQueue.main.async {
            self.isPerformingOperation = false
            self.operationDescription = ""
            self.operationProgress = 0.0
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.isUnlocked = false
            self.hiddenPhotos = []
            self.selectedPhoto = nil
            self.showError = false
            self.showSuccess = false
            self.isPerformingOperation = false
            self.securityHealthReport = nil
        }
    }
}
