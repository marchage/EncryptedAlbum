# Secret Vault

A beautiful macOS app - true - for securely hiding and encrypting photos with military-grade encryption.

(@NOTE-TO-SELF: include nice visuals! Explain biometrecs usage here in combination with for example a super simple code)

## ✨ Features

### Security
- 🔐 **AES-256-GCM Encryption** - Military-grade encryption using CryptoKit
- 👆 **Touch ID/Face ID Support** - Biometric authentication for quick unlock
- 🔑 **Password Protection** - Secure password-based access
- 🚫 **Single Instance** - Prevents multiple app instances from corrupting vault

### Photo Management
- 📸 **Hide Photos from Library** - Automatically removes photos from Photos app after encryption
- 🔍 **Search & Filter** - Search by filename, source album, or vault album
- 📤 **Batch Operations** - Select multiple photos (Cmd+A) to restore, export, or delete
- 💾 **Export Without Restore** - Save decrypted photos to any folder without adding back to Photos
- 🎯 **Selection Support** - Click to select, double-click to view, right-click for actions

### User Experience
- 🎨 **Beautiful SwiftUI Interface** - Clean, modern macOS design
- 🖼️ **Photo Viewer** - Full-screen photo viewing
- 📊 **Thumbnail Generation** - Fast preview of encrypted photos
- 🗑️ **Duplicate Detection** - Automatically find and remove duplicate photos
- 🔄 **Restore Photos** - Put photos back in your Photos library when needed

## 🚀 Quick Start

1. **Open the project in Xcode**
2. **Build and run** (⌘R)
3. **Set your master password** on first launch
4. **Hide photos** by clicking "Hide Photos" button
5. **Select photos** from your Photos library to encrypt and hide

## 🔒 Security Features Explained

### AES-256-GCM Encryption
Your photos are encrypted using the Advanced Encryption Standard with 256-bit keys in Galois/Counter Mode - the same encryption used by:
- Military and government agencies
- Banks and financial institutions
- Major cloud storage providers

**Why AES-256 is secure:**
- Virtually unbreakable with current technology
- Even with the original + encrypted photo, attackers can't recover your password
- Authenticated encryption prevents tampering

### Touch ID/Face ID
- Password is securely stored in macOS Keychain
- Only accessible after biometric authentication
- Automatically prompts on unlock for convenience

## 📖 Usage Guide

### Hiding Photos
1. Click **"Hide Photos"** button
2. Select photos from your Photos library
3. Photos are encrypted and saved to vault
4. Photos are automatically deleted from Photos app
5. Remember to empty "Recently Deleted" in Photos

### Restoring Photos
- **Right-click** any photo → "Restore to Photos"
- Or select multiple (Cmd+A) → "Restore Selected"
- Photos are decrypted and added back to Photos library

### Exporting Photos
- Select photos you want to export
- Click **"Export Selected"**
- Choose destination folder
- Photos are saved as regular image files (decrypted)

### Search
- Use the search bar to find photos by name or album
- Searches in real-time as you type

## 🛠️ Technical Details

**Built with:**
- Swift & SwiftUI
- CryptoKit (AES-256-GCM)
- LocalAuthentication (Touch ID/Face ID)
- Photos framework
- macOS 13.0+

**Encryption Method:**
- Password → SHA-256 → AES-256-GCM Key
- Each photo encrypted with nonce + ciphertext + authentication tag
- Thumbnails stored unencrypted for performance (only low-res previews)

## ⚠️ Important Notes

1. **Remember your password** - There is NO password recovery. Lost password = lost photos.
2. **Keep backups** - While encrypted, vault files are in `~/Library/Application Support/SecretVault/`
3. **Recently Deleted** - Photos deleted from library go to Recently Deleted album. Empty it manually for complete removal.
4. **Encryption is strong** - Without the password, photos are unrecoverable (this is a feature!)

## 🗺️ Future Enhancements

- [ ] Album organization within vault
- [ ] Slideshow mode for viewing photos
- [ ] Cloud sync with end-to-end encryption
- [ ] Video support
- [ ] Photo metadata preservation
- [ ] Batch album management

## 📝 License

This is a personal project. Use at your own risk.

---

**Built with ❤️ using Swift and SwiftUI**
