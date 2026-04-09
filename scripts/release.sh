#!/bin/bash
set -e

# VibeWars Release Script
# Usage: ./scripts/release.sh 1.2.0
#
# This script:
# 1. Bumps the version in Xcode project
# 2. Builds and archives the app
# 3. Creates a DMG
# 4. Creates a GitHub release with the DMG
# 5. Updates the Homebrew tap with new version + SHA

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.2.0"
    exit 1
fi

echo "🔥 Releasing VibeWars v$VERSION"

PROJECT_DIR="/Users/michaelperry/Desktop/VibeisCheck"
REPO_DIR="/Users/michaelperry/vibecheck"
TAP_DIR="/tmp/homebrew-tap"
ARCHIVE="/tmp/VibeWars-release.xcarchive"
EXPORT_DIR="/tmp/VibeWars-release-export"
DMG_DIR="/tmp/dmg_release"
DMG_PATH="/tmp/VibeWars-v${VERSION}.dmg"
EXPORT_PLIST="/tmp/export-options.plist"

# Step 1: Bump version in Xcode project
echo "📦 Bumping version to $VERSION..."
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${VERSION};/g" \
    "$PROJECT_DIR/VibeCheck.xcodeproj/project.pbxproj"

# Step 2: Build and archive
echo "🔨 Building..."
cd "$PROJECT_DIR"
xcodebuild -project VibeCheck.xcodeproj -scheme VibeCheck \
    -configuration Release archive -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates -quiet

# Step 3: Export
echo "📤 Exporting..."
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates -quiet

# Step 4: Create DMG
echo "💿 Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$EXPORT_DIR/VibeCheck.app" "$DMG_DIR/VibeWars.app"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "VibeWars" -srcfolder "$DMG_DIR" \
    -ov -format UDZO "$DMG_PATH" -quiet

# Step 5: Get SHA256
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "🔐 SHA256: $SHA"

# Step 6: Sync source files to repo
echo "📁 Syncing to repo..."
cd "$REPO_DIR"
for f in "$PROJECT_DIR"/VibeCheck/*.swift "$PROJECT_DIR"/VibeCheck/*.plist \
         "$PROJECT_DIR"/VibeCheck/*.entitlements "$PROJECT_DIR"/VibeCheck/*.h; do
    [ -f "$f" ] && cp "$f" VibeCheck/
done
cp -R "$PROJECT_DIR/VibeCheck/Assets.xcassets" VibeCheck/ 2>/dev/null
cp "$PROJECT_DIR/VibeCheck.xcodeproj/project.pbxproj" VibeCheck.xcodeproj/
git add -A
git commit -m "Release v${VERSION}

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>" || true
git push

# Step 7: Create GitHub release
echo "🚀 Creating GitHub release v$VERSION..."
gh release create "v${VERSION}" "$DMG_PATH" \
    --title "VibeWars v${VERSION}" \
    --generate-notes

# Step 8: Update Homebrew tap
echo "🍺 Updating Homebrew tap..."
rm -rf "$TAP_DIR"
git clone https://github.com/michaelperry/homebrew-tap.git "$TAP_DIR"
cat > "$TAP_DIR/Casks/vibewars.rb" << CASK
cask "vibewars" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/michaelperry/vibewars/releases/download/v#{version}/VibeWars-v#{version}.dmg"
  name "VibeWars"
  desc "The developer leaderboard for vibe coders"
  homepage "https://vibewars.dev"

  app "VibeWars.app"

  zap trash: [
    "~/Library/Preferences/com.michaelperry.VibeWars.plist",
  ]
end
CASK

cd "$TAP_DIR"
git add -A
git commit -m "Update VibeWars to v${VERSION}

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git push

echo ""
echo "✅ VibeWars v$VERSION released!"
echo "   DMG: $DMG_PATH"
echo "   SHA: $SHA"
echo "   Release: https://github.com/michaelperry/vibewars/releases/tag/v${VERSION}"
echo "   Homebrew: brew upgrade --cask vibewars"
