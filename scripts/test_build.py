#!/usr/bin/env python3
"""Check staged source-build packaging with a fake compiler."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build as builder


class BuildTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(builder.os.environ, {}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        self.temp = tempfile.TemporaryDirectory(prefix='netmin-build-fixture-', dir='/private/tmp')
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
                'MARKETING_VERSION = 1.2.3; CURRENT_PROJECT_VERSION = 123;',
        }
        for path, text in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.commands = []

    def compile_fixture(self, command, **kwargs):
        self.assertEqual(command[command.index('-target') + 1], 'arm64-apple-macos14.0')
        self.commands.append(command)
        Path(command[command.index('-o') + 1]).write_bytes(b'fixture executable')
        return subprocess.CompletedProcess(command, 0)

    def test_source_identity_version_and_public_access(self):
        with patch.object(builder.subprocess, 'run', side_effect=self.compile_fixture):
            builder.build_app(self.root, self.output, sign=False)
        info = plistlib.loads((self.output / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'tools.min.netmin')
        self.assertEqual(info['CFBundleDisplayName'], 'Netmin')
        self.assertEqual(info['CFBundleShortVersionString'], '1.2.3')
        self.assertEqual(info['CFBundleVersion'], '123')
        self.assertNotIn('NETMIN_APP_STORE', self.commands[0])
        self.assertNotIn('NETMIN_LOCAL_BUILD', self.commands[0])

    def test_unsupported_architecture_fails_before_compile(self):
        with patch.object(builder.subprocess, 'run') as compiler:
            with self.assertRaisesRegex(ValueError, 'arm64'):
                builder.build_app(self.root, self.output, architectures=['x86_64'], sign=False)
            compiler.assert_not_called()

    def test_incomplete_source_fails_before_compile(self):
        (self.root / 'Sources/NetminApp/ProStore.swift').unlink()
        with patch.object(builder.subprocess, 'run') as compiler:
            with self.assertRaisesRegex(ValueError, 'source checkout is incomplete'):
                builder.build_app(self.root, self.output, sign=False)
            compiler.assert_not_called()

    def test_failed_compile_preserves_previous_app(self):
        previous = self.output / 'Contents/Info.plist'
        previous.parent.mkdir(parents=True)
        previous.write_text('previous')
        with patch.object(builder.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'swiftc')):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.build_app(self.root, self.output, sign=False)
        self.assertEqual(previous.read_text(), 'previous')

    def test_both_modes_keep_distinct_default_outputs(self):
        args = argparse.Namespace(
            output=None, configuration='Release', architectures=['arm64'],
            app_store=False, both=True, unsigned=True,
        )
        with patch.object(builder, 'build_app', side_effect=lambda root, output, **kwargs: Path(output)) as build:
            outputs = builder.build_requested(self.root, args)
        self.assertEqual(outputs, [
            self.root.resolve() / 'build/Netmin.app',
            self.root.resolve() / 'build/app-store/Netmin.app',
        ])
        self.assertNotIn('app_store', build.call_args_list[0].kwargs)
        self.assertTrue(build.call_args_list[1].kwargs['app_store'])

    def test_app_store_mode_uses_its_own_default_output(self):
        args = argparse.Namespace(
            output=None, configuration='Release', architectures=None,
            app_store=True, both=False, unsigned=True,
        )
        with patch.object(builder, 'build_app', side_effect=lambda root, output, **kwargs: Path(output)):
            outputs = builder.build_requested(self.root, args)
        self.assertEqual(outputs, [self.root.resolve() / 'build/app-store/Netmin.app'])

    def test_both_modes_reject_one_shared_output(self):
        args = argparse.Namespace(
            output=self.output, configuration='Release', architectures=None,
            app_store=False, both=True, unsigned=True,
        )
        with self.assertRaisesRegex(ValueError, '--output'):
            builder.build_requested(self.root, args)


if __name__ == '__main__':
    unittest.main()
