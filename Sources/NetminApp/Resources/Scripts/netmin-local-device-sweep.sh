#!/bin/bash

set -u

ip_to_int() {
    local address=$1 a b c d
    IFS=. read -r a b c d <<<"$address"
    for part in "$a" "$b" "$c" "$d"; do
        [[ $part =~ ^[0-9]+$ ]] && (( part >= 0 && part <= 255 )) || return 1
    done
    printf '%u' "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
}

int_to_ip() {
    local value=$1
    printf '%d.%d.%d.%d' "$((value >> 24 & 255))" "$((value >> 16 & 255))" \
        "$((value >> 8 & 255))" "$((value & 255))"
}

mask_prefix() {
    local hex=${1#0x} value bits=0
    value=$((16#$hex))
    while (( value & 0x80000000 )); do bits=$((bits + 1)); value=$(((value << 1) & 0xFFFFFFFF)); done
    printf '%d' "$bits"
}

private_address() {
    local address=$1 a b
    IFS=. read -r a b _ <<<"$address"
    (( a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) ))
}

network_from_address() {
    local address=$1 prefix=$2 value mask
    value=$(ip_to_int "$address") || return 1
    if (( prefix == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF )); fi
    int_to_ip "$((value & mask))"
}

discover_networks() {
    local interface address mask prefix network key seen=''
    while read -r interface address mask; do
        private_address "$address" || continue
        prefix=$(mask_prefix "$mask")
        (( prefix < 31 )) || continue
        network=$(network_from_address "$address" "$prefix")
        key="$network/$prefix"
        [[ $seen == *"|$key|"* ]] && continue
        seen+="|$key|"
        printf '%s\t%s\t%s\n' "$interface" "$address" "$key"
    done < <(/sbin/ifconfig -a | /usr/bin/awk '
        /^[^[:space:]].*: flags=/ { interface=$1; sub(/:$/, "", interface) }
        /^[[:space:]]+inet / { print interface, $2, $4 }
    ')
}

port_name() {
    case $1 in
        22) printf 'SSH' ;; 80) printf 'HTTP' ;; 443) printf 'HTTPS' ;;
        445) printf 'SMB' ;; 631) printf 'IPP printer' ;; 7000) printf 'AirPlay' ;;
        8008) printf 'Chromecast HTTP' ;; 8009) printf 'Chromecast control' ;;
        9100) printf 'JetDirect printer' ;; *) printf 'TCP %s' "$1" ;;
    esac
}

probe_host() {
    local address=$1 interface=$2 latency='-' ping_output
    if ping_output=$(/sbin/ping -n -c 1 -W 200 "$address" 2>/dev/null); then
        latency=$(printf '%s\n' "$ping_output" | /usr/bin/sed -n 's/.*time=\([0-9.]*\) ms.*/\1 ms/p' | /usr/bin/head -n 1)
        latency=${latency:--}
        printf '%s\t%s\t\n' "$interface" "$latency" >"$RESULTS/$address"
    fi
}

