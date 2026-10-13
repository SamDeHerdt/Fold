#!/bin/bash
# Builds Fold.app into $FOLD_OUT (default <repo>/dist).
#   FOLD_BUILD_DIR  Xcode derived data (default <repo>/.build-fold)
#   FOLD_OUT        where Fold.app lands  (default <repo>/dist)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${FOLD_BUILD_DIR:-$REPO/.build-fold}"
OUT="${FOLD_OUT:-$REPO/dist}"
VERSION="$(tr -d '[:space:]' < "$REPO/VERSION")"
BUILD_NUMBER="$(git -C "$REPO" rev-list --count HEAD)"

xcodebuild -project "$REPO/Thaw.xcodeproj" -scheme Thaw \
  -configuration Release -derivedDataPath "$BUILD" \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

mkdir -p "$OUT"
APP="$OUT/Fold.app"
rm -rf "$APP"
ditto "$BUILD/Build/Products/Release/Thaw.app" "$APP"

# Xcode stamps CFBundleName/the executable with the Thaw product name, which is
# what permission prompts and Privacy & Security show. Name both Fold, and
# stamp Fold's own version (Sparkle compares CFBundleVersion).
PLIST="$APP/Contents/Info.plist"
mv "$APP/Contents/MacOS/Thaw" "$APP/Contents/MacOS/Fold"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleExecutable Fold" \
  -c "Set :CFBundleName Fold" \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$PLIST"

# Fold's own icon (drawn by fold/icon/make-icon.swift). Dropping
# CFBundleIconName makes macOS use this .icns instead of Thaw's asset-catalog icon.
cp "$REPO/fold/icon/Fold.icns" "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true

# Ad-hoc signature with a stable designated requirement, so Accessibility and
# Screen Recording grants survive rebuilds and updates.
codesign --force --deep --sign - "$APP"
codesign --force --sign - --requirements '=designated => identifier "com.samdeherdt.fold"' "$APP"
codesign --verify --deep --strict "$APP"

# Keep fold:// and the Privacy & Security name pointed at the installed copy:
# Xcode's product is still called Thaw.app and shares Fold's bundle ID.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -u "$BUILD/Build/Products/Release/Thaw.app" 2>/dev/null || true

printf '%s\n' "$APP"
