# SecretVault

SecretVault is a native macOS and iOS app for securely hiding photos and videos using strong, modern encryption. 

# Hopefully not pretend greenfield
I am not keeping things compatible with previous implementations. When that starts happening I will remove this line.

## Features

- **End-to-end encryption** – AES-256-GCM via CryptoKit; media and metadata are encrypted at rest.
- **Biometric unlock** – Touch ID / Face ID with an auto-generated strong password stored in Keychain.
- **Manual password option** – Use your own password instead of biometrics if you prefer.
- **Hide & restore** – Import from the Photos library, hide items, and restore them later when needed.
- **Video support** – Encrypt, decrypt and play videos directly in the app.
- **Search & organize** – Search by filename or album and use simple vault albums for grouping.
- **Batch actions** – Select multiple items to restore, export, or delete in one go.
- **Cross-platform sync** – iCloud Drive sync keeps your vault synchronized between macOS and iOS devices. Oh no, not this yet.

## Development Notes

### Technical Details: iCloud Sync

Currently the app uses local storage only. To enable iCloud sync between devices, you would need to join Apple's Developer Program and update the app's iCloud settings in the code.

## Build & Run

1. Open `SecretVault.xcodeproj` in Xcode (macOS 13 or later).
2. Select the `SecretVault` macOS app scheme.
3. Build and run with `⌘R` on your Mac.
4. On first launch, choose either:
   - **Biometric mode** – the app creates and stores a strong random password in Keychain; you unlock with Touch ID / Face ID.
   - **Manual password** – you set a password yourself (no recovery if forgotten).
5. Use the **"Hide Items"** button to select photos and videos from your library to add to the vault.

### iOS

1. Open `SecretVault.xcodeproj` in Xcode (iOS 15 or later).
2. Select the `SecretVault iOS` app scheme.
3. Build and run with `⌘R` on your iOS device or simulator.
4. **Note**: Currently uses local storage only (iCloud sync disabled for personal development teams).
5. Follow the same setup process as macOS.

### Release builds from the console

To produce a signed, optimized build for distribution, use the `Release` configuration instead of `Debug`:

```bash
cd /Users/marchage/source/repos/SecretVault

# Build Release configuration for macOS
xcodebuild \
   -project SecretVault.xcodeproj \
   -scheme SecretVault \
   -configuration Release \
   build

# Build Release configuration for iOS
xcodebuild \
   -project SecretVault.xcodeproj \
   -scheme "SecretVault iOS" \
   -configuration Release \
   -sdk iphoneos \
   build
```

- In **Release** builds all `#if DEBUG … #endif` code (including development-only reset actions that can wipe a vault) is **not compiled in**, so those destructive helpers are unavailable in production.

## Storage & Security (High Level)

- **macOS**: By default, encrypted media and metadata are stored under `~/Library/Application Support/SecretVault/` in the current user account.
- **iOS**: Currently uses local Documents directory (iCloud Drive sync disabled for personal development teams).
- You can optionally choose a custom vault folder (for example an iCloud Drive folder); the app then stores its encrypted vault inside a `SecretVault/` subfolder there.
- Encryption keys are derived from either the auto-generated password or your manual password.
- The app uses authenticated encryption (AES-256-GCM) so tampering with vault files is detected.
- Losing or forgetting the password means the vault contents cannot be recovered.

## iCloud Sync

**Note**: iCloud sync is currently turned off. The app works perfectly with local storage on each device - your vault stays secure but doesn't sync between devices.

If you want to enable syncing between your Mac and iPhone in the future, you'll need to update some settings in the code (see the Development Notes section below for technical details).

## License

Personal project. No warranty; use at your own risk.
