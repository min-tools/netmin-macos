#!/usr/bin/env python3
"""Verify public source access and reject missing or conflicting local inputs."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EDITION = ROOT / "Sources/NetminApp/BuildEdition.swift"

with tempfile.TemporaryDirectory(prefix="netmin-public-access-", dir="/private/tmp") as directory:
    folder = Path(directory)
    executable = folder / "test"

    # The access fixture needs no Xcode plugins, so avoid a full-Xcode license dependency.
    compile_environment = os.environ.copy()
    compile_environment["DEVELOPER_DIR"] = "/Library/Developer/CommandLineTools"
    compiler = ["swiftc", "-module-cache-path", str(folder / "modules")]

    # A public source build must retain the shared identity and normal access policy.
    subprocess.run(
        compiler + [str(EDITION), str(ROOT / "scripts/test_source_build.swift"), "-o", str(executable)],
        check=True,
        env=compile_environment,
    )
    subprocess.run([str(executable)], check=True)

    # The local flag must fail when the ignored access source is absent.
    missing = subprocess.run(
        compiler + ["-typecheck", "-D", "NETMIN_LOCAL_BUILD", str(EDITION)],
        capture_output=True,
        text=True,
        env=compile_environment,
    )
    assert missing.returncode != 0 and "NetminLocalAccess" in missing.stderr

    # App Store and private-local flags must never coexist.
    conflict = subprocess.run(
        compiler + [
            "-typecheck", "-D", "NETMIN_LOCAL_BUILD", "-D", "NETMIN_APP_STORE", str(EDITION),
        ],
        capture_output=True,
        text=True,
        env=compile_environment,
    )
    assert conflict.returncode != 0 and "Local access must not be included" in conflict.stderr
