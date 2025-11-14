# SecretVault – Changes

This file tracks technical changes and implementation details that are too low-level for the main `README.md`.

## 2025-11-14 – Privacy Mode, Encrypted Thumbnails & Vault Hardening

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

### Step-up authentication for sensitive operations

- Introduced a reusable "step-up" authentication helper in `VaultManager`:
  - `func requireStepUpAuthentication(completion: @escaping (Bool) -> Void)`.
  - If no password has been set yet (no `passwordHash`), the helper immediately returns `true` because there is nothing sensitive to protect.
  - Otherwise it first tries `LocalAuthentication` with `.deviceOwnerAuthentication`:
    - Uses Touch ID / Apple Watch / system password as configured on the Mac.
    - Presents the standard system auth sheet with the reason: "Authenticate to perform a sensitive vault operation.".
  - If device owner authentication is unavailable, it falls back to explicit password entry:
    - Presents an `NSAlert` with a secure text field.
    - Hashes the entered password the same way as `setupPassword`/`unlock` and compares it to `passwordHash`.
    - Calls the completion handler with `true` only when the hashes match.

### Authenticated vault location change with migration

- The "Choose Vault Folder…" action in `MainVaultView` is now treated as a high-risk operation and has been hardened:
  - Before doing anything, it calls `vaultManager.requireStepUpAuthentication`.
    - If step-up auth fails or is cancelled, the operation stops with no changes.
  - After successful auth, the user chooses a target base folder via `NSOpenPanel` as before.
  - A follow-up `NSAlert` explains what will happen and asks for explicit confirmation:
    - The app will copy the existing encrypted vault into a new `SecretVault` subfolder inside the chosen location.
    - If the location is synced (e.g. iCloud Drive), encrypted blobs (including encrypted thumbnails and metadata) will be synced there.
    - The old vault folder is left in place so the user can manually clean it up if desired.

- The implementation now performs a real migration instead of just changing `vaultBaseURL`:
  - Captures the old base directory (`oldBase = vaultManager.vaultBaseURL`).
  - Constructs the new base directory as `newBase = chosenFolder.appendingPathComponent("SecretVault", isDirectory: true)`.
  - Creates a `migration-in-progress` marker file in `newBase` to signal a non-completed move if something goes wrong.
  - Copies contents in a controlled way:
    - Ensures `newBase/photos` exists.
    - For every item in `oldBase/photos`, copies it into `newBase/photos`, replacing any existing files with the same name.
    - Copies `oldBase/hidden_photos.json` to `newBase/hidden_photos.json` if present, replacing any existing one.
    - Settings are **not** blindly copied; `settings.json` at the new location will be regenerated by `VaultManager` based on the in-memory state, including the updated `vaultBaseURL`.
  - Only after the copy completes without throwing an error:
    - Updates `vaultManager.vaultBaseURL` on the main thread to point at `newBase`.
    - Removes the `migration-in-progress` marker.

- Failure behavior and safety guarantees:
  - If any error is thrown during migration (directory creation, file copy, etc.):
    - The code removes the `migration-in-progress` marker if it exists.
    - It does **not** change `vaultBaseURL`; the vault continues to use the original location.
    - An `NSAlert` is shown stating that the move failed and providing the error's localized description.
  - The old vault folder is never deleted automatically.
    - This ensures that a partially migrated or failed move does not destroy the user's only copy.
    - Users can inspect and delete the old location manually after they are satisfied with the new setup.

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
