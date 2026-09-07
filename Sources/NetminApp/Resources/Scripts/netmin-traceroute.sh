#!/bin/bash

# Hop discovery with ICMP echo probes. macOS ships traceroute as a setuid binary, which the App
# Sandbox refuses to execute, while ping runs unprivileged and can set the TTL of its probes.
# Routers that drop a probe answer with "Time to live exceeded"; the destination answers the probe
# itself, which is the only hop whose round-trip time ping reports.

set -u

target=${1-}
max_hops=${2:-15}
ping_command=${NETMIN_PING:-/sbin/ping}

if [[ -z $target ]]; then
    printf '%s\n' 'Enter an IP address or hostname.' >&2
    exit 64
fi
if [[ $target == *:* ]]; then
    printf '%s\n' 'Traceroute probes IPv4 destinations. Enter an IPv4 address or a hostname with an A record.' >&2
    exit 64
fi
if [[ ! $max_hops =~ ^[0-9]+$ ]] || (( max_hops < 1 || max_hops > 64 )); then
    max_hops=15
fi

address=$target
if [[ ! $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    address=$(/usr/bin/dig +short +time=2 +tries=1 A "$target" | /usr/bin/awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')
    if [[ -z $address ]]; then
        printf 'No IPv4 address was found for %s.\n' "$target" >&2
        exit 68
    fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/netmin-trace.XXXXXX") || exit 1
trap '/bin/rm -rf "$work"' EXIT

# One probe per TTL, all in flight at once. Each result line is: ttl, kind, responder, rtt.
probe() {
    local ttl=$1
    "$ping_command" -n -c 1 -m "$ttl" -W 2000 "$address" 2>&1 | /usr/bin/awk -v ttl="$ttl" '
        / bytes from / && /Time to live exceeded/ {
            sub(/:.*/, "", $4); print ttl "\texceeded\t" $4 "\t"; exit
        }
        / bytes from / && /time=/ {
            sub(/:.*/, "", $4)
            for (i = 1; i <= NF; i++) if ($i ~ /^time=/) rtt = substr($i, 6)
            print ttl "\treply\t" $4 "\t" rtt; exit
        }
    ' >"$work/$ttl"
}

for ((ttl = 1; ttl <= max_hops; ttl++)); do
    probe "$ttl" &
done
wait

# The first TTL answered by the destination itself ends the path.
last=$max_hops
reached=0
for ((ttl = 1; ttl <= max_hops; ttl++)); do
    [[ -s $work/$ttl ]] || continue
    IFS=$'\t' read -r _ kind _ _ <"$work/$ttl"
    if [[ $kind == reply ]]; then
        last=$ttl; reached=1; break
    fi
done

# Reverse names for every responding hop, looked up concurrently with a short timeout.
for ((ttl = 1; ttl <= last; ttl++)); do
    [[ -s $work/$ttl ]] || continue
    IFS=$'\t' read -r _ _ hop _ <"$work/$ttl"
    (
        name=$(/usr/bin/dig +short +time=1 +tries=1 -x "$hop" 2>/dev/null | /usr/bin/head -n 1)
        printf '%s\n' "${name%.}" >"$work/$ttl.name"
    ) &
done
wait

printf 'traceroute to %s (%s), %d hops max, ICMP echo probes\n' "$target" "$address" "$max_hops"
for ((ttl = 1; ttl <= last; ttl++)); do
    if [[ -s $work/$ttl ]]; then
        IFS=$'\t' read -r _ kind hop rtt <"$work/$ttl"
        name=$(/bin/cat "$work/$ttl.name" 2>/dev/null)
        [[ -n $name ]] || name=$hop
        if [[ $kind == reply ]]; then
            printf '%2d  %s (%s)  %s ms\n' "$ttl" "$name" "$hop" "$rtt"
        else
            printf '%2d  %s (%s)\n' "$ttl" "$name" "$hop"
        fi
    else
        printf '%2d  * * *\n' "$ttl"
    fi
done
if (( ! reached )); then
    printf '\nThe destination did not answer within %d hops.\n' "$max_hops"
fi
