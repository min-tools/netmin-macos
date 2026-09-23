#!/usr/bin/env python3
"""Report local release failures and optionally verify public submission URLs."""
from pathlib import Path
import plistlib
import re
import socket
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent


def blockers(check_online=False):
    issues = []
    project = (ROOT / 'Netmin.xcodeproj/project.pbxproj').read_text()
    scheme = (ROOT / 'Netmin.xcodeproj/xcshareddata/xcschemes/Netmin.xcscheme').read_text()
    info = plistlib.loads((ROOT / 'NetminInfo.plist').read_bytes())
    entitlements = plistlib.loads((ROOT / 'NetminApp.entitlements').read_bytes())
    manifest = plistlib.loads((ROOT / 'Sources/NetminApp/Resources/PrivacyInfo.xcprivacy').read_bytes())
    catalog = (ROOT / 'Sources/NetminApp/Resources/tools.tsv').read_text()
    products = (ROOT / 'Sources/NetminApp/ProEntitlementLogic.swift').read_text()
    edition = (ROOT / 'Sources/NetminApp/BuildEdition.swift').read_text()
    banner = (ROOT / 'Sources/NetminApp/AccessBanner.swift').read_text()
    result_view = (ROOT / 'Sources/NetminApp/ResultView.swift').read_text()
    runner = (ROOT / 'Sources/NetminApp/CommandRunner.swift').read_text()
    policy = (ROOT / 'PRIVACY.md').read_text()
    bundled_policy = (ROOT / 'Sources/NetminApp/Resources/PRIVACY.md').read_text()

    if project.count('SWIFT_ACTIVE_COMPILATION_CONDITIONS = NETMIN_APP_STORE;') < 2:
        issues.append('AppStore must compile NETMIN_APP_STORE at project and target level.')
    app_store_target = re.search(r'100000000000000000000807.*?name = AppStore;', project, re.S)
    if app_store_target is None:
        issues.append('The Netmin target is missing its AppStore configuration.')
    if '<ArchiveAction buildConfiguration="AppStore"' not in scheme:
        issues.append('The shared scheme must archive the AppStore configuration.')
    if project.count('PRODUCT_BUNDLE_IDENTIFIER = tools.min.netmin;') < 3:
        issues.append('The Netmin bundle identifier is not consistent across configurations.')
    versions = re.findall(r'MARKETING_VERSION = ([^;]+);', project)
    build_numbers = re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project)
    if versions != ['2026.09.23'] * 3 or build_numbers != ['2026092300'] * 3:
        issues.append('The release version is inconsistent across configurations.')
    elif not all(number.startswith(version.replace('.', '')) for version, number in zip(versions, build_numbers)):
        issues.append('The version does not use the YYYY.MM.DD and YYYYMMDDNN release model.')
    if project.count('NETMIN_DISPLAY_NAME = Netmin;') != 3:
        issues.append('The Netmin display name is unresolved in one or more target configurations.')
    if 'EXECUTABLE_NAME = NetminApp;' not in project or info.get('CFBundleExecutable') != 'NetminApp':
        issues.append('The Xcode product and Info.plist executable names do not match.')
    if 'ARCHS = arm64;' not in project or info.get('LSMinimumSystemVersion') != '14.0':
        issues.append('The supported architecture or minimum macOS version changed.')
    if 'tools.min.netmin.pro.yearly' not in products or 'tools.min.netmin.pro.lifetime' not in products:
        issues.append('StoreKit product identifiers are incomplete.')
    if 'tools.min.netmin' not in edition or 'NETMIN_LOCAL_BUILD && NETMIN_APP_STORE' not in edition:
        issues.append('The shared app identity or private-build boundary is incomplete.')
    if 'struct NetminAccessBanner' not in banner or 'if store.hasResolvedEntitlement && store.hasPreparedFreeAccess && !store.hasFullAccess' not in banner:
        issues.append('The shared access banner is missing from public builds.')
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        issues.append('Encryption export declaration is missing or unresolved.')
    if info.get('NSHumanReadableCopyright') != '© 2026 Ilia Ross':
        issues.append('The About-panel copyright notice is missing.')
    if not entitlements.get('com.apple.security.app-sandbox'):
        issues.append('App Sandbox is not enabled.')
    if not entitlements.get('com.apple.security.network.client') or not entitlements.get('com.apple.security.network.server'):
        issues.append('Network client or discovery-server sandbox access is missing.')
    if manifest.get('NSPrivacyTracking') is not False:
        issues.append('Privacy manifest tracking declaration is missing.')
    collected = manifest.get('NSPrivacyCollectedDataTypes', [])
    if not any(item.get('NSPrivacyCollectedDataType') == 'NSPrivacyCollectedDataTypeOtherUserContent'
               and item.get('NSPrivacyCollectedDataTypeLinked') is True
               and item.get('NSPrivacyCollectedDataTypeTracking') is False
               for item in collected):
        issues.append('Diagnostic targets are not disclosed as linked app-functionality data.')
    if not policy.strip() or policy != bundled_policy:
        issues.append('The repository and bundled privacy policies are missing or inconsistent.')
    bonjour = set(info.get('NSBonjourServices', []))
    if not {'_services._dns-sd._udp', '_ipp._tcp', '_scanner._tcp', '_smb._tcp', '_http._tcp'} <= bonjour:
        issues.append('The local-network Bonjour service declaration is incomplete.')
    if '/usr/bin/delv' in catalog:
        issues.append('DNSSEC still depends on the non-validating macOS delv build.')
    if 'maximumDuration' not in runner or 'maximumOutputBytes' not in runner or 'process.interrupt()' not in runner:
        issues.append('Diagnostic execution is missing its duration or output safety limit.')
    if 'if model.showsRawOutput' not in result_view or 'else if !store.hasFullAccess' not in result_view:
        issues.append('Structured reports are not gated by trial or verified Pro access.')
    if 'static let trialLengthDays = 30' not in products or 'static let dailyRequestLimit = 5' not in products:
        issues.append('The 30-day trial or five-request Free allowance is missing.')
    if 'store.present(feature: .structuredReports)' not in result_view:
        issues.append('Locked report actions do not lead to the Pro purchase flow.')
    helpers = set(re.findall(r'\$NETMIN_HELPERS/([^" ]+)', catalog))
    missing_helpers = [name for name in helpers if not (ROOT / 'Sources/NetminApp/Resources/Scripts' / name).is_file()]
    if missing_helpers:
        issues.append(f'Catalog helpers are missing from the bundle: {", ".join(sorted(missing_helpers))}.')
    if info.get('CFBundleIconFile') != 'NetminIcon' or 'NetminIcon.icns' not in project:
        issues.append('The production Netmin icon is not configured.')
    if check_online:
        urls = re.findall(r'static let (?:website|privacyPolicy|purchase|support) = URL\(string: "(https://[^"]+)"\)!', edition)
        for url in urls:
            try:
                host = re.match(r'https://([^/]+)', url).group(1)
                socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
                request = Request(url, headers={'User-Agent': 'Netmin release checker/1.0'})
                with urlopen(request, timeout=10) as response:
                    if response.status >= 400:
                        issues.append(f'Public submission URL returned HTTP {response.status}: {url}')
            except HTTPError as error:
                issues.append(f'Public submission URL returned HTTP {error.code}: {url}')
            except (OSError, URLError, AttributeError) as error:
                issues.append(f'Public submission URL is unavailable: {url} ({error})')
    return issues


if __name__ == '__main__':
    unknown = [argument for argument in sys.argv[1:] if argument != '--online']
    if unknown:
        print(f'Usage: {Path(sys.argv[0]).name} [--online]', file=sys.stderr)
        sys.exit(2)
    found = blockers(check_online='--online' in sys.argv[1:])
    if found:
        print('App Store archive is blocked:')
        for issue in found:
            print(f'- {issue}')
        sys.exit(1)
    print('App Store release metadata checks passed')
