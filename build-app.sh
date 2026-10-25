#!/bin/zsh
# Builds QuietSpeech and assembles a signed .app bundle around the SPM binary.
set -euo pipefail

cd "$(dirname "$0")"
source scripts/embed-sparkle.sh

APP_NAME="QuietSpeech"
BUNDLE="${APP_NAME}.app"

echo "==> Compiling (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN" ]]; then
  echo "error: binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon*.png "${BUNDLE}/Contents/Resources/"
cp Resources/THIRD_PARTY_NOTICES.txt "${BUNDLE}/Contents/Resources/"
cp LICENSE "${BUNDLE}/Contents/Resources/LICENSE"
cp NOTICE "${BUNDLE}/Contents/Resources/NOTICE"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Sign with a stable identity if one is available.
#
# This matters more than it looks: an ad-hoc signature has a designated
# requirement of `cdhash H"…"`, so every rebuild produces what macOS considers a
# *different* app and all TCC grants (Microphone, Accessibility, Input
# Monitoring) are silently dropped — while System Settings still shows the
# toggles as ON. A certificate-based signature makes the requirement
# identity-based, so grants survive rebuilds.
#
# Override with: SIGN_IDENTITY="Apple Development: …" ./build-app.sh
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "==> Embedding Sparkle (ad-hoc)…"
  embed_sparkle "$BUNDLE" "-" 0
  echo "==> Ad-hoc signing…"
  echo "    WARNING: no code-signing identity found, falling back to ad-hoc."
  echo "    TCC permissions will be revoked on every rebuild."
  codesign --force --sign - --timestamp=none "$BUNDLE"
else
  echo "==> Embedding Sparkle…"
  embed_sparkle "$BUNDLE" "$SIGN_IDENTITY" 0
  echo "==> Signing as: ${SIGN_IDENTITY}"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$BUNDLE"
fi
codesign --verify --verbose=1 "$BUNDLE" 2>&1 | sed 's/^/    /'

echo "    designated requirement:"
codesign -d -r- "$BUNDLE" 2>&1 | rg 'designated' | sed 's/^/      /'

echo ""
echo "Done. Run it with:"
echo "    open $(pwd)/${BUNDLE}"
