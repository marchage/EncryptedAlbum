# SecretVault – Changes

This file tracks technical changes and implementation details that are too low-level for the main `README.md`.

## 2025-11-14 – Privacy Mode & Encrypted Thumbnails

### Privacy mode for grid previews

- Added a vault-wide privacy toggle in `MainVaultView`:
  - Backed by `@AppStorage("vaultPrivacyModeEnabled")`.
  - Default is `true`, so thumbnails are **hidden by default** on first run.
  - State is persisted per user and reused across launches.
- When privacy mode is **enabled**:
  - `PhotoThumbnailView` renders a neutral placeholder (no thumbnail loading).
  - No thumbnail files are read or decoded.
- When privacy mode is **disabled**:
  - `PhotoThumbnailView` loads and shows a thumbnail for each item.
  - Thumbnails are now backed by encrypted data (see below).
- Implementation details:
  - Privacy toggle is in the main toolbar next to the search field.
  - `PhotoThumbnailView` uses `onAppear` and `onChange(of: privacyModeEnabled)` so that:
    - Thumbnails load immediately when privacy is off.
    - If the view appeared while privacy was on, turning privacy off later triggers a thumbnail load.

### Encrypted per-item thumbnails

- Extended the `SecurePhoto` model in `VaultManager.swift`:
  - **New field:** `encryptedThumbnailPath: String?`.
  - Existing fields are preserved: `encryptedDataPath`, `thumbnailPath`, etc.
  - Initializer updated to accept `encryptedThumbnailPath` with a default of `nil` for backward compatibility.
- On hide/import (`VaultManager.hidePhoto(...)`):
  - For each item we now generate three files under the `photos` directory:
    - `UUID.enc` – full encrypted media (unchanged).
    - `UUID_thumb.jpg` – legacy unencrypted thumbnail (still written for compatibility).
    - `UUID_thumb.enc` – **new encrypted thumbnail**.
  - Flow:
    1. Encrypt original media with AES-256-GCM using a key derived from `passwordHash` and write `UUID.enc`.
    2. Generate a JPEG thumbnail from the original media (photo or first video frame) and write `UUID_thumb.jpg`.
    3. Encrypt the JPEG thumbnail using the same AES-256-GCM key and write `UUID_thumb.enc`.
    4. Save the `SecurePhoto` entry with `encryptedThumbnailPath` pointing to `UUID_thumb.enc`.
- New helper in `VaultManager`:
  - `func decryptThumbnail(for photo: SecurePhoto) throws -> Data`:
    - If `encryptedThumbnailPath` is set:
      - Reads and decrypts the encrypted thumbnail file.
    - Otherwise (older entries):
      - Falls back to reading the plain `thumbnailPath`.
- Grid thumbnail loading in `MainVaultView.swift`:
  - `PhotoThumbnailView` now has `@EnvironmentObject var vaultManager: VaultManager`.
  - `loadThumbnail()` calls `vaultManager.decryptThumbnail(for:)` instead of reading `photo.thumbnailPath` directly.
  - Decrypted thumbnail `Data` is converted to `NSImage` on the main actor.
- Deletion / cleanup:
  - `VaultManager.deletePhoto(_:)` and `removeDuplicates()` now also remove `encryptedThumbnailPath` if present, in addition to the main encrypted file and legacy thumbnail.

### Debug-only destructive actions

- The vault reset helpers remain **debug-only** and are excluded from Release builds:
  - In `UnlockView.swift` and `MainVaultView.swift`, "Reset Vault (Dev)" UI and corresponding methods are wrapped in `#if DEBUG ... #endif`.
  - Release configuration (`configuration = Release`) does not compile or ship this code.

### Release build notes

- Recommended release build command from the project root:

  ```bash
  cd /Users/marchage/source/repos/SecretVault

  xcodebuild \
    -project SecretVault.xcodeproj \
    -scheme SecretVault \
    -configuration Release \
    build
  ```

- Using `Release` ensures:
  - No `DEBUG`-gated dev helpers (e.g. vault reset) are present.
  - Privacy mode and encrypted thumbnails behave as described above.
