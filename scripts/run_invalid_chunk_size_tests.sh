#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source_ref="${1:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-invalid-chunks.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if [[ -n "$source_ref" ]]; then
    git show "$source_ref:VibeScribe/Utils/TextChunker.swift" > "$work/TextChunker.swift"
else
    cp VibeScribe/Utils/TextChunker.swift "$work/TextChunker.swift"
fi
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos26.0" \
    "$work/TextChunker.swift" VibeScribeTests/InvalidChunkSizeProbe.swift \
    -o "$work/invalid-chunk-size-probe"
python3 - "$work/invalid-chunk-size-probe" "$source_ref" <<'PY'
import resource
import subprocess
import sys

binary, source_ref = sys.argv[1:]

def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

for size in (0, -1):
    process = subprocess.Popen([binary, str(size)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, preexec_fn=disable_core_dumps)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=1)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        stdout, stderr = process.communicate()
    if 'ENTER_CHUNKER' not in stdout:
        raise SystemExit(f'Probe did not reach TextChunker for size {size}: {stderr}')
    if source_ref:
        if size == 0:
            if not timed_out:
                raise SystemExit('Historical zero-size nontermination was not reproduced')
            print('REPRODUCED: size 0 does not return within the bounded probe')
        else:
            if timed_out or process.returncode >= 0 or 'String index is out of bounds' not in stderr:
                raise SystemExit(f'Historical negative-size index failure was not reproduced: {stderr}')
            print('REPRODUCED: size -1 triggers the Swift string index-bounds failure')
    else:
        if timed_out or process.returncode != 0 or 'PASS:' not in stdout:
            raise SystemExit(f'Invalid size {size} was not safely rejected: {stderr}')
        print(f'PASS: size {size} returns no chunks promptly')
PY