probe_services() {
    local path=$1 address=${1##*/} interface latency _ port ports=''
    IFS=$'\t' read -r interface latency _ <"$path"
    for port in 22 80 443 445 631 7000 8008 8009 9100; do
        if /usr/bin/nc -n -z -G 1 "$address" "$port" >/dev/null 2>&1; then
            if [[ -n $ports ]]; then ports+=","; fi
            ports+="$port"
        fi
    done
    printf '%s\t%s\t%s\n' "$interface" "$latency" "$ports" >"$path"
}

scan_network() {
    local interface=$1 cidr=$2 base prefix start mask end value count=0 address
    base=${cidr%/*}; prefix=${cidr#*/}
    start=$(ip_to_int "$base")
    mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    start=$((start & mask)); end=$((start | (0xFFFFFFFF ^ mask)))
    for ((value=start + 1; value<end; value++)); do
        address=$(int_to_ip "$value")
        probe_host "$address" "$interface" &
        count=$((count + 1))
        (( count % 64 == 0 )) && wait
    done
    wait
}

browse_service() {
    local label=$1 type=$2 output process
    output=$(mktemp "${TMPDIR:-/tmp}/netmin-bonjour.XXXXXX") || return
    /usr/bin/dns-sd -B "$type" local. >"$output" 2>/dev/null & process=$!
    /bin/sleep 4
    /bin/kill "$process" >/dev/null 2>&1 || true
    wait "$process" 2>/dev/null || true
    /usr/bin/awk -v label="$label" -v type="$type." '
        / Add / && index($0, type) {
            line=$0; sub("^.*" type "[[:space:]]+", "", line)
            if (line != "" && !seen[line]++) printf "%-16s %s\n", label, line
        }
    ' "$output"
    /bin/rm -f "$output"
}

argument=${1-}
RESULTS=$(mktemp -d "${TMPDIR:-/tmp}/netmin-devices.XXXXXX") || exit 1
SERVICES=$(mktemp -d "${TMPDIR:-/tmp}/netmin-services.XXXXXX") || exit 1
trap '/bin/rm -rf "$RESULTS" "$SERVICES"' EXIT
export RESULTS

# Detected networks are always listed so explicit ranges can borrow their interface names.
detected=()
while IFS=$'\t' read -r interface local_address cidr; do
    [[ -n $interface ]] && detected+=("$interface|$local_address|$cidr")
done < <(discover_networks)

networks=()
if [[ -n $argument ]]; then
    # One CIDR, or several separated by commas, as selected in the app's sweep form.
    IFS=',' read -ra requested <<<"$argument"
    if (( ${#requested[@]} > 16 )); then
        printf '%s\n' 'A sweep can include at most 16 ranges.' >&2
        exit 64
    fi
    for candidate in "${requested[@]}"; do
        candidate=${candidate// /}
        [[ -n $candidate ]] || continue
        address=${candidate%/*}; prefix=${candidate#*/}
        if [[ $candidate != */* || ! $prefix =~ ^[0-9]+$ ]] || (( prefix < 0 || prefix > 30 )) || ! ip_to_int "$address" >/dev/null; then
            printf 'Enter a valid IPv4 CIDR, for example 192.168.1.0/24 (got %s).\n' "$candidate" >&2
            exit 64
        fi
        network=$(network_from_address "$address" "$prefix")
        interface=route; local_address=$address
        for entry in "${detected[@]}"; do
            IFS='|' read -r known_interface known_address known_cidr <<<"$entry"
            [[ $known_cidr == "$network/$prefix" ]] || continue
            interface=$known_interface; local_address=$known_address
        done
        networks+=("$interface|$local_address|$network/$prefix")
    done
else
    networks=("${detected[@]}")
fi

if (( ${#networks[@]} == 0 )); then
    printf '%s\n' 'No active private IPv4 network was found.' >&2
    exit 69
fi

printf '%s\n' 'Fast local discovery'
bounded=()
for entry in "${networks[@]}"; do
    IFS='|' read -r interface local_address cidr <<<"$entry"
    prefix=${cidr#*/}
    if (( prefix < 22 )); then
        network=$(network_from_address "$local_address" 24); cidr="$network/24"
        printf '  %s via %s (limited to the local /24 for speed)\n' "$cidr" "$interface"
    else
        printf '  %s via %s\n' "$cidr" "$interface"
    fi
    bounded+=("$interface|$local_address|$cidr")
    # Keep the process count bounded even when several ranges are selected.
    scan_network "$interface" "$cidr"
done
gateway=$(/sbin/route -n get default 2>/dev/null | /usr/bin/sed -n 's/^ *gateway: *//p' | /usr/bin/head -n 1)
[[ -n $gateway ]] && printf 'Default gateway: %s\n' "$gateway"
while read -r address mac interface; do
    [[ -n $address && -n $interface ]] || continue
    for entry in "${bounded[@]}"; do
        IFS='|' read -r wanted _ cidr <<<"$entry"
        [[ $wanted == "$interface" || $wanted == route ]] || continue
        start=$(ip_to_int "${cidr%/*}"); prefix=${cidr#*/}; mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
        value=$(ip_to_int "$address") || continue
        if (( (value & mask) == (start & mask) )); then
            [[ -f $RESULTS/$address ]] || printf '%s\t-\t\n' "$interface" >"$RESULTS/$address"
        fi
    done
done < <(/usr/sbin/arp -an | /usr/bin/awk '/ at / && $4 != "(incomplete)" { gsub(/[()]/, "", $2); print $2, $4, $6 }')

service_jobs=0
for path in "$RESULTS"/*; do
    [[ -f $path ]] || continue
    probe_services "$path" &
    service_jobs=$((service_jobs + 1))
    (( service_jobs % 64 == 0 )) && wait
done
wait

printf '\nMethod: macOS ping, TCP, neighbor cache and Bonjour\n'
count=$(/usr/bin/find "$RESULTS" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')
printf 'Devices (%s found)\n' "$count"
printf '%-16s %-28s %-10s %-12s %-18s %s\n' 'IP address' 'Name' 'Latency' 'Interface' 'MAC address' 'Vendor note'
printf '%s\n' '-------------------------------------------------------------------------------------------------------'
for path in $(/usr/bin/find "$RESULTS" -type f | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n -k4,4n); do
    address=${path##*/}
    IFS=$'\t' read -r interface latency ports <"$path"
    name=$(/usr/bin/dscacheutil -q host -a ip_address "$address" 2>/dev/null | /usr/bin/sed -n 's/^name: //p' | /usr/bin/head -n 1)
    for entry in "${bounded[@]}"; do
        IFS='|' read -r _ local_address _ <<<"$entry"
        [[ $address == "$local_address" ]] && name='This Mac'
    done
    mac=$(/usr/sbin/arp -an "$address" 2>/dev/null | /usr/bin/awk '/ at / { print $4; exit }')
    vendor='-'
    if [[ $mac =~ ^[0-9a-fA-F][0-9a-fA-F]: ]]; then
        first=${mac%%:*}; (( (16#$first) & 2 )) && vendor='Private/randomized MAC'
    fi
    printf '%-16s %-28.28s %-10s %-12s %-18s %s\n' "$address" "${name:--}" "${latency:--}" "$interface" "${mac:--}" "$vendor"
done

printf '\nCommon TCP services\n'
services_found=0
for path in $(/usr/bin/find "$RESULTS" -type f | /usr/bin/sort); do
    address=${path##*/}; IFS=$'\t' read -r _ _ ports <"$path"
    [[ -n ${ports-} ]] || continue
    labels=''
    IFS=, read -ra open_ports <<<"$ports"
    for port in "${open_ports[@]}"; do
        [[ -n $labels ]] && labels+=', '
        labels+="$(port_name "$port") ($port)"
    done
    printf '%-16s %s\n' "$address" "$labels"; services_found=$((services_found + 1))
done
(( services_found )) || printf '%s\n' 'No common TCP services accepted a connection.'

browse_service 'Printer' _ipp._tcp >"$SERVICES/ipp" &
browse_service 'Secure printer' _ipps._tcp >"$SERVICES/ipps" &
browse_service 'Scanner' _scanner._tcp >"$SERVICES/scanner" &
browse_service 'AirPlay' _airplay._tcp >"$SERVICES/airplay" &
browse_service 'AirPlay audio' _raop._tcp >"$SERVICES/raop" &
browse_service 'Chromecast' _googlecast._tcp >"$SERVICES/cast" &
browse_service 'File sharing' _smb._tcp >"$SERVICES/smb" &
browse_service 'SSH' _ssh._tcp >"$SERVICES/ssh" &
browse_service 'HomeKit' _hap._tcp >"$SERVICES/homekit" &
browse_service 'Web service' _http._tcp >"$SERVICES/http" &
wait

printf '\nBonjour services\n'
if /usr/bin/grep -q . "$SERVICES"/* 2>/dev/null; then
    /bin/cat "$SERVICES"/* | /usr/bin/sort -u
else
    printf '%s\n' 'No common services were advertised during the discovery window.'
fi
