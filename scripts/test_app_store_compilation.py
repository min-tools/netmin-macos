#!/usr/bin/env python3
"""Type-check the App Store variant with StoreKit purchase enforcement enabled."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

sources = sorted((ROOT / 'Sources/NetminApp').glob('*.swift'))
with tempfile.TemporaryDirectory(prefix='netmin-app-store-', dir='/private/tmp') as directory:
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-typecheck', '-module-name', 'NetminApp',
        '-module-cache-path', str(Path(directory) / 'modules'),
        '-target', 'arm64-apple-macos14.0', '-D', 'NETMIN_APP_STORE', *map(str, sources),
    ]
    subprocess.run(command, check=True)
print('App Store build type-check passed with StoreKit enforcement')
