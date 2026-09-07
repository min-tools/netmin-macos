#!/bin/bash

target=${1-}
if [[ -z $target ]]; then
    printf '%s\n' 'Enter an IP address or hostname.' >&2
    exit 64
fi
if [[ $target == */* ]]; then
    printf '%s\n' 'Windows Name Discovery accepts one host. Use Local Device Sweep to discover an entire subnet.' >&2
    exit 64
fi

printf 'Windows/SMB name query for %s\n\n' "$target"
exec /usr/bin/smbutil status -ae "$target"
