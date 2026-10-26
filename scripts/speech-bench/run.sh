#!/bin/zsh
# Compares speech recognizers (Apple's, Desert Ant's Voz) on your own
# dictations.
#
#   1. Turn on Settings › Privacy › Save audio clips (needs developer tools:
#      defaults write dev.harsh.quietspeech developerTools -bool YES)
#      and dictate as usual.
#   2. scripts/speech-bench/run.sh label    type what you actually said
#   3. scripts/speech-bench/run.sh score    compare the recognizers
#
# Clips, labels and results stay in
# ~/Library/Application Support/QuietSpeech/speech-clips (or CLIPS).
# The first Voz run downloads its model (about 470 MB) from Hugging Face.
set -euo pipefail
here=${0:A:h}
swift build -c release --package-path "$here" 2>&1 | grep -E "error|warning: unable" >&2 || true
exec "$here/.build/release/SpeechBench" "$@"
