#!/bin/bash

set -u

section() {
    printf '\n%s\n' "$1"
}

quick=0
if [[ ${1-} == --quick ]]; then quick=1; shift; fi
target=${1-}
if [[ -z $target ]]; then
    target=$(/usr/bin/curl -fsSL --connect-timeout 4 --max-time 7 https://api.ipify.org) || {
        printf '%s\n' 'Could not determine the public IP address.' >&2
        exit 69
    }
fi

input_type='IP address'
address=$target
if [[ $target != *:* && ! $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    input_type='Hostname'
    address=$(/usr/bin/dig +short A "$target" | /usr/bin/head -n 1)
    [[ -n $address ]] || address=$(/usr/bin/dig +short AAAA "$target" | /usr/bin/head -n 1)
    if [[ -z $address ]]; then
        printf 'No IP address was found for %s.\n' "$target" >&2
        exit 68
    fi
fi

printf 'Network report for %s\n' "$target"
section 'Basic'
printf 'Input type: %s\n' "$input_type"
printf 'Resolved address: %s\n' "$address"
if [[ $address == *:* ]]; then printf 'IP version: IPv6\n'; else printf 'IP version: IPv4\n'; fi
reverse=$(/usr/bin/dig +short -x "$address" | /usr/bin/head -n 1)
printf 'Reverse name: %s\n' "${reverse:-Not found}"

section 'Address and ownership'
information=$(/usr/bin/curl -fsSL --connect-timeout 4 --max-time 8 "https://ipinfo.io/$address/json")
if [[ -n $information ]]; then
    /usr/bin/jq -r '
        [
          ["IP address", .ip], ["Hostname", .hostname], ["City", .city],
          ["Region", .region], ["Country", .country], ["Coordinates", .loc],
          ["Network", .org], ["Postal code", .postal], ["Time zone", .timezone],
          ["Anycast", .anycast]
        ][] | select(.[1] != null and .[1] != false and .[1] != "") | "\(.[0]): \(.[1])"
    ' <<<"$information"
else
    printf '%s\n' 'The address-information service did not return data.'
fi

if [[ $input_type == Hostname ]]; then
    section 'DNS'
    for record_type in A AAAA MX NS TXT; do
        answer=$(/usr/bin/dig +noall +answer "$record_type" "$target")
        if [[ -n $answer ]]; then printf '%s\n' "$answer"; else printf '%s: No records found\n' "$record_type"; fi
    done
fi

if (( quick )); then
    section 'Lookup complete'
    printf '%s\n' 'Quick lookup completed. Full diagnostics were skipped.'
    exit 0
fi

section 'Reachability'
/sbin/ping -n -c 3 -W 1000 "$address" 2>&1 || true

section 'Common TCP ports'
/bin/bash "$NETMIN_HELPERS/netmin-common-port-scan.sh" "$address"

section 'Route'
/bin/bash "$NETMIN_HELPERS/netmin-traceroute.sh" "$address" 15 2>&1 || true

section 'Lookup complete'
printf '%s\n' 'Network lookup completed.'
