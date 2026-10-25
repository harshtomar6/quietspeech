#!/bin/zsh
# Scores AI polish on your captured dictations with Apple Intelligence.
#
#   scripts/polish-bench/run.sh [shipped|candidate] [limit]
#
# Reads ~/Library/Application Support/QuietSpeech/dictation-capture.jsonl
# (set CAPTURE to use another file) and writes one result per line to
# polish-<variant>.jsonl (or OUT). The capture holds your own dictations, so
# keep the results out of the repo.
set -euo pipefail
here=${0:A:h}
root=${here:h:h}
build=$(mktemp -d)
swiftc -O -parse-as-library -o "$build/polish-bench" \
    "$root/Sources/QuietSpeech/Cleanup.swift" \
    "$root/Sources/QuietSpeech/ContextProfile.swift" \
    "$root/Sources/QuietSpeech/Personalization.swift" \
    "$root/Sources/QuietSpeech/PolishGuard.swift" \
    "$root/Sources/QuietSpeech/PolishPrompt.swift" \
    "$here/CandidatePrompt.swift" \
    "$here/main.swift"
"$build/polish-bench" "$@"
