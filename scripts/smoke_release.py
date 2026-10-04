#!/usr/bin/env python3
"""Bounded liveness smoke of the extracted executable, using only mock services."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

RUNNING_SECONDS = 10
TERM_GRACE_SECONDS = 5
KILL_GRACE_SECONDS = 2


def stop_fixture(process):
    # Popen created a private session/group for this exact executable. Group
    # cleanup covers its descendants too, without a name or bundle-ID search.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=TERM_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    # Also clean up any group members that outlived the root fixture process.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=KILL_GRACE_SECONDS)


def smoke(app, fixture, result):
    executable = app / "Contents/MacOS/VibeScribe"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError("Extracted VibeScribe executable is missing or not executable")

    # Do not forward credentials or unrelated UI-test overrides from CI. Keep
    # HOME/TMPDIR unchanged; the app sandbox controls its own storage locations.
    environment = {
        key: os.environ[key]
        for key in (
            "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE",
        )
        if key in os.environ
    }
    environment.update({
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "VIBESCRIBE_UI_TESTING": "1",
        "VIBESCRIBE_UI_EMPTY_STATE": "1",
        "VIBESCRIBE_UI_USE_MOCK_PIPELINE": "1",
        "VIBESCRIBE_UI_OPEN_MAIN_WINDOW": "1",
    })
    arguments = ["--uitesting", "--empty-state"]
    # Launch directly: no intermediary helper can leave the app in a different
    # process group, and `open` cannot reactivate another installed app.
    process = subprocess.Popen(
        [str(executable), *arguments], cwd=fixture, env=environment,
        start_new_session=True,
    )
    started = time.monotonic()
    try:
        if os.getpgid(process.pid) != process.pid or os.getsid(process.pid) != process.pid:
            raise RuntimeError("Fixture is not in its private watchdog session/group")
        try:
            process.wait(timeout=RUNNING_SECONDS)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise RuntimeError(f"Extracted app exited before the 10-second smoke (status {process.returncode})")
        if process.poll() is not None or os.getpgid(process.pid) != process.pid:
            raise RuntimeError("Extracted app was not running in its group at the end of the smoke")
        observed_seconds = time.monotonic() - started
    finally:
        stop_fixture(process)

    evidence = {
        "status": "passed",
        "launch_method": "subprocess.Popen extracted executable in private session/group",
        "observed_running_seconds": observed_seconds,
        "fixture_pid": process.pid,
        "fixture_terminated": process.returncode is not None,
        "arguments": arguments,
        "mock_pipeline": True,
        "in_memory_empty_state": True,
    }
    with result.open("x") as stream:
        json.dump(evidence, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print("PASS: extracted app stayed running for 10 seconds with mock services; fixture group terminated")


def interrupted(signum, frame):
    # Convert cancellation into an exception so the fixture's finally cleanup
    # still runs. SIGKILL cannot be handled by any program.
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: smoke_release.py <extracted-app> <fixture-directory> <result-json>")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        smoke(*(Path(argument).resolve() for argument in sys.argv[1:]))
    except Exception as error:
        raise SystemExit(f"Release smoke failed: {error}") from error
