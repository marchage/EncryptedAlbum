# Secret Vault

A beautiful macOS app for securely hiding and encrypting photos and videos with military-grade encryption.

@NOTE-TO-SELF: include nice visuals!

## ✨ Features

### Security
- 🔐 **AES-256-GCM Encryption** - Military-grade encryption using CryptoKit
- 👆 **Touch ID/Face ID Support** - Biometric authentication for quick unlock
- 🔑 **Password Protection** - Secure password-based access
- 🚫 **Single Instance** - Prevents multiple app instances from corrupting vault

### Media Management
- 📸 **Hide Photos & Videos** - Automatically removes items from Photos app after encryption
- 🎬 **Full Video Support** - Encrypt, decrypt, and play videos directly in the app
- 🔍 **Search & Filter** - Search by filename, source album, or vault album
- 📤 **Batch Operations** - Select multiple items (Cmd+A) to restore, export, or delete
- 💾 **Export Without Restore** - Save decrypted items to any folder without adding back to Photos
- 🎯 **Selection Support** - Click to select, double-click to view, right-click for actions

### User Experience
- 🎨 **Beautiful SwiftUI Interface** - Clean, modern macOS design
- 🖼️ **Media Viewer** - Full-screen viewing for photos and videos
- 📊 **Thumbnail Generation** - Fast preview of encrypted photos and video thumbnails
- 🗑️ **Duplicate Detection** - Automatically find and remove duplicates
- 🔄 **Restore Items** - Put photos and videos back in your Photos library when needed

## 🚀 Quick Start

1. **Open the project in Xcode**
2. **Build and run** (⌘R)
3. **Set your master password** on first launch
4. **Hide items** by clicking "Hide Items" button
5. **Select photos and videos** from your Photos library to encrypt and hide

## 🔒 Security Features Explained

### AES-256-GCM Encryption
Your photos and videos are encrypted using the Advanced Encryption Standard with 256-bit keys in Galois/Counter Mode - the same encryption used by:
- Military and government agencies
- Banks and financial institutions
- Major cloud storage providers

**Why AES-256 is secure:**
- Virtually unbreakable with current technology
- Even with the original + encrypted media, attackers can't recover your password
- Authenticated encryption prevents tampering

### Touch ID/Face ID
- Password is securely stored in macOS Keychain
- Only accessible after biometric authentication
- Automatically prompts on unlock for convenience

## 📖 Usage Guide

### Hiding Photos
1. Click **"Hide Photos"** button
2. Select photos and videos from your Photos library
3. Items are encrypted and saved to vault
4. Items are automatically deleted from Photos app
5. Remember to empty "Recently Deleted" in Photos

### Restoring Items
- **Right-click** any item → "Restore to Library"
- Or select multiple (Cmd+A) → "Restore Selected"
- Choose restore options:
  - **Restore to Original Albums** - Recreates the original album structure
  - **Restore to New Album** - Put all items in a new album
  - **Just Add to Library** - Add directly to library without albums
- Items are decrypted and added back to Photos library

### Viewing & Playing
- **Double-click** any photo to view full-screen
- **Double-click** any video to play with controls
- Video player includes play/pause, scrubbing, and full-screen toggle

### Exporting Items
- Select items you want to export
- Click **"Export Selected"**
- Choose destination folder
- Items are saved as regular files (decrypted)

### Search
- Use the search bar to find items by name or album
- Searches in real-time as you type

## 🛠️ Technical Details

**Built with:**
- Swift & SwiftUI
- CryptoKit (AES-256-GCM)
- LocalAuthentication (Touch ID/Face ID)
- Photos framework
- AVFoundation/AVKit (video support)
- macOS 13.0+

**Encryption Method:**
- Password → SHA-256 → AES-256-GCM Key
- Each photo/video encrypted with nonce + ciphertext + authentication tag
- Photo thumbnails stored unencrypted for performance (only low-res previews)
- Video thumbnails generated from first frame

## ⚠️ Important Notes

1. **Remember your password** - There is NO password recovery. Lost password = lost photos/videos.
2. **Keep backups** - While encrypted, vault files are in `~/Library/Application Support/SecretVault/`
3. **Recently Deleted** - Items deleted from library go to Recently Deleted album. Empty it manually for complete removal.
4. **Encryption is strong** - Without the password, items are unrecoverable (this is a feature!)
5. **Video file sizes** - Large videos take longer to encrypt/decrypt but remain fully encrypted at rest

## 🗺️ Future Enhancements

- [ ] Album organization within vault
- [ ] Slideshow mode for viewing photos
- [ ] Cloud sync with end-to-end encryption
- [x] Video support ✅
- [ ] Photo/video metadata preservation
- [ ] Batch album management

## 📝 License

This is a personal project. Use at your own risk.

---

**Built with ❤️ using Swift and SwiftUI**
