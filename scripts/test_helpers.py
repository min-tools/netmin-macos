#!/usr/bin/env python3
"""Validate bundled helpers without relying on Homebrew or unbundled scripts."""
from pathlib import Path
import os
import re
import subprocess

from build import ROOT

resources = ROOT / 'Sources/NetminApp/Resources'
scripts = resources / 'Scripts'
catalog = (resources / 'tools.tsv').read_text()

assert '/opt/homebrew' not in catalog
assert '/usr/local' not in catalog
assert '/usr/bin/env python' not in catalog
assert '/usr/bin/env perl' not in catalog
assert 'python' not in catalog.lower()
assert 'perl' not in catalog.lower()

for name in set(re.findall(r'\$NETMIN_HELPERS/([^" ]+)', catalog)):
    assert (scripts / name).is_file(), f'Catalog helper is not bundled: {name}'

runtime_text = catalog + '\n' + '\n'.join(script.read_text() for script in scripts.glob('*.sh'))
system_commands = set(re.findall(r'(?<![A-Za-z0-9_$])(/(?:usr/)?(?:s?bin)/[A-Za-z0-9._-]+)', runtime_text))
for command in system_commands:
    assert Path(command).is_file() and os.access(command, os.X_OK), f'System command is unavailable: {command}'

for script in scripts.glob('*.sh'):
    subprocess.run(['/bin/bash', '-n', str(script)], check=True)

utility = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-network-utils.sh'), 'cidr', '192.0.2.14/24'],
    check=True, capture_output=True, text=True,
)
assert 'Network: 192.0.2.0' in utility.stdout and 'Addresses: 256' in utility.stdout
punycode = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-network-utils.sh'), 'punycode', 'münich.example'],
    check=True, capture_output=True, text=True,
)
assert 'ASCII: xn--mnich-kva.example' in punycode.stdout
mac = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-mac-format.sh'), 'aa-bb-cc-dd-ee-ff'],
    check=True, capture_output=True, text=True,
)
assert mac.stdout == 'AA:BB:CC:DD:EE:FF\n'
# Traceroute is built on TTL-limited ping; a fake ping stands in for the network here.
import tempfile
with tempfile.TemporaryDirectory(prefix='netmin-fake-ping-', dir='/private/tmp') as fake_dir:
    fake_ping = Path(fake_dir) / 'ping'
    fake_ping.write_text('''#!/bin/bash
ttl=0
while (( $# )); do case $1 in -m) ttl=$2; shift ;; esac; shift; done
printf 'PING 203.0.113.9 (203.0.113.9): 56 data bytes\\n'
if (( ttl < 3 )); then
    printf '36 bytes from 10.0.0.%s: Time to live exceeded\\n' "$ttl"
elif (( ttl == 3 )); then
    printf '\\n--- 203.0.113.9 ping statistics ---\\n1 packets transmitted, 0 packets received, 100.0%% packet loss\\n'
    exit 2
else
    printf '64 bytes from 203.0.113.9: icmp_seq=0 ttl=60 time=12.345 ms\\n'
fi
''')
    fake_ping.chmod(0o755)
    trace = subprocess.run(
        ['/bin/bash', str(scripts / 'netmin-traceroute.sh'), '203.0.113.9', '6'],
        check=True, capture_output=True, text=True, timeout=30,
        env={**os.environ, 'NETMIN_PING': str(fake_ping)},
    )
    trace_lines = trace.stdout.splitlines()
    assert trace_lines[0].startswith('traceroute to 203.0.113.9 (203.0.113.9), 6 hops max'), trace.stdout
    assert trace_lines[1].endswith('(10.0.0.1)') and trace_lines[2].endswith('(10.0.0.2)'), trace.stdout
    assert trace_lines[3] == ' 3  * * *', trace.stdout
    assert trace_lines[4].endswith('(203.0.113.9)  12.345 ms') and len(trace_lines) == 5, trace.stdout
