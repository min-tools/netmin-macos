#!/bin/bash

# Discover as much of a public DNS zone as its operator exposes. DNS has no dependable public
# "list" operation: only an allowed AXFR is complete, while direct queries, NSEC, and certificate
# transparency are useful but necessarily partial.

set -u

dig_command=${NETMIN_DIG:-/usr/bin/dig}
curl_command=${NETMIN_CURL:-/usr/bin/curl}
requested=${1-}
deep=0
[[ ${2-} == --deep ]] && deep=1

if [[ -z $requested ]]; then
    printf '%s\n' 'Enter a domain or hostname.' >&2
    exit 64
fi
requested=${requested%.}
if (( ${#requested} > 253 )) || [[ $requested != *.* ]] || [[ $requested == .* ]] ||
   [[ $requested == *..* ]] || [[ $requested =~ [^A-Za-z0-9_.-] ]]; then
    printf '%s\n' 'Enter a valid DNS name without a scheme, path, port, or spaces.' >&2
    exit 64
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/netmin-dns-zone.XXXXXX") || exit 1
trap '/bin/rm -rf "$work"' EXIT
all_records=$work/records
: >"$all_records"

section() {
    printf '\n%s\n' "$1"
}

emit() {
    local answer=$1 line
    [[ -n $answer ]] || return 1
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        if ! /usr/bin/grep -Fqx -- "$line" "$all_records"; then
            printf '%s\n' "$line"
            printf '%s\n' "$line" >>"$all_records"
        fi
    done <<<"$answer"
}

query() {
    local name=$1 type=$2 answer
    answer=$("$dig_command" +time=2 +tries=1 +noall +answer "$name" "$type" 2>/dev/null)
    emit "$answer"
}

query_name() {
    local name=$1; shift
    local type answer found=0
    for type in "$@"; do
        answer=$("$dig_command" +time=2 +tries=1 +noall +answer "$name" "$type" 2>/dev/null)
        if [[ -n $answer ]]; then emit "$answer"; found=1; fi
    done
    return $((found == 0))
}

# A hostname inside a zone is accepted. Walk towards the root until its enclosing SOA is found.
zone=$requested
soa=''
while [[ $zone == *.* ]]; do
    soa=$("$dig_command" +time=2 +tries=1 +short "$zone" SOA 2>/dev/null | /usr/bin/head -n 1)
    [[ -n $soa ]] && break
    zone=${zone#*.}
done
if [[ -z $soa ]]; then
    printf 'No authoritative DNS zone was found for %s.\n' "$requested" >&2
    exit 68
fi

mode=Quick
(( deep )) && mode=Deep
printf 'DNS zone discovery for %s\n' "$zone"
printf 'Requested name: %s\n' "$requested"
printf 'Mode: %s\n' "$mode"
if [[ $zone != "$requested" ]]; then printf 'Zone apex detected: %s\n' "$zone"; fi

section 'Authoritative DNS'
query "$zone" SOA || true
ns_records=$("$dig_command" +time=2 +tries=1 +noall +answer "$zone" NS 2>/dev/null)
if [[ -n $ns_records ]]; then emit "$ns_records"; else printf '%s\n' 'No authoritative nameservers were returned.'; fi
nameservers=$(printf '%s\n' "$ns_records" | /usr/bin/awk '$4 == "NS" { sub(/\.$/, "", $5); print $5 }' | /usr/bin/sort -u)

# A permitted transfer is the one standards-based way to receive the complete zone.
if (( deep )) && [[ -n $nameservers ]]; then
    section 'Zone transfer attempts'
    while IFS= read -r server; do
        [[ -n $server ]] || continue
        printf 'Trying AXFR from %s…\n' "$server"
        transfer=$work/axfr
        if "$dig_command" +time=4 +tries=1 AXFR "$zone" "@$server" >"$transfer" 2>&1 &&
           /usr/bin/grep -Eq '[[:space:]]IN[[:space:]]+SOA[[:space:]]' "$transfer" &&
           ! /usr/bin/grep -Eqi 'transfer failed|refused|timed out|communications error' "$transfer"; then
            section 'Complete zone transfer'
            /bin/cat "$transfer"
            /usr/bin/awk '$2 ~ /^[0-9]+$/ && $3 == "IN" { print }' "$transfer" >>"$all_records"
            section 'Discovery status'
            unique=$(/usr/bin/sort -u "$all_records" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
            printf '%s\n' 'Completeness: Complete'
            printf 'Method: AXFR from %s\n' "$server"
            printf 'Unique records: %s\n' "$unique"
            exit 0
        fi
        reason=$(/usr/bin/grep -Ei 'transfer failed|refused|timed out|communications error' "$transfer" | /usr/bin/head -n 1)
        printf 'Not available%s\n' "${reason:+ · $reason}"
    done <<<"$nameservers"
fi

section 'Zone apex records'
apex_before=$(/usr/bin/wc -l <"$all_records")
for type in A AAAA CNAME MX TXT CAA NAPTR LOC TYPE65 TYPE64 DNSKEY DS; do query "$zone" "$type" || true; done
apex_after=$(/usr/bin/wc -l <"$all_records")
(( apex_after > apex_before )) || printf '%s\n' 'No apex records were returned.'

section 'Mail and domain policies'
policy_before=$(/usr/bin/wc -l <"$all_records")
query_name "_dmarc.$zone" TXT || true
query_name "_smtp._tls.$zone" TXT || true
query_name "_mta-sts.$zone" TXT || true
query_name "default._bimi.$zone" TXT || true
policy_after=$(/usr/bin/wc -l <"$all_records")
(( policy_after > policy_before )) || printf '%s\n' 'No standard DMARC, TLS-RPT, MTA-STS, or BIMI records were found.'

section 'Standard services'
service_before=$(/usr/bin/wc -l <"$all_records")
for label in _autodiscover._tcp _submission._tcp _submissions._tcp _imaps._tcp _pop3s._tcp \
             _sip._tcp _sip._udp _sips._tcp _xmpp-client._tcp _xmpp-server._tcp \
             _caldavs._tcp _carddavs._tcp; do
    query "$label.$zone" SRV || true
done
service_after=$(/usr/bin/wc -l <"$all_records")
(( service_after > service_before )) || printf '%s\n' 'No records were found at the standard SRV service names.'

section 'Common hostnames'
host_before=$(/usr/bin/wc -l <"$all_records")
hosts=(www mail smtp imap pop webmail autodiscover autoconfig ftp api vpn ns1 ns2)
if (( deep )); then hosts+=(admin portal dev staging test status cdn files remote gateway router); fi
for label in "${hosts[@]}"; do query_name "$label.$zone" A AAAA CNAME MX || true; done
host_after=$(/usr/bin/wc -l <"$all_records")
(( host_after > host_before )) || printf '%s\n' 'No records were found at the common hostnames tested.'

section 'Common DKIM selectors'
dkim_before=$(/usr/bin/wc -l <"$all_records")
selectors=(default selector1 selector2 google k1 k2 s1 s2 sig1 sig2 dkim mail mandrill)
for selector in "${selectors[@]}"; do query_name "$selector._domainkey.$zone" TXT CNAME || true; done
dkim_after=$(/usr/bin/wc -l <"$all_records")
(( dkim_after > dkim_before )) || printf '%s\n' 'No records were found for the common DKIM selectors tested.'

if (( deep )); then
    section 'DNSSEC enumeration signals'
    nsec3=$("$dig_command" +time=2 +tries=1 +short "$zone" NSEC3PARAM 2>/dev/null)
    if [[ -n $nsec3 ]]; then
        printf '%s\n' 'NSEC3 is enabled, so DNSSEC does not expose an ordered list of zone names.'
        printf '%s\n' "$nsec3"
    else
        probe="netmin-discovery-${RANDOM}.$zone"
        denial=$("$dig_command" +time=2 +tries=1 +dnssec +noall +authority "$probe" A 2>/dev/null | /usr/bin/awk '$4 == "NSEC" { print; exit }')
        if [[ -n $denial ]]; then
            printf '%s\n' 'A walkable NSEC denial record was exposed:'
            printf '%s\n' "$denial"
        else
            printf '%s\n' 'No walkable NSEC record was exposed through the current resolver.'
        fi
    fi

    section 'Certificate transparency names'
    ct_json=$work/ct.json
    ct_names=$work/ct-names
    if "$curl_command" -fsSL --connect-timeout 4 --max-time 12 \
       "https://crt.sh/?q=%25.$zone&output=json" >"$ct_json" 2>/dev/null; then
        /usr/bin/awk -v zone="$zone" '
            BEGIN { RS="\\\"name_value\\\":\\\"" }
            NR > 1 {
                value=$0; sub(/\\\".*/, "", value); gsub(/\\\\n/, "\n", value)
                count=split(value, names, "\n")
                for (i=1; i<=count; i++) {
                    name=tolower(names[i]); sub(/^\\*\\./, "", name); sub(/\\.$/, "", name)
                    if (name == zone || name ~ ("\\." zone "$") ) print name
                }
            }
        ' "$ct_json" | /usr/bin/sort -u | /usr/bin/head -n 80 >"$ct_names"
        if [[ -s $ct_names ]]; then
            /bin/cat "$ct_names"
            printf '%s\n' 'Certificate names are historical clues and may no longer resolve.'
        else
            printf '%s\n' 'No certificate names were returned.'
        fi
    else
        printf '%s\n' 'The certificate-transparency service did not answer.'
    fi

    section 'Wildcard check'
    wildcard="netmin-discovery-${RANDOM}.$zone"
    if query_name "$wildcard" A AAAA CNAME; then
        printf '%s\n' 'A wildcard answer exists. Some apparent host discoveries may be synthesized.'
    else
        printf '%s\n' 'No A, AAAA, or CNAME wildcard answer was detected.'
    fi
fi

section 'Discovery status'
unique=$(/usr/bin/sort -u "$all_records" | /usr/bin/sed '/^[[:space:]]*$/d' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
names=$(/usr/bin/sort -u "$all_records" | /usr/bin/awk '$2 ~ /^[0-9]+$/ && $3 == "IN" { print $1 }' | /usr/bin/sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' ')
printf '%s\n' 'Completeness: Partial discovery'
printf 'Method: %s public DNS probes\n' "$mode"
printf 'Unique records: %s\n' "$unique"
printf 'Names with records: %s\n' "$names"
printf '%s\n' 'Why partial: DNS has no dependable public list operation. Custom names can remain undiscovered unless AXFR or provider access is available.'
