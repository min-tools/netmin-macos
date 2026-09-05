#!/bin/bash

set -u
host=${1-}
if [[ -z $host ]]; then
    printf '%s\n' 'Enter an IP address or hostname.' >&2
    exit 64
fi

ports=(21 22 25 53 80 110 135 139 143 443 445 465 587 631 993 995 1433 3306 3389 5432 5900 6379 8000 8080 8443)
found_dir=$(mktemp -d "${TMPDIR:-/tmp}/netmin-ports.XXXXXX") || exit 1
trap '/bin/rm -rf "$found_dir"' EXIT

service_name() {
    case $1 in
        21) printf 'FTP' ;; 22) printf 'SSH' ;; 25) printf 'SMTP' ;; 53) printf 'DNS' ;;
        80) printf 'HTTP' ;; 110) printf 'POP3' ;; 135) printf 'MS RPC' ;; 139) printf 'NetBIOS' ;;
        143) printf 'IMAP' ;; 443) printf 'HTTPS' ;; 445) printf 'SMB' ;; 465) printf 'SMTPS' ;;
        587) printf 'Mail submission' ;; 631) printf 'IPP' ;; 993) printf 'IMAPS' ;; 995) printf 'POP3S' ;;
        1433) printf 'MS SQL' ;; 3306) printf 'MySQL' ;; 3389) printf 'Remote Desktop' ;;
        5432) printf 'PostgreSQL' ;; 5900) printf 'Screen Sharing' ;; 6379) printf 'Redis' ;;
        8000) printf 'HTTP alternate' ;; 8080) printf 'HTTP proxy' ;; 8443) printf 'HTTPS alternate' ;;
        *) printf 'Unknown' ;;
    esac
}

printf 'Common TCP ports on %s\n\n' "$host"
for port in "${ports[@]}"; do
    (
        if /usr/bin/nc -z -G 1 "$host" "$port" >/dev/null 2>&1; then
            printf '%s\topen\t%s\n' "$port" "$(service_name "$port")" >"$found_dir/$port"
        fi
    ) &
done
wait

found=0
for port in "${ports[@]}"; do
    if [[ -f $found_dir/$port ]]; then
        /bin/cat "$found_dir/$port"
        found=$((found + 1))
    fi
done
if (( found == 0 )); then
    printf '%s\n' 'No common TCP ports accepted a connection.'
fi
printf '\nOpen ports: %d\n' "$found"
