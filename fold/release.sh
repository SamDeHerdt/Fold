#!/bin/bash
# Publishes a Fold release that installed copies pick up through Sparkle.
#   fold/release.sh 1.1.0 "What changed"
# Needs: a clean tree, `gh` signed in, and Fold's EdDSA key in the login
# keychain (account "fold", made once with Sparkle's generate_keys).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: fold/release.sh <version> [notes]}"
NOTES="${2:-Fold $VERSION}"
BUILD="${FOLD_BUILD_DIR:-$REPO/.build-fold}"
OUT="${FOLD_OUT:-$REPO/dist}"
GH_REPO="SamDeHerdt/Fold"
cd "$REPO"

[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "v$VERSION already exists." >&2; exit 1; }

echo "$VERSION" > VERSION
git diff --quiet VERSION || git commit -q -m "Release $VERSION" VERSION
BUILD_NUMBER="$(git rev-list --count HEAD)"

FOLD_BUILD_DIR="$BUILD" FOLD_OUT="$OUT" "$REPO/fold/build.sh"

ZIP="$OUT/Fold-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$OUT/Fold.app" "$ZIP"
SIGNATURE="$("$BUILD/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" --account fold "$ZIP")"

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fold</title>
    <item>
      <title>Fold $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$GH_REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$GH_REPO/releases/download/v$VERSION/Fold-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

git tag "v$VERSION"
git push origin HEAD:main "v$VERSION"
gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$GH_REPO" --title "Fold $VERSION" --notes "$NOTES"
echo "Released Fold $VERSION (build $BUILD_NUMBER)."
