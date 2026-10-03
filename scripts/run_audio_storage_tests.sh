#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Optional baseline commit: the same narrowly instrumented harness must reproduce
# both historical overwrites, rather than merely treating any failure as evidence.
source_ref="${1:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-audio-storage.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/recordings"
if [[ -n "$source_ref" ]]; then
    git show "$source_ref:VibeScribe/Utils/AudioUtils.swift" > "$work/AudioUtils.swift"
else
    cp VibeScribe/Utils/AudioUtils.swift "$work/AudioUtils.swift"
fi

python3 - "$work/AudioUtils.swift" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
substitutions = {
    'Date()': 'Date(timeIntervalSince1970: 1700000000)',
    'let recordingsDir = try AudioUtils.getRecordingsDirectory()':
        'let recordingsDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)',
}
for original, replacement in substitutions.items():
    count = source.count(original)
    if count != 2:
        raise SystemExit(f"Refusing test instrumentation: expected 2 occurrences of {original!r}, found {count}")
    source = source.replace(original, replacement)
path.write_text(source)
PY

xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos26.0" \
    "$work/AudioUtils.swift" \
    VibeScribe/Utils/Logger.swift \
    VibeScribe/Utils/AppLanguage.swift \
    VibeScribeTests/AudioStorageRegression.swift \
    -o "$work/audio-storage-tests"
if [[ -n "$source_ref" ]]; then
    "$work/audio-storage-tests" "$work/recordings" --expect-collision
else
    "$work/audio-storage-tests" "$work/recordings"
fi
