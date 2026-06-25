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

# ============================================================================
# Developer ID 签名（公开分发）：硬化运行时 + 安全时间戳 + 沙盒 entitlements。
# 自动选取钥匙串中的 "Developer ID Application" 身份；缺失则降级 ad-hoc（仅本机自用）。
# 注：公证(notarization)需 Apple 凭据，本脚本不做——公开分发前请自行 `xcrun notarytool submit`。
# 可用 MICTETHER_SIGN_ID 环境变量覆盖签名身份。
# ============================================================================
# 沙盒真相源是 project.yml 的 ENABLE_APP_SANDBOX=YES；未签名归档不带 entitlements，
# 故在此合成签名 entitlements(仅沙盒一项,与构建设置一致),构建产物不入库,不触碰源 entitlements 文件。
SIGN_ENTITLEMENTS="${BUILD_DIR}/sign.entitlements"
cat > "${SIGN_ENTITLEMENTS}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
EOF

SIGN_ID="${MICTETHER_SIGN_ID:-$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed -E 's/^[^"]*"([^"]*)".*$/\1/')}"

if [ -n "${SIGN_ID}" ]; then
    echo "🔏 Developer ID 签名: ${SIGN_ID}"
    codesign --force --options runtime --timestamp \
        --entitlements "${SIGN_ENTITLEMENTS}" \
        --sign "${SIGN_ID}" "${APP_PATH}"
else
    echo "⚠️  未找到 Developer ID Application 证书，回退 ad-hoc 签名（仅本机自用，公开分发会被 Gatekeeper 拦截）"
    codesign --force --options runtime \
        --entitlements "${SIGN_ENTITLEMENTS}" \
        --sign - "${APP_PATH}"
fi

echo "🔎 验证签名..."
codesign --verify --strict --verbose=2 "${APP_PATH}"

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
# (同名时跳过 rename——mv X X 会报 "Invalid argument")
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${DMG_SRC_FOLDER}/"
if [ "${APP_NAME}" != "${DISPLAY_NAME}" ]; then
    mv "${DMG_SRC_FOLDER}/${APP_NAME}.app" "${DMG_SRC_FOLDER}/${DISPLAY_NAME}.app"
fi

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

# DMG 容器本身也签名（持有 Developer ID 时），让分发件整体可校验
if [ -n "${SIGN_ID}" ] && [ -f "${DMG_PATH}" ]; then
    echo "🔏 为 DMG 容器签名..."
    codesign --force --timestamp --sign "${SIGN_ID}" "${DMG_PATH}"
    codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi

# ============================================================================
# 公证 + 装订（可选）：检测到 notarytool 凭据 profile 时,提交 Apple 公证并把票据
# 装订进 DMG——之后 Gatekeeper 直接放行,无需右键/xattr。缺凭据则跳过(仍是已签名未公证包)。
# profile 名可用 MICTETHER_NOTARY_PROFILE 覆盖,默认 MicTether-notary。
# 一次性配置: xcrun notarytool store-credentials <profile> --apple-id .. --team-id .. --password ..
# ============================================================================
NOTARY_PROFILE="${MICTETHER_NOTARY_PROFILE:-MicTether-notary}"
if [ -n "${SIGN_ID}" ] && xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "📜 提交公证（profile: ${NOTARY_PROFILE}，可能需几分钟）..."
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    echo "📌 装订公证票据到 DMG..."
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
else
    echo "ℹ️  跳过公证（未检测到 notarytool 凭据 profile '${NOTARY_PROFILE}'）；分发件已签名但未公证。"
fi

# Cleanup temp
rm -rf "${TMP_WORKSPACE}"

echo "✅ DMG package successfully created at: ${DMG_PATH}"
