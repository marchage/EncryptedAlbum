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
