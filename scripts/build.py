#!/usr/bin/env python3
"""Build Netmin locally without requiring signing credentials."""
from pathlib import Path
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


# Prefer a complete Xcode toolchain because SwiftUI's compiler plugin is not shipped in every
# Command Line Tools installation. DEVELOPER_DIR remains available for nonstandard installs.
def swift_compiler():
    developer = Path(os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer'))
    swiftc = developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
    sdk = developer / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
    plugins = developer / 'Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins'
    if swiftc.is_file() and sdk.exists() and plugins.is_dir():
        return [str(swiftc), '-sdk', str(sdk), '-plugin-path', str(plugins)]
    return ['xcrun', 'swiftc']


# Compile a complete app in staging before replacing a prior generated bundle.
def build_app(root, output, *, configuration='Release', architectures=None,
              app_store=False, sign=True):
    root, output = Path(root).resolve(), Path(output).absolute()
    if output.suffix != '.app' or output.is_symlink():
        raise ValueError('The output must be an .app directory, not a symbolic link.')
    architectures = architectures or ['arm64']
    if architectures != ['arm64']:
        raise ValueError('Netmin builds target Apple silicon (arm64) only.')

    source_root = root / 'Sources/NetminApp'
    sources = sorted(source_root.glob('*.swift'))
    required = {'ProEntitlementLogic.swift', 'ProStore.swift', 'AccessBanner.swift'}
    if not sources or not required.issubset({path.name for path in sources}):
        raise ValueError('The Netmin source checkout is incomplete.')
    output.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()

    with tempfile.TemporaryDirectory(prefix='netmin-build-', dir=output.parent) as folder:
        work = Path(folder)
        bundle = work / output.name
        executable = bundle / 'Contents/MacOS/NetminApp'
        executable.parent.mkdir(parents=True)
        command = swift_compiler() + [
            '-swift-version', '5', '-module-name', 'NetminApp',
            '-module-cache-path', str(work / 'modules'), '-target', 'arm64-apple-macos14.0'
        ]
        command += ['-O', '-whole-module-optimization'] if configuration == 'Release' else ['-Onone', '-D', 'DEBUG']
        if app_store:
            command += ['-D', 'NETMIN_APP_STORE']
        command += [*map(str, sources), '-o', str(executable)]
        subprocess.run(command, check=True, env=environment)

        shutil.copytree(source_root / 'Resources', bundle / 'Contents/Resources')
        info = (root / 'NetminInfo.plist').read_text()
        project_path = root / 'Netmin.xcodeproj/project.pbxproj'
        project = project_path.read_text()
        versions = {}
        for key in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
            matches = set(re.findall(r'\b' + key + r' = ([^;]+);', project))
            if len(matches) != 1:
                raise ValueError(f'Expected one consistent {key} in {project_path}.')
            versions[key] = matches.pop().strip('"')
        values = {
            'NETMIN_DISPLAY_NAME': 'Netmin',
            'PRODUCT_BUNDLE_IDENTIFIER': 'tools.min.netmin',
            **versions,
        }
        for key, value in values.items():
            info = info.replace('$(' + key + ')', value)
        plist = plistlib.loads(info.encode())
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist, sort_keys=False))

        if sign:
            subprocess.run([
                'codesign', '--force', '--sign', '-', '--entitlements',
                str(root / 'NetminApp.entitlements'), str(bundle)
            ], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
        if output.exists():
            if not (output / 'Contents/Info.plist').is_file():
                raise ValueError('Refusing to replace a directory that is not an app bundle.')
            shutil.rmtree(output)
        shutil.move(bundle, output)
    mode = 'App Store' if app_store else 'source'
    print(f'Built {output} ({", ".join(architectures)}, {mode})', flush=True)
    return output


def arguments(description=__doc__):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Release')
    parser.add_argument('--arch', action='append', choices=['arm64'], dest='architectures')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--app-store', action='store_true',
                      help='Build build/app-store/Netmin.app with StoreKit enforcement.')
    mode.add_argument('--both', action='store_true',
                      help='Build both local/source and App Store test bundles.')
    parser.add_argument('--unsigned', action='store_true')
    return parser


def build_requested(root, args):
    root = Path(root).resolve()
    common = {
        'configuration': args.configuration,
        'architectures': args.architectures,
        'sign': not args.unsigned,
    }
    # Keep both standard artifacts when a release review needs to compare their compiled content.
    if args.both:
        if args.output is not None:
            raise ValueError('--output cannot be used with --both.')
        return [
            build_app(root, root / 'build/Netmin.app', **common),
            build_app(root, root / 'build/app-store/Netmin.app', app_store=True, **common),
        ]

    # Give the StoreKit test build its own default path so it cannot replace the local build.
    output = args.output or root / (
        'build/app-store/Netmin.app' if args.app_store else 'build/Netmin.app'
    )
    return [build_app(root, output, app_store=args.app_store, **common)]


if __name__ == '__main__':
    args = arguments().parse_args()
    build_requested(ROOT, args)
