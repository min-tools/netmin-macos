#!/usr/bin/env python3
"""Check privacy, sandbox, identity, and release metadata without launching the app."""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent.parent
info = plistlib.loads((ROOT / 'NetminInfo.plist').read_bytes())
entitlements = plistlib.loads((ROOT / 'NetminApp.entitlements').read_bytes())
manifest = plistlib.loads((ROOT / 'Sources/NetminApp/Resources/PrivacyInfo.xcprivacy').read_bytes())
policy = (ROOT / 'PRIVACY.md').read_text()
bundled_policy = (ROOT / 'Sources/NetminApp/Resources/PRIVACY.md').read_text()
project = (ROOT / 'Netmin.xcodeproj/project.pbxproj').read_text()
readme = (ROOT / 'README.md').read_text()
license_text = (ROOT / 'LICENSE').read_text()

assert policy == bundled_policy, 'Bundled and repository privacy policies differ'
assert license_text.startswith('# PolyForm Strict License 1.0.0\n')
assert 'PolyForm Strict License 1.0.0' in license_text
assert 'Additional Permission for Personal Modification' in license_text
assert 'Additional Permission for Contributions' in license_text
assert 'PolyForm Strict License 1.0.0' in readme and 'Elastic License' not in readme
assert info['ITSAppUsesNonExemptEncryption'] is False
assert info['LSApplicationCategoryType'] == 'public.app-category.utilities'
assert info['NSLocalNetworkUsageDescription'].strip()
bonjour = set(info['NSBonjourServices'])
assert {'_services._dns-sd._udp', '_ipp._tcp', '_scanner._tcp', '_smb._tcp', '_http._tcp'} <= bonjour
assert entitlements['com.apple.security.app-sandbox'] is True
assert entitlements['com.apple.security.network.client'] is True
assert entitlements['com.apple.security.network.server'] is True
assert manifest['NSPrivacyTracking'] is False
collected = manifest['NSPrivacyCollectedDataTypes']
assert len(collected) == 1
assert collected[0]['NSPrivacyCollectedDataType'] == 'NSPrivacyCollectedDataTypeOtherUserContent'
assert collected[0]['NSPrivacyCollectedDataTypeLinked'] is True
assert collected[0]['NSPrivacyCollectedDataTypeTracking'] is False
assert collected[0]['NSPrivacyCollectedDataTypePurposes'] == ['NSPrivacyCollectedDataTypePurposeAppFunctionality']
reasons = manifest['NSPrivacyAccessedAPITypes']
assert any(item['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryUserDefaults'
           and 'CA92.1' in item['NSPrivacyAccessedAPITypeReasons'] for item in reasons)
assert project.count('PRODUCT_BUNDLE_IDENTIFIER = tools.min.netmin;') == 3
assert project.count('NETMIN_DISPLAY_NAME = Netmin;') == 3
assert 'NETMIN_APP_STORE' in project
assert info['NSAppTransportSecurity']['NSAllowsLocalNetworking'] is True

# Prevent renamed product paths, identifiers, and internal comparison apps from returning in
# source, documentation, project metadata, or release scripts.
old_product = 'Network' + 'ing'
old_peer_apps = ('Lang' + 'min', 'Paste' + 'min')
legacy_markers = (
    f'{old_product}App', f'{old_product} Free', f'{old_product} for macOS',
    f'{old_product}.xcodeproj', f'{old_product}Info.plist', f'{old_product}App.entitlements',
    f'Sources/{old_product}App', f'{old_product.upper()}_',
    f'app.{old_peer_apps[0].lower()}.{old_product.lower()}',
    f'{old_product.lower()}-app-macos', 'wid' + 'get-', *old_peer_apps,
)
text_suffixes = {
    '.entitlements', '.json', '.md', '.pbxproj', '.plist', '.py', '.sh', '.swift',
    '.tsv', '.xcprivacy', '.xcscheme',
}
stale_branding = []
for path in ROOT.rglob('*'):
    relative = path.relative_to(ROOT)
    if path.resolve() == Path(__file__).resolve():
        continue
    if not path.is_file() or {'.git', '.build', 'build', '__pycache__'} & set(relative.parts):
        continue
    if path.suffix not in text_suffixes and path.name not in {'.gitignore', 'LICENSE'}:
        continue
    text = path.read_text()
    for marker in legacy_markers:
        if marker in str(relative) or marker in text:
            stale_branding.append(f'{relative}: {marker}')
assert not stale_branding, 'Legacy branding remains:\n' + '\n'.join(stale_branding)

print('Netmin privacy, sandbox, identity, and App Store metadata passed')
