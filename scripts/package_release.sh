#!/usr/bin/env bash
set -euo pipefail

# Build and validate a candidate ZIP. This does not sign again, notarize, upload,
# alter quarantine, or change system security settings.
if [[ $# -ne 3 || -z "$1" || ! "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$3" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 <output-directory> <version> <build>" >&2
    exit 2
fi
expected_version="$2"
expected_build="$3"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "Release packaging requires macOS and Xcode 26.3." >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode_26.3.app/Contents/Developer}"
xcode_version="$(xcodebuild -version)"
if [[ "${xcode_version%%$'\n'*}" != "Xcode 26.3" ]]; then
    echo "Expected Xcode 26.3; found: $xcode_version" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Package a clean checkout so the manifest source SHA identifies the built source." >&2
    exit 1
fi
source_sha="$(git rev-parse HEAD)"
mkdir -p "$1"
output_dir="$(cd "$1" && pwd)"
for name in VibeScribe.zip SHA256SUMS validation.json; do
    if [[ -e "$output_dir/$name" || -L "$output_dir/$name" ]]; then
        echo "Refusing to replace existing output: $output_dir/$name" >&2
        exit 1
    fi
done

work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
printf '%s\n' "$xcode_version" > "$work/xcode-version.txt"
xcrun swift --version > "$work/swift-version.txt"
xcrun --sdk macosx --show-sdk-version > "$work/sdk-version.txt"
sw_vers > "$work/host-version.txt"

# Let Xcode combine the project's build-setting entitlements with its plist.
# In particular, do not re-sign using VibeScribe.entitlements alone: that plist
# does not contain the full sandbox/audio/file/network entitlements.
xcodebuild -project VibeScribe.xcodeproj -scheme VibeScribe \
    -configuration Release -destination 'generic/platform=macOS' \
    -disableAutomaticPackageResolution \
    -archivePath "$work/VibeScribe.xcarchive" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive

verify_bundle() {
    local app="$1"
    local result="$2"
    /usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$app"
    python3 - "$app" "$result" "$expected_version" "$expected_build" <<'PY'
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

app, destination = map(Path, sys.argv[1:3])
expected_version, expected_build = sys.argv[3:5]
with (app / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
expected_metadata = {
    "CFBundleIdentifier": "pfrankov.VibeScribe",
    "CFBundleShortVersionString": expected_version,
    "CFBundleVersion": expected_build,
    "LSMinimumSystemVersion": "26.0",
    "CFBundleExecutable": "VibeScribe",
    "CFBundlePackageType": "APPL",
}
for key, expected in expected_metadata.items():
    if info.get(key) != expected:
        raise SystemExit(f"Unexpected {key}: {info.get(key)!r}; expected {expected!r}")

def command(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True)

executable = app / "Contents/MacOS/VibeScribe"
architectures = command("xcrun", "lipo", "-archs", str(executable)).stdout.decode().split()
if sorted(architectures) != ["arm64", "x86_64"]:
    raise SystemExit(f"Expected exactly arm64 and x86_64, found {architectures!r}")

expected_entitlements = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.cs.disable-library-validation": True,
    "com.apple.security.device.audio-input": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.network.client": True,
}
signatures = {}
for architecture in sorted(architectures):
    details = command(
        "/usr/bin/codesign", "--display", "--verbose=4",
        "--architecture", architecture, str(app),
    ).stderr.decode()
    flags = re.search(r"\bflags=0x[0-9a-fA-F]+\(([^)]*)\)", details)
    if "Signature=adhoc" not in details.splitlines() or flags is None:
        raise SystemExit(f"Missing ad-hoc signature or flags for {architecture}")
    flag_names = set(flags.group(1).split(","))
    if not {"adhoc", "runtime"}.issubset(flag_names):
        raise SystemExit(f"Missing ad-hoc/hardened-runtime flags for {architecture}: {flag_names}")
    entitlement_data = command(
        "/usr/bin/codesign", "--display", "--architecture", architecture,
        "--entitlements", ":-", str(app),
    ).stdout
    entitlements = plistlib.loads(entitlement_data)
    if (entitlements != expected_entitlements
            or any(type(value) is not bool for value in entitlements.values())):
        raise SystemExit(f"Unexpected embedded entitlements for {architecture}: {entitlements!r}")
    signatures[architecture] = {
        "identity": "adhoc",
        "flags": sorted(flag_names),
        "entitlements": entitlements,
    }

destination.write_text(json.dumps({
    "metadata": expected_metadata,
    "architectures": sorted(architectures),
    "deep_strict_signature_verification": "passed",
    "signatures": signatures,
}, indent=2, sort_keys=True) + "\n")
PY
}

app="$work/VibeScribe.xcarchive/Products/Applications/VibeScribe.app"
verify_bundle "$app" "$work/archive-validation.json"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$work/VibeScribe.zip"
mkdir "$work/extracted"
/usr/bin/ditto -x -k "$work/VibeScribe.zip" "$work/extracted"
verify_bundle "$work/extracted/VibeScribe.app" "$work/extracted-validation.json"
cmp "$work/archive-validation.json" "$work/extracted-validation.json"

mkdir "$work/smoke-runtime"
python3 scripts/smoke_release.py "$work/extracted/VibeScribe.app" \
    "$work/smoke-runtime" "$work/smoke-validation.json"

python3 - "$work" "$source_sha" "$expected_version" "$expected_build" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

work, source_sha = Path(sys.argv[1]), sys.argv[2]
expected_version, expected_build = sys.argv[3:5]
hasher = hashlib.sha256()
with (work / "VibeScribe.zip").open("rb") as archive:
    for block in iter(lambda: archive.read(1024 * 1024), b""):
        hasher.update(block)
digest = hasher.hexdigest()
(work / "SHA256SUMS").write_text(f"{digest}  VibeScribe.zip\n")
manifest = {
    "source_sha": source_sha,
    "version": expected_version,
    "build": expected_build,
    "zip": {"name": "VibeScribe.zip", "sha256": digest},
    "toolchain": {
        name: (work / filename).read_text().strip()
        for name, filename in {
            "xcode": "xcode-version.txt", "swift": "swift-version.txt",
            "macos_sdk": "sdk-version.txt", "host": "host-version.txt",
        }.items()
    },
    "bundle_checks": json.loads((work / "extracted-validation.json").read_text()),
    "archive_and_extracted_checks_match": True,
    "smoke": json.loads((work / "smoke-validation.json").read_text()),
    "limits": [
        "Ad-hoc signature; no Developer ID signing or notarization.",
        "No Gatekeeper/quarantine assessment or security-setting changes.",
        "Synthetic process-liveness smoke on the runner architecture only; no UI interaction assertions.",
        "UI-testing uses in-memory records and mock services; no real recording, speech models, or AI calls exercised.",
        "No release publication or external upload performed by this script.",
    ],
}
(work / "validation.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

if [[ "$(git rev-parse HEAD)" != "$source_sha" || -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Source changed during packaging; refusing to publish artifacts with stale provenance." >&2
    exit 1
fi

# Publish local outputs only after every validation stage succeeds. The manifest
# is written last; never replace another run's artifacts.
python3 - "$work" "$output_dir" <<'PY'
import shutil
import sys
from pathlib import Path

work, output = map(Path, sys.argv[1:])
for name in ("VibeScribe.zip", "SHA256SUMS", "validation.json"):
    with (work / name).open("rb") as source, (output / name).open("xb") as destination:
        shutil.copyfileobj(source, destination)
PY
echo "PASS: universal Release ZIP, signature/entitlements, extracted bundle, and synthetic launch verified"
echo "Outputs: $output_dir"
