# Secret Vault

A beautiful macOS app for securely hiding and encrypting photos and videos with military-grade encryption.

@NOTE-TO-SELF: include nice visuals!

## ✨ Features

### Security
- 🔐 **AES-256-GCM Encryption** - Military-grade encryption using CryptoKit
- 👆 **Touch ID/Face ID Support** - Biometric authentication with auto-generated passwords
- 🎲 **Auto-Generated Passwords** - Choose from 3 strong random passwords (16 chars, mixed case, numbers, symbols)
- 🔑 **Manual Password Option** - Set your own password with strength requirements
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
3. **Set up security** on first launch:
   - **With Touch ID/Face ID**: Choose from 3 auto-generated strong passwords (recommended)
   - **Manual**: Create your own password (min 8 chars, uppercase, number required)
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
- Auto-generates strong 16-character passwords
- Password is securely stored in macOS Keychain
- Only accessible after biometric authentication
- You never need to remember or type the password
- Can toggle to manual password if preferred

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

**Vault Storage:**
- Location: `~/Library/Application Support/SecretVault/`
- Structure:
  ```
  SecretVault/
  ├── vault.json          # Encrypted metadata (filenames, dates, albums, GPS, etc.)
  ├── password.hash       # SHA-256 hash of your password
  └── photos/
      ├── UUID.enc        # Encrypted photo/video data (AES-256-GCM)
      ├── UUID_thumb.jpg  # Unencrypted thumbnail (low-res preview)
      └── ...
  ```
- Files are encrypted with AES-256-GCM using your password-derived key
- Thumbnails are low-resolution previews only (not the full image)
- Metadata (GPS, dates, albums) is stored in encrypted vault.json
- Without your password, all `.enc` files are just random data

## 🔒 Vault Security Details

### What's Encrypted
- ✅ Full-resolution photos and videos (`*.enc` files)
- ✅ Metadata (filenames, dates taken, GPS coordinates, favorite status)
- ✅ Album information (source album, vault albums)

### What's NOT Encrypted
- ❌ Thumbnails (low-resolution previews only - ~200x200px)
- ❌ File count (visible in Finder)
- ❌ File sizes (attacker can see encrypted file sizes)

**Important**: Thumbnails are stored in the vault directory (`~/Library/Application Support/SecretVault/photos/`), **NOT in Photos.app**. They are completely invisible to Photos.app, Spotlight, and other apps. Only accessible by:
- Direct file system access to the vault folder
- The Secret Vault app itself

### Why This Design?
- **Thumbnails**: Need instant grid view without decrypting everything
- **Performance**: Decrypting hundreds of photos just to show thumbnails would be too slow
- **Trade-off**: Thumbnails reveal you have photos, but not the full content
- **Isolation**: Thumbnails are in app's private folder, not indexed or visible anywhere else
- **Security**: Full-resolution originals remain fully encrypted and unrecoverable without password

### Accessing Vault Files
```bash
# Navigate to vault directory
cd ~/Library/Application\ Support/SecretVault/

# List encrypted files
ls -lh photos/

# View vault metadata (encrypted)
cat vault.json  # Will show encrypted gibberish without decryption

# Thumbnails are viewable (low-res previews only)
open photos/some-uuid_thumb.jpg
```

### Backup & Portability
- Copy entire `SecretVault/` folder to backup vault
- Can transfer to another Mac (need same password)
- Cloud backup possible (files are encrypted, but consider privacy)
- Password in Keychain is NOT transferred - manual password needed on new Mac

## ⚠️ Important Notes

1. **Auto-Generated Password (Recommended)** - If using Touch ID/Face ID with auto-generated password, your vault is only accessible with biometric authentication on this Mac. Make note of your password if you need backup access.
2. **Manual Password** - If you set a manual password, remember it! There is NO password recovery.
3. **Vault Location** - Encrypted files stored in `~/Library/Application Support/SecretVault/`
4. **Backup Strategy** - Copy the entire `SecretVault/` folder to backup. Files remain encrypted and need your password to decrypt.
5. **Thumbnails** - Low-resolution thumbnails (~200x200px) are NOT encrypted for performance. Full originals are fully encrypted.
6. **Recently Deleted** - Items deleted from library go to Recently Deleted album. Empty it manually for complete removal.
7. **Encryption is strong** - Without the password, items are unrecoverable (this is a feature!)
8. **Video file sizes** - Large videos take longer to encrypt/decrypt but remain fully encrypted at rest
9. **Portability** - Can move vault to another Mac, but biometric password won't transfer - you'll need the actual password

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
