#!/bin/bash

echo "🔧 SecretVault iOS Setup Helper"
echo "================================"

# Check if Xcode project exists
if [ ! -f "SecretVault.xcodeproj/project.pbxproj" ]; then
    echo "❌ SecretVault.xcodeproj not found!"
    exit 1
fi

echo "✅ Xcode project found"

# Check if iOS files exist
if [ ! -f "SecretVault/SecretVaultApp_iOS.swift" ]; then
    echo "❌ SecretVaultApp_iOS.swift not found!"
    exit 1
fi

if [ ! -f "SecretVault/Info_iOS.plist" ]; then
    echo "❌ Info_iOS.plist not found!"
    exit 1
fi

if [ ! -f "SecretVault/SecretVault_iOS.entitlements" ]; then
    echo "❌ SecretVault_iOS.entitlements not found!"
    exit 1
fi

echo "✅ iOS app files found"

# Check entitlements content
if grep -q "iCloud.biz.front-end.SecretVault" "SecretVault/SecretVault_iOS.entitlements"; then
    echo "✅ iCloud entitlements configured"
else
    echo "❌ iCloud entitlements missing"
fi

echo ""
echo "📋 Next Steps in Xcode:"
echo "1. Open SecretVault.xcodeproj"
echo "2. Add iOS target: File → New → Target → iOS App"
echo "3. Name: 'SecretVault iOS'"
echo "4. Bundle ID: biz.front-end.SecretVault.iOS"
echo "5. Add files to target:"
echo "   - SecretVaultApp_iOS.swift"
echo "   - Info_iOS.plist"
echo "   - SecretVault_iOS.entitlements"
echo "   - All shared Swift files"
echo "6. In Signing & Capabilities:"
echo "   - Add iCloud capability"
echo "   - Enable 'iCloud Documents'"
echo "   - Container: iCloud.biz.front-end.SecretVault"
echo ""
echo "🎯 Ready to build iOS version!"