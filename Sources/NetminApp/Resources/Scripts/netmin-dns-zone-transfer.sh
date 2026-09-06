#!/bin/bash

set -u

zone=${1%.}
dig_command=${NETMIN_DIG:-/usr/bin/dig}
if [[ -z $zone ]] || [[ $zone != *.* ]] || [[ $zone == .* ]] || [[ $zone == *..* ]] ||
   [[ $zone =~ [^A-Za-z0-9_.-] ]]; then
    printf '%s\n' 'Enter a valid DNS zone without a scheme, path, port, or spaces.' >&2
    exit 64
fi

nameservers=$(
    "$dig_command" +time=3 +tries=1 +short "$zone" NS 2>/dev/null |
        /usr/bin/sed 's/\.$//' | /usr/bin/sort -u
)
if [[ -z $nameservers ]]; then
    printf 'No authoritative name servers were found for %s.\n' "$zone"
    exit 0
fi

printf 'DNS zone transfer for %s\n' "$zone"
while IFS= read -r server; do
    [[ -n $server ]] || continue
    printf '\nAuthoritative server: %s\n' "$server"
    transfer=$("$dig_command" +time=5 +tries=1 "@$server" "$zone" AXFR 2>&1)
    status=$?
    if (( status == 0 )) && /usr/bin/grep -Eq '[[:space:]]IN[[:space:]]+SOA[[:space:]]' <<<"$transfer" &&
       ! /usr/bin/grep -Eqi 'transfer failed|refused|timed out|communications error' <<<"$transfer"; then
        printf '%s\n' 'Transfer: Allowed'
        printf '%s\n' "$transfer"
        exit 0
    fi
    reason=$(/usr/bin/grep -Ei 'transfer failed|refused|timed out|communications error' <<<"$transfer" | /usr/bin/head -n 1)
    printf 'Transfer: Not available%s\n' "${reason:+ · $reason}"
done <<<"$nameservers"

printf '\n%s\n' 'No authoritative server allowed a complete zone transfer.'
