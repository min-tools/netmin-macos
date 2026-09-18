#!/usr/bin/env python3
"""Check App Store packaging mode with a fake compiler."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build as builder


class AppStoreBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='netmin-app-store-build-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'Netmin'
        self.output = Path(self.temp.name) / 'output/Netmin.app'
        files = {
            self.root / 'Sources/NetminApp/ProEntitlementLogic.swift': '// fixture',
            self.root / 'Sources/NetminApp/ProStore.swift': '// fixture',
            self.root / 'Sources/NetminApp/AccessBanner.swift': '// fixture',
            self.root / 'Sources/NetminApp/Resources/tools.tsv': '[Fixture]\nTool\t/bin/true\n',
            self.root / 'NetminInfo.plist': (builder.ROOT / 'NetminInfo.plist').read_text(),
            self.root / 'NetminApp.entitlements': (builder.ROOT / 'NetminApp.entitlements').read_text(),
            self.root / 'Netmin.xcodeproj/project.pbxproj':
                'MARKETING_VERSION = 2.5; CURRENT_PROJECT_VERSION = 25;',
        }
        for path, text in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.command = None

    def compile_fixture(self, command, **kwargs):
        self.command = command
        Path(command[command.index('-o') + 1]).write_bytes(b'fixture executable')
        return subprocess.CompletedProcess(command, 0)

    def test_app_store_mode_enables_storekit_enforcement(self):
        with patch.object(builder.subprocess, 'run', side_effect=self.compile_fixture):
            builder.build_app(self.root, self.output, app_store=True, sign=False)
        self.assertIn('NETMIN_APP_STORE', self.command)
        self.assertNotIn('NETMIN_LOCAL_BUILD', self.command)
        self.assertTrue(self.output.is_dir())


if __name__ == '__main__':
    unittest.main()
