#!/bin/zsh
# Builds a distributable, notarized QuietSpeech for another Mac.
#
#   ./package.sh                 build, sign, notarize, staple, make a DMG
#   SKIP_NOTARIZE=1 ./package.sh sign and package without notarizing
#   VERSION=0.2 BUILD_NUMBER=2 ./package.sh   build the next Sparkle update
#
# BUILD_NUMBER is Sparkle's comparison key: it must increase for every release,
# or existing installs will never see the new version.
#
# Signing needs a "Developer ID Application" certificate. Notarization needs a
# stored notarytool credential profile — see the error it prints if missing.
set -euo pipefail

cd "$(dirname "$0")"
source scripts/embed-sparkle.sh

APP_NAME="QuietSpeech"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-quietspeech-notary}"
DIST="dist"
BUNDLE="${DIST}/${APP_NAME}.app"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
ZIP="${DIST}/${APP_NAME}-${VERSION}.zip"

step() { print -r -- "\n==> $1" }

# MARK: - Signing identity

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  print -r -- "error: no 'Developer ID Application' certificate found." >&2
  print -r -- "       A distributable build must be signed with a Developer ID," >&2
  print -r -- "       not 'Apple Development' and not ad-hoc." >&2
  exit 1
fi

# MARK: - Build

step "Compiling (release, arm64)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
[[ -f "$BIN" ]] || { print -r -- "error: binary not found at $BIN" >&2; exit 1 }

step "Assembling ${APP_NAME}.app…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon*.png "$BUNDLE/Contents/Resources/"
cp Resources/THIRD_PARTY_NOTICES.txt "$BUNDLE/Contents/Resources/"
cp LICENSE "$BUNDLE/Contents/Resources/LICENSE"
cp NOTICE "$BUNDLE/Contents/Resources/NOTICE"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$BUNDLE/Contents/Info.plist"

# MARK: - Sign (hardened runtime, secure timestamp)

step "Embedding Sparkle…"
embed_sparkle "$BUNDLE" "$SIGN_IDENTITY" 1

step "Signing as: ${SIGN_IDENTITY}"
# --options runtime is the hardened runtime, a hard requirement for
# notarization. --timestamp embeds a secure timestamp from Apple; a signature
# without one is rejected by the notary service.
codesign --force \
  --sign "$SIGN_IDENTITY" \
  --options runtime \
  --timestamp \
  --entitlements Resources/QuietSpeech.entitlements \
  "$BUNDLE"

step "Verifying signature…"
codesign --verify --strict --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/    /'
print -r -- "    entitlements:"
codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null \
  | plutil -convert xml1 -o - - 2>/dev/null | sed 's/^/      /' || true
print -r -- "    designated requirement:"
codesign -d -r- "$BUNDLE" 2>&1 | rg 'designated' | sed 's/^/      /' || true

# MARK: - Notarize

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  step "Skipping notarization (SKIP_NOTARIZE=1)"
  print -r -- "    The other Mac will need: right-click the app > Open, once."
