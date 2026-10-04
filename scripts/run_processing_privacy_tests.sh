#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# An optional historical ref reproduces old dispatches and output logs.
# For a ref with fixed dispatch guards but old logs, add --expect-legacy-output-logs.
# No service, model download, microphone, or macOS permission prompt is used.
source_ref="${1:-}"
historical_mode="${2:-}"
if [[ "$#" -gt 2 || "$source_ref" == --* || ( -n "$historical_mode" && "$historical_mode" != "--expect-legacy-output-logs" ) || ( -n "$historical_mode" && -z "$source_ref" ) ]]; then
    echo "Usage: $0 [historical-ref [--expect-legacy-output-logs]]" >&2
    exit 2
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-processing-privacy.XXXXXX")"
trap 'rm -rf "$work"' EXIT
python3 scripts/prepare_processing_privacy_tests.py "$work" "$source_ref"

compiler=()
platform_flags=()
if [[ -n "${SWIFTC:-}" ]]; then
    compiler=("$SWIFTC")
elif [[ "$(uname -s)" == "Darwin" ]]; then
    compiler=(xcrun swiftc)
else
    compiler=(swiftc)
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
    platform_flags=(-target "$(uname -m)-apple-macos26.0")
fi
"${compiler[@]}" -swift-version 5 -parse-as-library -module-cache-path "$work/module-cache" "${platform_flags[@]}" \
    "$work/SourceParts.swift" "$work/PipelineParts.swift" "$work/DefaultTranscriptionManager.swift" \
    VibeScribeTests/ProcessingPrivacyProbe.swift -o "$work/processing-privacy-tests"
args=("$work/synthetic-audio-marker.m4a")
if [[ -n "$source_ref" ]]; then
    args+=(--expect-legacy-output-logs)
    if [[ "$historical_mode" != "--expect-legacy-output-logs" ]]; then
        args+=(--expect-legacy-dispatch)
    fi
fi
python3 - "$work/processing-privacy-tests" "${args[@]}" <<'PY'
import subprocess
import sys

subprocess.run(sys.argv[1:], check=True, timeout=30)
PY
