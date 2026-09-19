#!/usr/bin/env python3
"""Validate Netmin's language coverage, catalog coverage, and format safety."""

from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'Sources/NetminApp'
RESOURCES = SOURCE / 'Resources'
LANGUAGES = [
    'en', 'ru', 'es', 'de', 'fr', 'it', 'pt', 'zh-Hans', 'ja', 'uk', 'ko',
    'zh-Hant', 'tr', 'pl', 'nl', 'id', 'vi', 'hi', 'sv', 'da', 'nb', 'fi',
    'cs', 'hr', 'th', 'sr', 'sr-Latn',
]
FORMAT = re.compile(r'%%|%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|ll|h|l|q|z|t|j)?([@diuoxXfFeEgGaAcCsSp])')
LOCALIZED = re.compile(r'localized(?:Format)?\(\s*"((?:[^"\\]|\\.)*)"')
RUNTIME_VALUES = {
    'active', 'closed', 'complete zone', 'configured', 'differs', 'down', 'incomplete',
    'inactive', 'local', 'network', 'networks', 'open', 'reachable', 'scoped',
    'timed out', 'unknown', 'up',
}
CORE_TRANSLATIONS = {
    'Purchase or restore access to unlock them.',
    'Netmin stopped this command after %lld seconds.',
    'No devices match “%@”',
    'Pro features are locked',
}


def strings_values(path):
    result = subprocess.run(
        ['plutil', '-convert', 'json', '-o', '-', str(path)],
        capture_output=True, check=True,
    )
    return json.loads(result.stdout)


def formats(text):
    result = []
    for match in FORMAT.finditer(text):
        if match.group(0) != '%%':
            result.append(((int(match.group(1)) if match.group(1) else None), (match.group(2) or '') + match.group(3)))
    return result


def catalog_strings():
    values = set()
    group = 'Other'
    for raw in (RESOURCES / 'tools.tsv').read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            group = line[1:-1]
            values.add(group)
            continue
        fields = raw.split('\t')
        command = fields[1] if len(fields) > 1 else ''
        uses_resolver = '$2' in command or '${2' in command
        description = 4 if uses_resolver else 3
        option = description + 1
        progress = option + 3
        indexes = [0, 2, description, option, progress] + ([3] if uses_resolver else [])
        values.update(fields[index].strip() for index in indexes if index < len(fields) and fields[index].strip())
    return values


def fail(message):
    print(f'FAIL: {message}')
    return False


def main():
    ok = True
    project = (ROOT / 'Netmin.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    package = (ROOT / 'Package.swift').read_text(encoding='utf-8')
    if 'Localizable.strings in Resources' not in project or 'InfoPlist.strings in Resources' not in project:
        ok &= fail('Xcode does not embed both localization variant groups')
    if '.process("Resources")' not in package:
        ok &= fail('Swift Package resources are not processed for localization lookup')
    for language in LANGUAGES:
        for filename in ('Localizable.strings', 'InfoPlist.strings'):
            expected_path = f'Sources/NetminApp/Resources/{language}.lproj/{filename}'
            if expected_path not in project:
                ok &= fail(f'Xcode is missing {expected_path}')

    folders = sorted(path.parent.name.removesuffix('.lproj') for path in RESOURCES.glob('*.lproj/Localizable.strings'))
    if sorted(LANGUAGES) != folders:
        ok &= fail(f'language folders differ: expected {sorted(LANGUAGES)}, found {folders}')

    english_path = RESOURCES / 'en.lproj/Localizable.strings'
    if not english_path.exists():
        return 1 if not fail('English localization is missing') else 0
    english = strings_values(english_path)
    english_info = strings_values(RESOURCES / 'en.lproj/InfoPlist.strings')
    expected = set(english)
    if len(expected) < 700:
        ok &= fail(f'English catalog is unexpectedly small ({len(expected)} keys)')

    source_keys = set()
    for path in SOURCE.glob('*.swift'):
        source_keys.update(match.group(1).replace(r'\"', '"') for match in LOCALIZED.finditer(path.read_text(encoding='utf-8')))
    missing_source = (source_keys | RUNTIME_VALUES) - expected
    if missing_source:
        ok &= fail('localized() source keys missing from English: ' + ', '.join(sorted(missing_source)[:8]))

    missing_catalog = catalog_strings() - expected
    if missing_catalog:
        ok &= fail('tool catalog text missing from English: ' + ', '.join(sorted(missing_catalog)[:8]))

    for language in LANGUAGES:
        folder = RESOURCES / f'{language}.lproj'
        localizable = folder / 'Localizable.strings'
        info = folder / 'InfoPlist.strings'
        if not localizable.exists() or not info.exists():
            ok &= fail(f'{language}: resource files are incomplete')
            continue
        values = strings_values(localizable)
        if set(values) != expected:
            missing, extra = expected - set(values), set(values) - expected
            ok &= fail(f'{language}: {len(missing)} missing and {len(extra)} unexpected keys')
        mismatched = [key for key in expected & set(values) if formats(key) != formats(values[key])]
        if mismatched:
            ok &= fail(f'{language}: incompatible format arguments: {", ".join(sorted(mismatched)[:8])}')
        if any('[[[NETMIN_' in value or 'NETMINFORMAT' in value for value in values.values()):
            ok &= fail(f'{language}: translation markers remain in output')
        info_values = strings_values(info)
        if set(info_values) != {'NSLocalNetworkUsageDescription'}:
            ok &= fail(f'{language}: InfoPlist.strings has the wrong keys')
        if language != 'en' and info_values == english_info:
            ok &= fail(f'{language}: the local-network permission text is not translated')
        if language != 'en':
            # Count only present translations because missing keys are reported above.
            changed = sum(
                key in values and values[key] != english[key]
                for key in expected
            )
            if changed < len(expected) // 2:
                ok &= fail(f'{language}: only {changed}/{len(expected)} strings are translated')
            untranslated_core = sorted(key for key in CORE_TRANSLATIONS if values.get(key) == english.get(key))
            if untranslated_core:
                ok &= fail(f'{language}: core UI text is untranslated: {", ".join(untranslated_core)}')
        print(f'{language}: {len(values)} strings')

    print(f'{len(LANGUAGES)} languages; {len(expected)} strings per language')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
