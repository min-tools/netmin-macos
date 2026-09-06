#!/bin/bash

value=${1-}
compact=$(printf '%s' "$value" | /usr/bin/tr -cd '0-9A-Fa-f')
if [[ ${#compact} -ne 12 ]]; then
    printf '%s\n' 'Expected a MAC address containing exactly 12 hexadecimal digits.' >&2
    exit 64
fi

printf '%s:%s:%s:%s:%s:%s\n' \
    "${compact:0:2}" "${compact:2:2}" "${compact:4:2}" \
    "${compact:6:2}" "${compact:8:2}" "${compact:10:2}" | /usr/bin/tr '[:lower:]' '[:upper:]'
