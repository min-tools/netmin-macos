#!/usr/bin/env python3
"""Verify Netmin records the selected macOS SDK instead of compatibility SDK 14."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

from build import DEFAULT_DEVELOPER_DIR, swift_compiler

environment = os.environ.copy()
if 'DEVELOPER_DIR' not in environment and DEFAULT_DEVELOPER_DIR.is_dir():
    environment['DEVELOPER_DIR'] = str(DEFAULT_DEVELOPER_DIR)

with tempfile.TemporaryDirectory(prefix='netmin-sdk-linkage-', dir='/private/tmp') as directory:
    folder = Path(directory)
    source = folder / 'main.swift'
    executable = folder / 'sdk-linkage'
    source.write_text('print("Netmin SDK linkage")\n')
    command = swift_compiler() + [
        '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0',
        str(source),
        '-o', str(executable),
    ]
    subprocess.run(command, check=True, env=environment)
    build = subprocess.check_output(
        ['xcrun', 'vtool', '-show-build', str(executable)],
        text=True,
        env=environment,
    )
    expected = subprocess.check_output(
        ['xcrun', '--sdk', 'macosx', '--show-sdk-version'],
        text=True,
        env=environment,
    ).strip()
    match = re.search(r'^\s*sdk\s+([0-9.]+)$', build, re.MULTILINE)
    assert match is not None, build
    assert match.group(1) == expected, (
        f'Netmin linked SDK {match.group(1)} instead of selected SDK {expected}'
    )

print(f'Netmin SDK linkage: macOS {expected} recorded')