else
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    print -r -- "\nerror: no notarytool credential profile named '${NOTARY_PROFILE}'." >&2
    cat >&2 <<EOF

  Store one of the following first.

  App Store Connect API key (preferred — no password sharing, does not expire
  the way app-specific passwords can):

      xcrun notarytool store-credentials ${NOTARY_PROFILE} \\
        --key   ~/private_keys/AuthKey_XXXXXXXXXX.p8 \\
        --key-id XXXXXXXXXX \\
        --issuer 00000000-0000-0000-0000-000000000000

  Apple ID + app-specific password (create it at https://appleid.apple.com):

      xcrun notarytool store-credentials ${NOTARY_PROFILE} \\
        --apple-id you@example.com \\
        --team-id  48K4A3F8F7 \\
        --password abcd-efgh-ijkl-mnop

  Then re-run ./package.sh — or SKIP_NOTARIZE=1 ./package.sh to package anyway.
EOF
    exit 1
  fi

  notarize() {
    # Not "path" or "status": in zsh the first is tied to $PATH (a local one
    # empties it) and the second is read-only.
    local file="$1" label="$2" json result id
    json="$(mktemp)"
    step "Notarizing ${label} (uploads to Apple, usually 1-5 min)…"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
      --wait --output-format json > "$json"
    result="$(/usr/bin/python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status',''))" "$json")"
    id="$(/usr/bin/python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('id',''))" "$json")"
    if [[ "$result" != "Accepted" ]]; then
      print -r -- "error: notarization of ${label} was ${result:-unknown} (id ${id})" >&2
      xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
      exit 1
    fi
    print -r -- "    accepted (id ${id})"
  }

  # The app has to be zipped to submit it, and the ticket then stapled into the
  # bundle so it validates offline. Doing this before the DMG means the app
  # inside the disk image is already stapled.
  ditto -c -k --keepParent --sequesterRsrc "$BUNDLE" "$ZIP"
  notarize "$ZIP" "the app"
  step "Stapling the app…"
  xcrun stapler staple "$BUNDLE" | sed 's/^/    /'
  xcrun stapler validate "$BUNDLE" | sed 's/^/    /'
fi

step "Gatekeeper assessment…"
spctl --assess --type execute --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/    /' || \
  print -r -- "    (expected to fail only when notarization was skipped)"

# MARK: - Package

step "Building ${DMG}…"
rm -f "$DMG"
STAGE="$(mktemp -d)"
mkdir -p "${STAGE}/${APP_NAME}"
cp -R "$BUNDLE" "${STAGE}/${APP_NAME}/"
ln -s /Applications "${STAGE}/${APP_NAME}/Applications"
hdiutil create -quiet -volname "QuietSpeech" -srcfolder "${STAGE}/${APP_NAME}" \
  -ov -format UDZO "$DMG"
rm -rf "$STAGE"

codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  notarize "$DMG" "the disk image"
  step "Stapling the disk image…"
  xcrun stapler staple "$DMG" | sed 's/^/    /'
  xcrun stapler validate "$DMG" | sed 's/^/    /'
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | sed 's/^/    /'
fi

# Refresh the zip so it holds the stapled app rather than the pre-staple copy.
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc "$BUNDLE" "$ZIP"

# MARK: - Appcast

# Installed copies read https://quietspeech.app/appcast.xml (SUFeedURL), so
# the feed can move hosts without breaking them. Every DMG ever released stays
# in APPCAST_DIR so generate_appcast keeps the older entries.
APPCAST_DIR="${APPCAST_DIR:-${DIST}/appcast}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://quietspeech.app/downloads/}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
if [[ -x "${SPARKLE_BIN}/generate_appcast" ]]; then
  step "Updating appcast in ${APPCAST_DIR}…"
  mkdir -p "$APPCAST_DIR"
  cp "$DMG" "${APPCAST_DIR}/"
  "${SPARKLE_BIN}/generate_appcast" "$APPCAST_DIR" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  print -r -- "    Publish ${APPCAST_DIR}/appcast.xml at https://quietspeech.app/appcast.xml"
  print -r -- "    and $(basename "$DMG") at ${DOWNLOAD_URL_PREFIX}$(basename "$DMG")."
else
  step "Skipping appcast (no generate_appcast at ${SPARKLE_BIN})"
fi

# MARK: - Done

step "Done"
print -r -- "    $(shasum -a 256 "$DMG" | awk '{print $1}')  ${DMG}"
print -r -- "    $(shasum -a 256 "$ZIP" | awk '{print $1}')  ${ZIP}"
cat <<EOF

  On the other Mac, check it can run the build at all first:

      sw_vers -productVersion   # must be 26.0 or newer
      uname -m                  # must be arm64

  Then open the DMG, drag QuietSpeech to Applications, and launch it. On first
  run it will ask for Microphone and Accessibility, and download the on-device
  speech model for your language.
EOF
