# EncryptedAlbum — macOS Share Extension

This folder contains a scaffolding macOS Share Extension for Encrypted Album. The provided
`ShareViewController.swift` is a minimal controller that accepts shared files and copies
them into the app group's `ImportInbox` so the main app can pick them up.

What you'll still need to do to make this extension functional inside Xcode:

1. Create a new macOS Share Extension target in your Xcode workspace and add these files
   to that target (Source files + Info.plist + entitlements). When you create a new target:
   - Choose the **macOS → App Extension → Share Extension** template (or create a basic target and set NSExtension info in Info.plist).
   - Set the extension bundle identifier (e.g. `com.example.EncryptedAlbum.ShareExtensionMac`).

2. App Group + entitlements
   - Create or reuse an App Group that both your main app and the extension can access (example: `group.biz.front-end.EncryptedAlbum`).
   - Add that App Group to the main app target and to the share extension target in Xcode.
   - Attach a provisioning profile that contains the App Group entitlement for both targets.
   - A simple entitlements template file is included: `ShareExtensionMac.entitlements` — edit the `$(APP_GROUP_ID)` placeholder to your App Group id.

3. Provisioning on Apple Developer portal
   - Add the App Group to your App ID(s) for both the main app and the extension (or create a new App ID for each).
   - Regenerate provisioning profiles (development / distribution) that include the App Group entitlement and install them locally.

4. Info.plist settings
   - The included `Info.plist` already contains `NSExtensionPointIdentifier = com.apple.share-services` and an `NSExtensionPrincipalClass` entry.
   - Make sure the `NSExtensionPrincipalClass` matches the class name for your view controller or set up a storyboard if you prefer a view-based extension.

5. Testing locally
   - The extension's runtime environment is different from the main app. You can test by sharing a file from Finder or other apps with the macOS share menu and choosing the extension.
   - The extension writes incoming files into the app group's `ImportInbox` directory so the main app (which should also have the same App Group entitlement) can discover and import them.

Security note
   - The extension respects the app's lockdown sentinel stored in the shared user defaults suite (app group). If Lockdown Mode is enabled, the extension will refuse to import and will show the user an alert.

If you'd like, I can:
 - Add an Xcode entitlements plist with a real App Group id filled in (if you tell me the exact string you want),
 - Add a sample storyboard or simple UI so the extension provides a visible confirmation screen,
 - Wire up unit/integration tests (requires target creation in Xcode to run in CI),
 - Or create a small shell script that validates the existence of the `ImportInbox` in your app group's container for debugging.

Happy to continue — tell me whether you want me to add entitlements with a specific App Group ID, a small storyboard UI, or tests next.
ShareExtensionMac (scaffold)
============================

This folder contains a basic scaffold for a macOS Share extension that copies incoming files or images into the app group's ImportInbox directory so the main app can process imported items.

How to use
1. In Xcode, create a new target: File → New → Target → macOS → App Extension → Share Extension.
6. On developer.apple.com, enable the App Groups capability for the new extension's App ID and regenerate provisioning profiles if you use manual provisioning.

Quick helper (local) — refresh provisioning cache and prompt Xcode to recreate profiles
----------------------------------------------------------
I added a small helper script you can run locally to clear your cached provisioning profiles and trigger Xcode to refresh/create new ones. It uses xcodebuild's -allowProvisioningUpdates, so Xcode will attempt to create profiles for the signed-in Apple account if it can.

Run from the repo root:

```bash
chmod +x scripts/refresh-profiles.sh
./scripts/refresh-profiles.sh
```

Notes:
- This requires Xcode to be signed in with an Apple ID that can create provisioning profiles for the given team (Admin/Agent privileges usually required).
- The script will backup your existing profiles to ~/Desktop/provisioning-backup. Use with care and only if you trust the machine you're running it on.
2. When Xcode creates the target, pick a bundle ID (e.g. biz.front-end.EncryptedAlbum.ShareExtensionMac).
3. Replace the generated sources with (or add) the files from this folder:
   - `ShareViewController.swift` — the main extension controller
   - `Info.plist` — extension properties (set PRODUCT_BUNDLE_IDENTIFIER for the new target)
   - `ShareExtension.entitlements` — includes the app group used by the app (update if you use a different group)
4. In the project Signing & Capabilities for the new macOS extension target, enable App Groups and add the group: `group.biz.front-end.EncryptedAlbum`.
5. On developer.apple.com, enable the App Groups capability for the new extension's App ID and regenerate provisioning profiles if you use manual/provisioning.
6. Add the extension target to the main app's App Group (same group) if you want the app to see the shared folder.

Notes
-----
- This is a scaffold (minimal). For a polished extension you will want to add proper UI flow, error handling, and user feedback.
- If you want me to add this target to the Xcode project file (.pbxproj) directly I can do that, but it modifies complex project state — I left it as files for you to add (safer).