no_target = subprocess.run(['/bin/bash', str(scripts / 'netmin-traceroute.sh')], capture_output=True, text=True, timeout=8)
assert no_target.returncode == 64
loopback = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-traceroute.sh'), '127.0.0.1', '2'],
    check=True, capture_output=True, text=True, timeout=20,
)
assert ' 1  ' in loopback.stdout and '(127.0.0.1)' in loopback.stdout and ' ms' in loopback.stdout, loopback.stdout

# The sweep validates every comma-separated range before it scans anything.
bad_sweep = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-local-device-sweep.sh'), '192.0.2.0/24,10.0.0.0/33'],
    capture_output=True, text=True, timeout=8,
)
assert bad_sweep.returncode == 64 and '10.0.0.0/33' in bad_sweep.stderr
too_many_ranges = ','.join(f'192.0.2.{index * 4}/30' for index in range(17))
bounded_sweep = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-local-device-sweep.sh'), too_many_ranges],
    capture_output=True, text=True, timeout=8,
)
assert bounded_sweep.returncode == 64 and 'at most 16 ranges' in bounded_sweep.stderr
ports = subprocess.run(
    ['/bin/bash', str(scripts / 'netmin-common-port-scan.sh'), '127.0.0.1'],
    check=True, capture_output=True, text=True, timeout=8,
)
assert 'Open ports:' in ports.stdout

