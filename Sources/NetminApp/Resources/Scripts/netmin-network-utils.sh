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
    printf '%d.%d.%d.%d' \
        "$(( (value >> 24) & 255 ))" "$(( (value >> 16) & 255 ))" \
        "$(( (value >> 8) & 255 ))" "$(( value & 255 ))"
}

parse_cidr() {
    local value=$1 address prefix address_int mask
    address=${value%/*}
    prefix=${value#*/}
    if [[ $value != */* || ! $prefix =~ ^[0-9]+$ ]] || (( prefix < 0 || prefix > 32 )); then
        printf '%s\n' 'Expected an IPv4 address followed by a prefix from /0 to /32.' >&2
        return 1
    fi
    address_int=$(ip_to_int "$address") || {
        printf '%s\n' 'The IPv4 address is invalid.' >&2
        return 1
    }
    if (( prefix == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF )); fi
    CIDR_PREFIX=$prefix
    CIDR_MASK=$mask
    CIDR_NETWORK=$(( address_int & mask ))
    CIDR_BROADCAST=$(( CIDR_NETWORK | (0xFFFFFFFF ^ mask) ))
}

cidr() {
    parse_cidr "$1" || exit 64
    local first=$CIDR_NETWORK last=$CIDR_BROADCAST count=$((1 << (32 - CIDR_PREFIX)))
    if (( count > 2 )); then first=$((first + 1)); last=$((last - 1)); fi
    printf 'Network: %s\n' "$(int_to_ip "$CIDR_NETWORK")"
    printf 'Netmask: %s\n' "$(int_to_ip "$CIDR_MASK")"
    printf 'Broadcast: %s\n' "$(int_to_ip "$CIDR_BROADCAST")"
    printf 'First: %s\n' "$(int_to_ip "$first")"
    printf 'Last: %s\n' "$(int_to_ip "$last")"
    printf 'Addresses: %d\n' "$count"
}

expand() {
    parse_cidr "$1" || exit 64
    local count=$((1 << (32 - CIDR_PREFIX))) value
    if (( count > 4096 )); then
        printf '%s\n' 'Range is larger than 4096 addresses.' >&2
        exit 64
    fi
    for ((value=CIDR_NETWORK; value<=CIDR_BROADCAST; value++)); do int_to_ip "$value"; printf '\n'; done
}

adapt_bias() {
    local delta=$1 points=$2 first=$3 k=0
    if (( first )); then delta=$((delta / 700)); else delta=$((delta / 2)); fi
    delta=$((delta + delta / points))
    while (( delta > 455 )); do delta=$((delta / 35)); k=$((k + 36)); done
    ADAPTED_BIAS=$((k + (36 * delta) / (delta + 38)))
}

digit_value() {
    case $1 in
        [a-z]) printf '%d' "$(( $(printf '%d' "'$1") - 97 ))" ;;
        [A-Z]) printf '%d' "$(( $(printf '%d' "'$1") - 65 ))" ;;
        [0-9]) printf '%d' "$(( $(printf '%d' "'$1") - 22 ))" ;;
        *) return 1 ;;
    esac
}

encode_digit() {
    local value=$1 escaped
    if (( value < 26 )); then
        printf -v escaped '\\%03o' "$((97 + value))"
        printf '%b' "$escaped"
    else
        printf '%d' "$((value - 26))"
    fi
}

codepoint() {
    local hex b1 b2 b3 b4
    hex=$(printf '%s' "$1" | /usr/bin/xxd -p)
    case ${#hex} in
        2) printf '%d' "$((16#$hex))" ;;
        4)
            b1=$((16#${hex:0:2})); b2=$((16#${hex:2:2}))
            printf '%d' "$(( (b1 & 0x1F) << 6 | (b2 & 0x3F) ))"
            ;;
        6)
            b1=$((16#${hex:0:2})); b2=$((16#${hex:2:2})); b3=$((16#${hex:4:2}))
            printf '%d' "$(( (b1 & 0x0F) << 12 | (b2 & 0x3F) << 6 | (b3 & 0x3F) ))"
            ;;
        8)
            b1=$((16#${hex:0:2})); b2=$((16#${hex:2:2})); b3=$((16#${hex:4:2})); b4=$((16#${hex:6:2}))
            printf '%d' "$(( (b1 & 0x07) << 18 | (b2 & 0x3F) << 12 | (b3 & 0x3F) << 6 | (b4 & 0x3F) ))"
            ;;
        *) return 1 ;;
    esac
}

utf8_character() {
    local cp=$1 escaped
    if (( cp <= 0x7F )); then
        escaped=$(printf '\\%03o' "$cp")
    elif (( cp <= 0x7FF )); then
        escaped=$(printf '\\%03o\\%03o' "$((0xC0 | cp >> 6))" "$((0x80 | cp & 0x3F))")
    elif (( cp <= 0xFFFF )); then
        escaped=$(printf '\\%03o\\%03o\\%03o' "$((0xE0 | cp >> 12))" "$((0x80 | cp >> 6 & 0x3F))" "$((0x80 | cp & 0x3F))")
    else
        escaped=$(printf '\\%03o\\%03o\\%03o\\%03o' "$((0xF0 | cp >> 18))" "$((0x80 | cp >> 12 & 0x3F))" "$((0x80 | cp >> 6 & 0x3F))" "$((0x80 | cp & 0x3F))")
    fi
    printf '%b' "$escaped"
}

punycode_encode_label() {
    local label=$1 output='' length basic=0 handled n=128 delta=0 bias=72 pos cp minimum q k t
    length=${#label}
    for ((pos=0; pos<length; pos++)); do
        cp=$(codepoint "${label:pos:1}")
        if (( cp < 128 )); then output+="${label:pos:1}"; basic=$((basic + 1)); fi
    done
    handled=$basic
    (( basic > 0 && handled < length )) && output+='-'
    while (( handled < length )); do
        minimum=2147483647
        for ((pos=0; pos<length; pos++)); do
            cp=$(codepoint "${label:pos:1}")
            (( cp >= n && cp < minimum )) && minimum=$cp
        done
        delta=$((delta + (minimum - n) * (handled + 1))); n=$minimum
        for ((pos=0; pos<length; pos++)); do
            cp=$(codepoint "${label:pos:1}")
            if (( cp < n )); then delta=$((delta + 1)); fi
            if (( cp == n )); then
                q=$delta; k=36
                while :; do
                    if (( k <= bias )); then t=1; elif (( k >= bias + 26 )); then t=26; else t=$((k - bias)); fi
                    (( q < t )) && break
                    output+=$(encode_digit "$((t + (q - t) % (36 - t)))")
                    q=$(((q - t) / (36 - t))); k=$((k + 36))
                done
                output+=$(encode_digit "$q")
                adapt_bias "$delta" "$((handled + 1))" "$((handled == basic))"; bias=$ADAPTED_BIAS
                delta=0; handled=$((handled + 1))
            fi
        done
        delta=$((delta + 1)); n=$((n + 1))
    done
    printf 'xn--%s' "$output"
}

punycode_decode_label() {
    local encoded=${1#xn--} basic='' tail n=128 i=0 bias=72 old_i w k digit t out_length index cp
    tail=$encoded
    [[ $encoded == *-* ]] && { basic=${encoded%-*}; tail=${encoded##*-}; }
    local points=()
    for ((index=0; index<${#basic}; index++)); do points+=("$(codepoint "${basic:index:1}")"); done
    while [[ -n $tail ]]; do
        old_i=$i; w=1; k=36
        while :; do
            [[ -n $tail ]] || return 1
            digit=$(digit_value "${tail:0:1}") || return 1; tail=${tail:1}
            i=$((i + digit * w))
            if (( k <= bias )); then t=1; elif (( k >= bias + 26 )); then t=26; else t=$((k - bias)); fi
            (( digit < t )) && break
            w=$((w * (36 - t))); k=$((k + 36))
        done
        out_length=$((${#points[@]} + 1))
        adapt_bias "$((i - old_i))" "$out_length" "$((old_i == 0))"; bias=$ADAPTED_BIAS
        n=$((n + i / out_length)); i=$((i % out_length))
        points=("${points[@]:0:i}" "$n" "${points[@]:i}")
        i=$((i + 1))
    done
    for cp in "${points[@]}"; do utf8_character "$cp"; done
}

punycode() {
    local input=$1 label converted ascii=() unicode=()
    IFS=. read -ra labels <<<"$input"
    for label in "${labels[@]}"; do
        if [[ $label == xn--* ]]; then
            converted=$(punycode_decode_label "$label") || { printf '%s\n' 'Invalid Punycode label.' >&2; exit 64; }
            ascii+=("$label"); unicode+=("$converted")
        elif LC_ALL=C /usr/bin/grep -q '[^ -~]' <<<"$label"; then
            converted=$(punycode_encode_label "$label")
            ascii+=("$converted"); unicode+=("$label")
        else
            ascii+=("$label"); unicode+=("$label")
        fi
    done
    local IFS=.
    printf 'ASCII: %s\n' "${ascii[*]}"
    printf 'Unicode: %s\n' "${unicode[*]}"
}

case ${1-} in
    cidr) [[ $# -eq 2 ]] || exit 64; cidr "$2" ;;
    expand) [[ $# -eq 2 ]] || exit 64; expand "$2" ;;
    punycode) [[ $# -eq 2 ]] || exit 64; punycode "$2" ;;
    *) printf '%s\n' 'Usage: netmin-network-utils.sh cidr|expand|punycode VALUE' >&2; exit 64 ;;
esac
