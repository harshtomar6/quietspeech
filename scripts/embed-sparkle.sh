#!/bin/zsh
# Embeds Sparkle.framework into an .app bundle and signs its nested helpers.
#
# Sparkle ships helpers that must be re-signed with the same identity as the
# app: XPC services, Updater.app, and the Autoupdate executable. They have to be
# signed deepest-first, before the framework itself, and before the app seal.
#
# Usage: source scripts/embed-sparkle.sh; embed_sparkle <bundle> <identity> <hardened>
#   identity  "-" for ad-hoc, otherwise a codesigning identity name
#   hardened  1 to add --options runtime --timestamp (distribution builds)

embed_sparkle() {
  local bundle="$1"
  local identity="$2"
  local hardened="${3:-0}"

  local bin_dir fw_src
  bin_dir="$(swift build -c release --show-bin-path)"
  fw_src="${bin_dir}/Sparkle.framework"
  if [[ ! -d "$fw_src" ]]; then
    print -r -- "error: Sparkle.framework not found at $fw_src" >&2
    return 1
  fi

  local frameworks="${bundle}/Contents/Frameworks"
  local dest="${frameworks}/Sparkle.framework"
  mkdir -p "$frameworks"
  rm -rf "$dest"
  # ditto preserves the framework's version symlinks and executable bits.
  ditto "$fw_src" "$dest"

  local -a opts
  if [[ "$identity" == "-" ]]; then
    opts=(--force --sign - --timestamp=none)
  elif [[ "$hardened" == "1" ]]; then
    opts=(--force --sign "$identity" --options runtime --timestamp)
  else
    opts=(--force --sign "$identity" --timestamp=none)
  fi

  local item
  for item in "$dest"/Versions/B/XPCServices/*.xpc; do
    [[ -d "$item" ]] || continue
    codesign "${opts[@]}" "$item"
  done
  codesign "${opts[@]}" "$dest/Versions/B/Updater.app"
  # Keep Sparkle's original identifier: the helper is launched by path, but the
  # identifier is what the framework's own checks expect to see.
  codesign "${opts[@]}" --identifier org.sparkle-project.Sparkle.Autoupdate \
    "$dest/Versions/B/Autoupdate"
  codesign "${opts[@]}" "$dest"

  codesign --verify --strict --verbose=1 "$dest" 2>&1 | sed 's/^/    /'
}
