# SecretVault

SecretVault is a native macOS app for securely hiding photos and videos using strong, modern encryption.

## Features

- **End-to-end encryption** – AES-256-GCM via CryptoKit; media and metadata are encrypted at rest.
- **Biometric unlock** – Touch ID / Face ID with an auto-generated strong password stored in Keychain.
- **Manual password option** – Use your own password instead of biometrics if you prefer.
- **Hide & restore** – Import from the Photos library, hide items, and restore them later when needed.
- **Video support** – Encrypt, decrypt and play videos directly in the app.
- **Search & organize** – Search by filename or album and use simple vault albums for grouping.
- **Batch actions** – Select multiple items to restore, export, or delete in one go.

## Build & Run

1. Open `SecretVault.xcodeproj` in Xcode (macOS 13 or later).
2. Select the `SecretVault` macOS app scheme.
3. Build and run with `⌘R` on your Mac.
4. On first launch, choose either:
   - **Biometric mode** – the app creates and stores a strong random password in Keychain; you unlock with Touch ID / Face ID.
   - **Manual password** – you set a password yourself (no recovery if forgotten).
5. Use the **“Hide Items”** button to select photos and videos from your library to add to the vault.

### Release builds from the console

To produce a signed, optimized build for distribution, use the `Release` configuration instead of `Debug`:

```bash
cd /Users/marchage/source/repos/SecretVault

# Build Release configuration for the SecretVault app
xcodebuild \
   -project SecretVault.xcodeproj \
   -scheme SecretVault \
   -configuration Release \
   build
```

- In **Release** builds all `#if DEBUG … #endif` code (including development-only reset actions that can wipe a vault) is **not compiled in**, so those destructive helpers are unavailable in production.

## Storage & Security (High Level)

- Encrypted media and metadata are stored under `~/Library/Application Support/SecretVault/` in the current user account.
- Encryption keys are derived from either the auto-generated password or your manual password.
- The app uses authenticated encryption (AES-256-GCM) so tampering with vault files is detected.
- Losing or forgetting the password means the vault contents cannot be recovered.

## License

Personal project. No warranty; use at your own risk.
