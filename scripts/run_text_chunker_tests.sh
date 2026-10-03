#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source_ref="${1:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-text-chunker.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if [[ -n "$source_ref" ]]; then
    git show "$source_ref:VibeScribe/Utils/TextChunker.swift" > "$work/TextChunker.swift"
else
    cp VibeScribe/Utils/TextChunker.swift "$work/TextChunker.swift"
fi
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos26.0" \
    "$work/TextChunker.swift" VibeScribeTests/TextChunkerRegression.swift \
    -o "$work/text-chunker-tests"
if [[ -n "$source_ref" ]]; then
    "$work/text-chunker-tests" --expect-truncation
else
    "$work/text-chunker-tests"
fi
