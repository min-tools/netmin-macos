#!/bin/bash

set -u

section() {
    printf '\n%s\n' "$1"
}

normalize_host() {
    local value=$1
    value=${value#*://}
    value=${value%%/*}
    value=${value%%:*}
    printf '%s' "$value"
}

tcp_check() {
    local host=$1 port=$2 started=$SECONDS
    if /usr/bin/nc -z -G 3 "$host" "$port" >/dev/null 2>&1; then
        printf 'open (%d s)\n' "$((SECONDS - started))"
    else
        printf '%s\n' 'closed, filtered, or timed out'
    fi
}

tls_capture() {
    local output process status=0 wait_status tick
    output=$(mktemp "${TMPDIR:-/tmp}/netmin-tls.XXXXXX") || return 1
    /usr/bin/openssl "$@" </dev/null >"$output" 2>&1 &
    process=$!
    for ((tick=0; tick<100; tick++)); do
        /bin/kill -0 "$process" >/dev/null 2>&1 || break
        /bin/sleep 0.1
    done
    if /bin/kill -0 "$process" >/dev/null 2>&1; then
        /bin/kill "$process" >/dev/null 2>&1 || true
        status=124
    fi
    wait "$process" 2>/dev/null; wait_status=$?
    (( status == 124 )) || status=$wait_status
    TLS_OUTPUT=$(/bin/cat "$output")
    /bin/rm -f "$output"
    return "$status"
}

tls_summary() {
    local host=$1 port=$2 starttls=${3-} version=${4-} arguments summary
    arguments=(s_client -connect "$host:$port" -servername "$host")
    [[ -n $starttls ]] && arguments+=(-starttls "$starttls")
    [[ -n $version ]] && arguments+=("$version")
    tls_capture "${arguments[@]}" || true
    summary=$(printf '%s\n' "$TLS_OUTPUT" | /usr/bin/awk '
        /Server Temp Key:/ || /Protocol  *:/ || /Cipher  *:/ || /Verify return code:/ { sub(/^[[:space:]]+/, ""); print }
    ')
    if [[ -n $summary ]]; then printf '%s\n' "$summary"; else printf '%s\n' "${TLS_OUTPUT##*$'\n'}"; fi
}

certificate_report() {
    local host=$1 pem details text sans verify ocsp
    tls_capture s_client -connect "$host:443" -servername "$host" -showcerts -status || true
    pem=$(mktemp "${TMPDIR:-/tmp}/netmin-cert.XXXXXX") || return 1
    printf '%s\n' "$TLS_OUTPUT" | /usr/bin/awk '
        /-----BEGIN CERTIFICATE-----/ { capture=1 }
        capture { print }
        /-----END CERTIFICATE-----/ { exit }
    ' >"$pem"
    if ! /usr/bin/grep -q 'BEGIN CERTIFICATE' "$pem"; then
        printf '%s\n' 'No certificate was returned.'
        /bin/rm -f "$pem"
        return
    fi
    details=$(/usr/bin/openssl x509 -in "$pem" -noout -subject -issuer -serial -dates -fingerprint -sha256 2>&1)
    text=$(/usr/bin/openssl x509 -in "$pem" -noout -text 2>/dev/null)
    sans=$(printf '%s\n' "$text" | /usr/bin/awk '
        /X509v3 Subject Alternative Name:/ { getline; sub(/^[[:space:]]+/, ""); print; exit }
    ')
    verify=$(printf '%s\n' "$TLS_OUTPUT" | /usr/bin/sed -n 's/^[[:space:]]*Verify return code: /Verification: /p' | /usr/bin/tail -n 1)
    ocsp=$(printf '%s\n' "$TLS_OUTPUT" | /usr/bin/sed -n 's/^[[:space:]]*Cert Status: /OCSP stapling: /p' | /usr/bin/head -n 1)
    printf '%s\n' "$details"
    [[ -n $sans ]] && printf 'Subject Alternative Names: %s\n' "$sans"
    printf '%s\n' "${verify:-Verification: Not reported}"
    printf '%s\n' "${ocsp:-OCSP stapling: No response reported}"
    /bin/rm -f "$pem"
}

http_headers() {
    local host=$1 output
    output=$(/usr/bin/curl -sSIL --connect-timeout 4 --max-time 10 "https://$host" 2>&1)
    printf '%s\n' "${output:-No HTTPS headers were returned.}"
}

mail_service() {
    local label=$1 host=$2 port=$3 starttls=${4-}
    printf '%-20s %s:%s\n' "$label" "$host" "$port"
    printf '  TCP: %s\n' "$(tcp_check "$host" "$port")"
    printf '%s\n' '  TLS:'
    while IFS= read -r line; do printf '    %s\n' "$line"; done < <(tls_summary "$host" "$port" "$starttls")
}

mail_report() {
    local domain=$1 mx mail_host task_dir
    mx=$(/usr/bin/dig +short MX "$domain" | /usr/bin/sort -n | /usr/bin/awk 'NR == 1 { sub(/\.$/, "", $2); print $2 }')
    mail_host=${mx:-$domain}
    printf 'Mail TLS report for %s\n' "$domain"
    section 'Discovered endpoints'
    printf 'Primary mail server: %s\n' "$mail_host"
    task_dir=$(mktemp -d "${TMPDIR:-/tmp}/netmin-mail.XXXXXX") || exit 1
    mail_service 'SMTP STARTTLS' "$mail_host" 25 smtp >"$task_dir/25" &
    mail_service 'SMTPS' "$mail_host" 465 >"$task_dir/465" &
    mail_service 'Submission STARTTLS' "$mail_host" 587 smtp >"$task_dir/587" &
    mail_service 'IMAPS' "$mail_host" 993 >"$task_dir/993" &
    mail_service 'POP3S' "$mail_host" 995 >"$task_dir/995" &
    wait
    section 'Port and TLS checks'
    for port in 25 465 587 993 995; do /bin/cat "$task_dir/$port"; done
    /bin/rm -rf "$task_dir"
}

site_report() {
    local host=$1 primary_mx task_dir
    printf 'Site report for %s\n' "$host"
    task_dir=$(mktemp -d "${TMPDIR:-/tmp}/netmin-site.XXXXXX") || exit 1

    tcp_check "$host" 22 >"$task_dir/tcp22" &
    tcp_check "$host" 80 >"$task_dir/tcp80" &
    tcp_check "$host" 443 >"$task_dir/tcp443" &
    http_headers "$host" >"$task_dir/headers" &
    certificate_report "$host" >"$task_dir/certificate" &
    tls_summary "$host" 443 >"$task_dir/tls-default" &
    tls_summary "$host" 443 '' -tls1_2 >"$task_dir/tls12" &
    tls_summary "$host" 443 '' -tls1_3 >"$task_dir/tls13" &

    # Find the enclosing zone so reports for hosts such as www.example.com still inspect the
    # domain's authority and mail policies rather than querying those records at the host label.
    local zone=$host soa nameservers record_type answer policy_name policy_label
    while [[ $zone == *.* ]]; do
        soa=$(/usr/bin/dig +time=3 +tries=1 +short "$zone" SOA 2>/dev/null | /usr/bin/head -n 1)
        [[ -n $soa ]] && break
        zone=${zone#*.}
    done
    [[ -n ${soa-} ]] || zone=$host

    section 'DNS host records'
    for record_type in A AAAA CNAME TYPE65; do
        answer=$(/usr/bin/dig +time=3 +tries=1 +noall +answer "$host" "$record_type" 2>/dev/null)
        if [[ -n $answer ]]; then printf '%s\n' "$answer"; else printf '%s: No records found\n' "$record_type"; fi
    done
    answer=$(/usr/bin/dig +time=3 +tries=1 +noall +answer "_443._tcp.$host" TLSA 2>/dev/null)
    printf '%s\n' "${answer:-TLSA: No records found}"

    section 'DNS zone and mail records'
    printf 'Zone apex: %s\n' "$zone"
    for record_type in SOA NS MX TXT CAA DS DNSKEY; do
        answer=$(/usr/bin/dig +time=3 +tries=1 +noall +answer "$zone" "$record_type" 2>/dev/null)
        if [[ -n $answer ]]; then printf '%s\n' "$answer"; else printf '%s: No records found\n' "$record_type"; fi
    done

    section 'Mail policy records'
    while IFS='|' read -r policy_label policy_name; do
        answer=$(/usr/bin/dig +time=3 +tries=1 +noall +answer "$policy_name.$zone" TXT 2>/dev/null)
        if [[ -n $answer ]]; then printf '%s\n' "$answer"; else printf '%s: No record found\n' "$policy_label"; fi
    done <<'POLICIES'
DMARC|_dmarc
MTA-STS|_mta-sts
TLS-RPT|_smtp._tls
BIMI|default._bimi
POLICIES

    section 'Authoritative SOA answers'
    nameservers=$(/usr/bin/dig +time=3 +tries=1 +short "$zone" NS 2>/dev/null | /usr/bin/sed 's/\.$//' | /usr/bin/sort -u)
    if [[ -n $nameservers ]]; then
        while IFS= read -r server; do
            [[ -n $server ]] || continue
            answer=$(/usr/bin/dig "@$server" +time=3 +tries=1 +short "$zone" SOA 2>/dev/null)
            printf '%s: %s\n' "$server" "${answer:-No answer}"
        done <<<"$nameservers"
    else
        printf '%s\n' 'No authoritative name servers were returned.'
    fi

    primary_mx=$(/usr/bin/dig +time=3 +tries=1 +short "$zone" MX 2>/dev/null | /usr/bin/sort -n | /usr/bin/awk 'NR == 1 { sub(/\.$/, "", $2); print $2 }')
    if [[ -n $primary_mx ]]; then mail_service 'SMTP STARTTLS' "$primary_mx" 25 smtp >"$task_dir/mx" & fi
    wait

    section 'TCP reachability'
    printf 'SSH      %s:22    %s\n' "$host" "$(/bin/cat "$task_dir/tcp22")"
    printf 'HTTP     %s:80    %s\n' "$host" "$(/bin/cat "$task_dir/tcp80")"
    printf 'HTTPS    %s:443   %s\n' "$host" "$(/bin/cat "$task_dir/tcp443")"
    section 'HTTPS headers'; /bin/cat "$task_dir/headers"
    section 'TLS certificate and chain'; /bin/cat "$task_dir/certificate"
    section 'TLS handshakes'
    printf '%s\n' 'Default'; /usr/bin/sed 's/^/  /' "$task_dir/tls-default"
    printf '%s\n' 'TLS 1.2'; /usr/bin/sed 's/^/  /' "$task_dir/tls12"
    printf '%s\n' 'TLS 1.3'; /usr/bin/sed 's/^/  /' "$task_dir/tls13"
    section 'Primary MX STARTTLS'
    if [[ -n $primary_mx ]]; then
        /bin/cat "$task_dir/mx"
        printf '%s\n' 'For ports 465, 587, 993, and 995, use Mail TLS Report.'
    else
        printf '%s\n' 'No MX record was found.'
    fi
    /bin/rm -rf "$task_dir"
}

if [[ ${1-} == --mail ]]; then
    [[ -n ${2-} ]] || { printf '%s\n' 'Enter a mail domain or server.' >&2; exit 64; }
    mail_report "$(normalize_host "$2")"
else
    [[ -n ${1-} ]] || { printf '%s\n' 'Enter a domain or hostname.' >&2; exit 64; }
    site_report "$(normalize_host "$1")"
fi
