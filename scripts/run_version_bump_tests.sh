#!/usr/bin/env bash
set -euo pipefail
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [historical-ref]" >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin || ! -x /usr/libexec/PlistBuddy ]]; then
    echo "Version-bump regressions require macOS PlistBuddy and BSD sed." >&2
    exit 1
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_ref="${1:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/vibescribe-version-bump.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Only the helper source varies between baseline and candidate. Both run against
# the same isolated fixtures, using the real platform tools without substitution.
if [[ -n "$source_ref" ]]; then
    git -C "$ROOT_DIR" show "$source_ref:scripts/bump_version.sh" > "$work/bump_version.sh"
else
    cp "$ROOT_DIR/scripts/bump_version.sh" "$work/bump_version.sh"
fi
cp "$ROOT_DIR/VibeScribe/Info.plist" "$work/Info.plist"
cp "$ROOT_DIR/VibeScribe.xcodeproj/project.pbxproj" "$work/project.pbxproj"

python3 - "$work" "$source_ref" <<'PY'
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

work, source_ref = Path(sys.argv[1]), sys.argv[2]
plist_relative = Path("VibeScribe/Info.plist")
project_relative = Path("VibeScribe.xcodeproj/project.pbxproj")
script_relative = Path("scripts/bump_version.sh")
token = "$(CURRENT_PROJECT_VERSION)"
environment = os.environ.copy()
# No inherited Git directory/index overrides or global hooks/filters can redirect
# the helper's `git add` outside these new, remote-free repositories.
for key in list(environment):
    if key.startswith("GIT_"):
        environment.pop(key)
environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")

def run(arguments, *, cwd=None, check=True):
    return subprocess.run(arguments, cwd=cwd, env=environment, check=check,
                          capture_output=True, text=True, timeout=10)

def plist(fixture, command):
    return run(["/usr/libexec/PlistBuddy", "-c", command, str(fixture / plist_relative)]).stdout.strip()

def fixture(name, *, legacy=False, numeric_project=True):
    destination = work / name
    for source, relative in (("Info.plist", plist_relative),
                             ("project.pbxproj", project_relative),
                             ("bump_version.sh", script_relative)):
        (destination / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / source, destination / relative)
    project = destination / project_relative
    text, marketing_count = re.subn(r"(MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;",
                                   r"\g<1>1.4.1;", project.read_text())
    text, build_count = re.subn(r"(CURRENT_PROJECT_VERSION = )[0-9]+;", r"\g<1>4;", text)
    if marketing_count < 1 or build_count < 2:
        raise AssertionError("Fixture source lacks expected version/build settings")
    # The first setting is deliberately smaller: token resolution must use the
    # maximum numeric build, not simply the first configuration in the project.
    text = text.replace("CURRENT_PROJECT_VERSION = 4;", "CURRENT_PROJECT_VERSION = 2;", 1)
    if not numeric_project:
        text = re.sub(r"(CURRENT_PROJECT_VERSION = )[0-9]+;", r"\g<1>not_a_number;", text)
    project.write_text(text)
    plist(destination, "Set :CFBundleShortVersionString " + ("1.4.1" if legacy else "$(MARKETING_VERSION)"))
    plist(destination, f"Set :CFBundleVersion {'3' if legacy else token}")
    run(["git", "init", "--quiet", "--template=", str(destination)])
    assert not run(["git", "-C", str(destination), "remote"]).stdout
    return destination

def invoke(destination, *arguments, success=True):
    # No caller passes --tag or --push; there are no remotes or commits.
    assert "--tag" not in arguments and "--push" not in arguments
    result = run(["/bin/bash", str(destination / script_relative), *arguments],
                 cwd=destination, check=False)
    assert "command not found" not in result.stderr, result.stderr
    if (result.returncode == 0) != success:
        raise AssertionError(f"Unexpected helper result ({result.returncode}): {result.stdout}\n{result.stderr}")

def builds(destination):
    return re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);",
                      (destination / project_relative).read_text())

def verify_success(destination, expected_build, expected_version="1.4.2"):
    assert plist(destination, "Print :CFBundleVersion") == token
    assert plist(destination, "Print :CFBundleShortVersionString") == "$(MARKETING_VERSION)"
    actual_builds = builds(destination)
    assert actual_builds and set(actual_builds) == {expected_build}, actual_builds
    versions = re.findall(r"MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+);",
                          (destination / project_relative).read_text())
    assert versions and set(versions) == {expected_version}, versions
    staged = run(["git", "-C", str(destination), "diff", "--cached", "--name-only"]).stdout.splitlines()
    assert set(staged) == {str(plist_relative), str(project_relative)}, staged

if source_ref:
    automatic = fixture("historical-auto")
    before_builds = builds(automatic)
    invoke(automatic, "patch")
    assert plist(automatic, "Print :CFBundleVersion") == "1"
    assert builds(automatic) == before_builds
    print("REPRODUCED: tokenized build 4 resets to literal 1 while project builds remain stale")

    explicit = fixture("historical-explicit")
    before_builds = builds(explicit)
    invoke(explicit, "patch", "--build", "10")
    assert plist(explicit, "Print :CFBundleVersion") == "10"
    assert builds(explicit) == before_builds
    print("REPRODUCED: explicit build 10 replaces the plist token while project builds remain stale")
else:
    automatic = fixture("candidate-auto")
    invoke(automatic, "patch")
    verify_success(automatic, "5")
    print("PASS: token uses maximum project build 4, increments to 5, and stays tokenized")
    invoke(automatic, "patch")
    verify_success(automatic, "6", "1.4.3")
    print("PASS: a repeated automatic bump increments build 5 to 6 and stages both version sources")

    explicit = fixture("candidate-explicit")
    invoke(explicit, "patch", "--build", "10")
    verify_success(explicit, "10")
    print("PASS: explicit build 10 updates project settings and retains the plist token")

    legacy = fixture("candidate-legacy", legacy=True)
    invoke(legacy, "patch")
    verify_success(legacy, "4")
    print("PASS: legacy numeric plist build 3 increments to 4 and migrates to the token")

    invalid_cases = (
        ("invalid-text", ("patch", "--build", "not-a-number"), True),
        ("invalid-negative", ("patch", "--build", "-1"), True),
        ("invalid-empty", ("patch", "--build", ""), True),
        ("missing-build-argument", ("patch", "--build"), True),
        ("token-without-numeric-project", ("patch",), False),
    )
    for name, arguments, numeric_project in invalid_cases:
        destination = fixture(name, numeric_project=numeric_project)
        before = {relative: (destination / relative).read_bytes()
                  for relative in (plist_relative, project_relative, script_relative)}
        before_index = run(["git", "-C", str(destination), "ls-files", "--stage"]).stdout
        invoke(destination, *arguments, success=False)
        assert all((destination / relative).read_bytes() == contents
                   for relative, contents in before.items()), f"{name} changed files before failing"
        assert run(["git", "-C", str(destination), "ls-files", "--stage"]).stdout == before_index
        print(f"PASS: {name} fails before modifying files or staging changes")
PY
