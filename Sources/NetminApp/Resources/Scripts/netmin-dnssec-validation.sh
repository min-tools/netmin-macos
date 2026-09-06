#!/bin/bash

set -u

name=${1-}
record_type=${2:-A}
resolver=${3:-1.1.1.1}
dig_command=${NETMIN_DIG:-/usr/bin/dig}

if [[ -z $name ]]; then
    printf '%s\n' 'Enter a DNS name to validate.' >&2
    exit 64
fi
case $record_type in
    A|TLSA) ;;
    *) printf '%s\n' 'DNSSEC validation supports A and TLSA records.' >&2; exit 64 ;;
esac

answer=$("$dig_command" "@$resolver" +time=4 +tries=2 +dnssec +comments +answer "$name" "$record_type" 2>&1)
status=$?
if (( status != 0 )); then
    printf '%s\n' "$answer" >&2
    exit "$status"
fi

printf 'Validating resolver: %s\n' "$resolver"
if /usr/bin/grep -Eq '^;; flags: .* ad[ ;]' <<<"$answer"; then
    printf '%s\n' 'Validation: Secure (authenticated data)'
else
    printf '%s\n' 'Validation: Not authenticated'
fi
printf '\n%s\n' "$answer"
