#!/bin/zsh
# Build, sign with Developer ID, notarize and publish a release on GitHub: Glyph-Record-<version>.dmg,
# plus Glyph-Record.dmg for the stable link (releases/latest/download/Glyph-Record.dmg).
# Hardened runtime, no sandbox; the entitlements file asks for the microphone only (the Mac's
# own sound is asked for at first use, no entitlement needed).
# Needs a "Developer ID Application" certificate in the keychain, an App Store Connect API key
# for notarization (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH), and the GitHub CLI signed in.
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} # xcodebuild needs Xcode, not the command line tools
: ${ASC_KEY_ID:?set ASC_KEY_ID} ${ASC_ISSUER_ID:?set ASC_ISSUER_ID} ${ASC_KEY_PATH:?set ASC_KEY_PATH}
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
[[ -n $identity ]] || { echo "no Developer ID Application certificate in the keychain"; exit 1; }
team=${identity##*\(}; team=${team%\)}
version=$(awk '/MARKETING_VERSION/{gsub(/"/,"",$2); print $2; exit}' project.yml)

echo "building Glyph Record $version"
xcodegen generate --quiet
xcodebuild -project GlyphRecord.xcodeproj -scheme GlyphRecord -configuration Release -derivedDataPath build -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" OTHER_CODE_SIGN_FLAGS=--timestamp \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build # no get-task-allow: notarization refuses it
app="build/Build/Products/Release/Glyph Record.app"
codesign --verify --strict --deep "$app"

echo "making the disk image"
rm -rf dist && mkdir -p dist/stage
cp -R "$app" dist/stage/ && ln -s /Applications dist/stage/Applications
dmg=dist/Glyph-Record-$version.dmg
hdiutil create -volname "Glyph Record $version" -srcfolder dist/stage -fs HFS+ -format UDZO -ov "$dmg" -quiet
codesign --sign "$identity" --timestamp "$dmg"

echo "notarizing (a few minutes)"
result=$(xcrun notarytool submit "$dmg" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --timeout 20m)
echo "$result"
if ! grep -q "status: Accepted" <<<"$result"; then
  id=$(awk '/^ *id:/{print $2; exit}' <<<"$result")
  xcrun notarytool log "$id" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
  echo "notarization was not accepted (log above)"; exit 1
fi
xcrun stapler staple "$dmg"

echo "checking a downloaded copy passes Gatekeeper"
cp "$dmg" dist/check.dmg
xattr -w com.apple.quarantine "0081;00000000;Safari;" dist/check.dmg
spctl --assess --type open --context context:primary-signature -v dist/check.dmg
rm dist/check.dmg
cp "$dmg" dist/Glyph-Record.dmg

notes=$(awk -v v="**$version**" 'index($0, "- " v) == 1 {sub(/^- /, ""); print; exit}' README.md)
if gh release view "v$version" >/dev/null 2>&1; then
  gh release upload "v$version" "$dmg" dist/Glyph-Record.dmg --clobber
else
  gh release create "v$version" "$dmg" dist/Glyph-Record.dmg --title "Glyph Record $version" --notes "${notes:-Glyph Record $version}"
fi
echo "released: https://github.com/fru-dev3/glyph-record/releases/tag/v$version"