# DNS discovery has deterministic Quick and complete-AXFR paths when DNS is replaced by a fixture.
with tempfile.TemporaryDirectory(prefix='netmin-fake-dns-', dir='/private/tmp') as fake_dir:
    fake_dig = Path(fake_dir) / 'dig'
    fake_dig.write_text(r'''#!/bin/bash
args=" $* "
if [[ $args == *" AXFR "* ]]; then
    if [[ ${NETMIN_AXFR_COMPLETE:-0} == 1 ]]; then
        printf 'example.test. 300 IN SOA ns1.example.test. hostmaster.example.test. 1 3600 600 86400 300\n'
        printf 'www.example.test. 300 IN CNAME example.test.\n'
        printf 'example.test. 300 IN SOA ns1.example.test. hostmaster.example.test. 1 3600 600 86400 300\n'
        exit 0
    fi
    printf '; Transfer failed.\n'
    exit 9
fi
name=''; type=''
for value in "$@"; do
    [[ $value == +* || $value == @* ]] && continue
    name=${type:-$value}; type=$value
done
case "$name $type" in
    'example.test SOA') printf 'example.test. 300 IN SOA ns1.example.test. hostmaster.example.test. 1 3600 600 86400 300\n' ;;
    'example.test NS')
        if [[ $args == *' +short '* ]]; then printf 'ns1.example.test.\n';
        else printf 'example.test. 300 IN NS ns1.example.test.\n'; fi ;;
    'example.test A') printf 'example.test. 300 IN A 192.0.2.10\n' ;;
    'sig1._domainkey.example.test CNAME') printf 'sig1._domainkey.example.test. 300 IN CNAME dkim.example.invalid.\n' ;;
esac
''')
    fake_dig.chmod(0o755)
    discovery = scripts / 'netmin-dns-zone-discovery.sh'
    quick = subprocess.run(
        ['/bin/bash', str(discovery), 'example.test'], check=True, capture_output=True, text=True,
        timeout=15, env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert 'Completeness: Partial discovery' in quick.stdout
    assert 'sig1._domainkey.example.test.' in quick.stdout
    deep = subprocess.run(
        ['/bin/bash', str(discovery), 'example.test', '--deep'], check=True,
        capture_output=True, text=True, timeout=15,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig), 'NETMIN_AXFR_COMPLETE': '1'},
    )
    assert 'Completeness: Complete' in deep.stdout and 'Method: AXFR from ns1.example.test' in deep.stdout
    transfer_helper = scripts / 'netmin-dns-zone-transfer.sh'
    allowed_transfer = subprocess.run(
        ['/bin/bash', str(transfer_helper), 'example.test'], check=True,
        capture_output=True, text=True, timeout=15,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig), 'NETMIN_AXFR_COMPLETE': '1'},
    )
    assert 'Authoritative server: ns1.example.test' in allowed_transfer.stdout
    assert 'Transfer: Allowed' in allowed_transfer.stdout
    refused_transfer = subprocess.run(
        ['/bin/bash', str(transfer_helper), 'example.test'], check=True,
        capture_output=True, text=True, timeout=15,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert 'No authoritative server allowed a complete zone transfer.' in refused_transfer.stdout

# Resolver comparison is deterministic when dig is replaced by a local fixture.
with tempfile.TemporaryDirectory(prefix='netmin-fake-propagation-', dir='/private/tmp') as fake_dir:
    fake_dig = Path(fake_dir) / 'dig'
    fake_dig.write_text(r'''#!/bin/bash
resolver=${1#@}; shift
reverse=0
name=''; type=''
while (( $# )); do
    case $1 in
        +*) ;;
        -x) reverse=1 ;;
        *) if [[ -z $name ]]; then name=$1; else type=$1; fi ;;
    esac
    shift
done
if (( reverse )); then printf '10.2.0.192.in-addr.arpa. 300 IN PTR ptr.example.test.\n'; exit 0; fi
case $type in
    A) printf 'example.test. 300 IN A 192.0.2.10\n' ;;
    AAAA) printf 'example.test. 300 IN AAAA 2001:db8::10\n' ;;
    MX) printf 'example.test. 300 IN MX 10 mail.example.test.\n' ;;
esac
''')
    fake_dig.chmod(0o755)
    propagation = scripts / 'netmin-dns-propagation.sh'
    primary = subprocess.run(
        ['/bin/bash', str(propagation), 'example.test'], check=True,
        capture_output=True, text=True, timeout=10,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert primary.stdout.count('Resolver ') == 4 and primary.stdout.count('192.0.2.10') == 4
    all_records = subprocess.run(
        ['/bin/bash', str(propagation), 'example.test', '--all'], check=True,
        capture_output=True, text=True, timeout=10,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert 'A 192.0.2.10' in all_records.stdout and 'AAAA 2001:db8::10' in all_records.stdout
    reverse = subprocess.run(
        ['/bin/bash', str(propagation), '192.0.2.10'], check=True,
        capture_output=True, text=True, timeout=10,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert reverse.stdout.count('ptr.example.test.') == 4

# macOS ships delv without trust anchors, so DNSSEC uses a validating resolver through dig.
with tempfile.TemporaryDirectory(prefix='netmin-fake-dnssec-', dir='/private/tmp') as fake_dir:
    fake_dig = Path(fake_dir) / 'dig'
    fake_dig.write_text(r'''#!/bin/bash
if [[ ${NETMIN_DNSSEC_AUTHENTICATED:-0} == 1 ]]; then
    printf ';; flags: qr rd ra ad; QUERY: 1, ANSWER: 1\n'
else
    printf ';; flags: qr rd ra; QUERY: 1, ANSWER: 1\n'
fi
printf 'example.test. 300 IN A 192.0.2.10\n'
''')
    fake_dig.chmod(0o755)
    validation = scripts / 'netmin-dnssec-validation.sh'
    secure = subprocess.run(
        ['/bin/bash', str(validation), 'example.test', 'A'], check=True,
        capture_output=True, text=True,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig), 'NETMIN_DNSSEC_AUTHENTICATED': '1'},
    )
    assert 'Validating resolver: 1.1.1.1' in secure.stdout and 'Validation: Secure' in secure.stdout
    custom = subprocess.run(
        ['/bin/bash', str(validation), 'example.test', 'A', '9.9.9.9'], check=True,
        capture_output=True, text=True,
        env={**os.environ, 'NETMIN_DIG': str(fake_dig), 'NETMIN_DNSSEC_AUTHENTICATED': '1'},
    )
    assert 'Validating resolver: 9.9.9.9' in custom.stdout
    insecure = subprocess.run(
        ['/bin/bash', str(validation), 'example.test', 'TLSA'], check=True,
        capture_output=True, text=True, env={**os.environ, 'NETMIN_DIG': str(fake_dig)},
    )
    assert 'Validation: Not authenticated' in insecure.stdout

print('Bundled helpers: Bash tools and macOS command fallbacks passed')
