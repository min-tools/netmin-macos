#!/bin/bash

set -u

document=${1:-}
requested_host=${2:-}

case $document in
    security)
        display_name='security.txt'
        paths=('/.well-known/security.txt' '/security.txt')
        ;;
    robots)
        display_name='robots.txt'
        paths=('/robots.txt')
        ;;
    *)
        printf '%s\n' 'Expected security or robots as the document type.' >&2
        exit 64
        ;;
esac

if [[ -z $requested_host ]]; then
    printf 'A hostname is required to fetch %s.\n' "$display_name" >&2
    exit 64
fi

temporary_root=${TMPDIR:-/tmp}
work_directory=$(/usr/bin/mktemp -d "${temporary_root%/}/netmin-document.XXXXXX") || exit 1
body_file="$work_directory/body"
error_file="$work_directory/error"
first_failure=''

# The EXIT trap invokes this function indirectly.
# shellcheck disable=SC2329
cleanup() {
    /bin/rm -rf "$work_directory"
}
trap cleanup EXIT HUP INT TERM

remember_failure() {
    [[ -n $first_failure ]] || first_failure=$1
}

# Fetch one candidate and accept it only when the response is the requested text document.
fetch_candidate() {
    local url=$1 status preview
    : >"$body_file"
    : >"$error_file"

    /usr/bin/curl -fsSL --max-time 20 --max-redirs 20 \
        --output "$body_file" "$url" 2>"$error_file"
    status=$?
    if (( status != 0 )); then
        if (( status == 47 )); then
            remember_failure "The app followed the redirects, but the website sent $display_name back to the same URL repeatedly. No file was returned."
        else
            remember_failure "$(/usr/bin/tail -n 3 "$error_file")"
        fi
        return 1
    fi

    if [[ ! -s $body_file ]]; then
        remember_failure "The website returned an empty $display_name file."
        return 1
    fi

    # A number of sites turn missing files into a successful HTML not-found or home page.
    preview=$(/usr/bin/head -c 1024 "$body_file")
    if LC_ALL=C /usr/bin/printf '%s' "$preview" | /usr/bin/grep -Eiq '<(!doctype[[:space:]]+html|html|head|body)([[:space:]>])'; then
        remember_failure "The website returned an HTML page instead of $display_name. The file does not appear to be published."
        return 1
    fi

    # RFC 9116 requires at least one Contact field, so arbitrary text is not security.txt.
    if [[ $document == security ]] && ! LC_ALL=C /usr/bin/grep -Eiq '^[[:space:]]*contact[[:space:]]*:' "$body_file"; then
        remember_failure "The response did not contain a valid security.txt Contact field. The file does not appear to be published."
        return 1
    fi

    /bin/cat "$body_file"
    return 0
}

# Try the standard path first; security.txt also has a widely used legacy root location.
fetch_from_host() {
    local host=$1 path
    for path in "${paths[@]}"; do
        fetch_candidate "https://$host$path" && return 0
    done
    return 1
}

fetch_from_host "$requested_host" && exit 0

# A broken www redirect sometimes leaves the apex document reachable, so use it as a fallback.
if [[ $requested_host == www.* ]]; then
    fetch_from_host "${requested_host#www.}" && exit 0
fi

printf '%s\n' "${first_failure:-The website did not return $display_name.}" >&2
exit 65
