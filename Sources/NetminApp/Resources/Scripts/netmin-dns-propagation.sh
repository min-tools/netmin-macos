#!/bin/bash

set -u

target=${1%.}
mode=${2-}
dig_command=${NETMIN_DIG:-/usr/bin/dig}
if [[ -z $target ]]; then
    printf '%s\n' 'Enter a hostname, DNS service name, or IP address.' >&2
    exit 64
fi
if [[ -n $mode && $mode != --all ]]; then
    printf '%s\n' 'The only supported option is --all.' >&2
    exit 64
fi

if [[ $target == *:* ]] || [[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    record_types=(PTR)
elif [[ $target == _* ]]; then
    record_types=(SRV)
    [[ $mode == --all ]] && record_types=(SRV TLSA TXT CNAME)
else
    record_types=(A)
    [[ $mode == --all ]] && record_types=(A AAAA CNAME MX NS SOA TXT CAA DS DNSKEY)
fi

work=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/netmin-propagation.XXXXXX") || exit 1
trap '/bin/rm -rf "$work"' EXIT
providers=(
    'Cloudflare|1.1.1.1'
    'Google|8.8.8.8'
    'Quad9|9.9.9.9'
    'OpenDNS|208.67.222.222'
)

query_resolver() {
    local provider=$1 resolver=$2 type answer owner ttl class actual_type record_data records=''
    printf 'Resolver %s (%s)\n' "$provider" "$resolver"
    for type in "${record_types[@]}"; do
        if [[ $type == PTR ]]; then
            answer=$("$dig_command" "@$resolver" +time=2 +tries=1 +noall +answer -x "$target" 2>/dev/null)
        else
            answer=$("$dig_command" "@$resolver" +time=2 +tries=1 +noall +answer "$target" "$type" 2>/dev/null)
        fi
        while read -r owner ttl class actual_type record_data; do
            [[ $class == IN && -n $record_data ]] || continue
            records+="$actual_type $record_data"$'\n'
        done <<<"$answer"
    done
    [[ -z $records ]] || printf '%s' "$records" | /usr/bin/sort -u
    printf '\n'
}

pids=()
for index in "${!providers[@]}"; do
    IFS='|' read -r provider resolver <<<"${providers[$index]}"
    query_resolver "$provider" "$resolver" >"$work/$index" &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || true; done
for index in "${!providers[@]}"; do /bin/cat "$work/$index"; done
