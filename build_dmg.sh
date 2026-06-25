#!/bin/bash

# Exit on any error
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MicTether"
SCHEME_NAME="MicTether"
DISPLAY_NAME="MicTether"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
DMG_PATH="${PROJECT_DIR}/${DISPLAY_NAME}.dmg"

echo "🧹 Cleaning up previous builds..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_PATH}"

echo "🔨 Building and Archiving..."
xcodebuild clean archive \
    -workspace "${PROJECT_DIR}/${APP_NAME}.xcodeproj/project.xcworkspace" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO | xcpretty || true

# If xcpretty is not installed, it will fallback to normal, but since it's an automation script, just skip xcpretty if not available.
if [ ! -d "${ARCHIVE_PATH}" ]; then
    xcodebuild clean archive \
        -workspace "${PROJECT_DIR}/${APP_NAME}.xcodeproj/project.xcworkspace" \
        -scheme "${SCHEME_NAME}" \
        -configuration Release \
        -archivePath "${ARCHIVE_PATH}" \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
fi

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Error: App not found in archive."
    exit 1
fi

echo "📦 Creating DMG directory structure in /tmp..."
TMP_WORKSPACE="/tmp/MicTether_$$"
DMG_SRC_FOLDER="${TMP_WORKSPACE}/dmg_src"
TMP_DMG="${TMP_WORKSPACE}/${APP_NAME}.dmg"

mkdir -p "${DMG_SRC_FOLDER}"

# Copy the custom icns if we have it
ICNS_PATH="${PROJECT_DIR}/MicTether/Resources/AppIcon.icns"
if [ -f "${ICNS_PATH}" ]; then
    cp "${ICNS_PATH}" "${DMG_SRC_FOLDER}/.VolumeIcon.icns"
    SetFile -c icnC "${DMG_SRC_FOLDER}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "${DMG_SRC_FOLDER}" 2>/dev/null || true
fi

# Copy the app to the source folder and rename it to the display name
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${DMG_SRC_FOLDER}/"
mv "${DMG_SRC_FOLDER}/${APP_NAME}.app" "${DMG_SRC_FOLDER}/${DISPLAY_NAME}.app"

# Create a symlink to Applications directory
ln -s /Applications "${DMG_SRC_FOLDER}/Applications"

echo "💿 Building DMG file..."
hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "${DMG_SRC_FOLDER}" -ov -format UDZO "${TMP_DMG}"

echo "📦 Moving DMG to project folder..."
cp "${TMP_DMG}" "${DMG_PATH}"

# Set the Finder icon for the DMG file itself
if [ -f "${ICNS_PATH}" ] && [ -f "${DMG_PATH}" ]; then
    echo "🎨 为 DMG 文件本身赋予自定义图标..."
    SWIFT_SCRIPT="${BUILD_DIR}/setIcon.swift"
    cat > "$SWIFT_SCRIPT" << 'EOF'
import Cocoa
let args = CommandLine.arguments
if args.count == 3 {
    let icon = NSImage(contentsOfFile: args[1])
    let success = NSWorkspace.shared.setIcon(icon, forFile: args[2], options: [])
    print(success ? "Icon set successfully" : "Failed to set icon")
}
EOF
    swift "$SWIFT_SCRIPT" "${ICNS_PATH}" "${DMG_PATH}" || true
fi

# Cleanup temp
rm -rf "${TMP_WORKSPACE}"

echo "✅ DMG package successfully created at: ${DMG_PATH}"
