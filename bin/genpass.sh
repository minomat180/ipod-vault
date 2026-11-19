#!/usr/bin/env bash
# genpass.sh - generate extremely strong passwords
#
# Usage:
#   genpass.sh [-l LENGTH] [-n COUNT] [-s] [-w] [-p PRESET]
#
#   -l LENGTH   password length (default 32)
#   -n COUNT    how many passwords to generate (default 1)
#   -s          simple mode: alnum only, no symbols (still strong, easier to type)
#   -w          wordlist/passphrase mode instead of char-based password
#   -p PRESET   use a named preset (overrides -l/-s/-w defaults, can still be
#               combined with -n). Presets:
#                 paypal   20 chars, safe symbol subset (PayPal's 20-char cap)
#                 short20  20 chars, safe symbol subset (generic short-max sites)
#                 pin      6 digits, numeric only
#                 simple16 16 chars, alnum only
#               List presets: genpass.sh -p list
#
# Uses /dev/urandom via openssl for CSPRNG. No shell $RANDOM anywhere.

set -euo pipefail

LENGTH=32
COUNT=1
MODE="full"   # full | simple | phrase | pin

usage() {
    grep '^#' "$0" | sed -n '2,19p' | sed 's/^# \{0,1\}//'
    exit 1
}

apply_preset() {
    case "$1" in
        list)
            echo "paypal   20 chars, safe symbols (PayPal's 20-char max)"
            echo "short20  20 chars, safe symbols (generic short-max sites)"
            echo "pin      6 digits, numeric only"
            echo "simple16 16 chars, alnum only"
            exit 0
            ;;
        paypal|short20) LENGTH=20; MODE="safe" ;;
        pin)            LENGTH=6;  MODE="pin" ;;
        simple16)       LENGTH=16; MODE="simple" ;;
        *) echo "Unknown preset: $1 (try -p list)" >&2; exit 1 ;;
    esac
}

while getopts ":l:n:p:swh" opt; do
    case "$opt" in
        l) LENGTH="$OPTARG" ;;
        n) COUNT="$OPTARG" ;;
        s) MODE="simple" ;;
        w) MODE="phrase" ;;
        p) apply_preset "$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Full charset: upper, lower, digits, symbols (avoids ambiguous chars? no - max entropy, keep all)
CHARSET_FULL='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!"#$%&'"'"'()*+,-./:;<=>?@[\]^_`{|}~'
CHARSET_SIMPLE='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
# Safe subset: no quotes/backslash/backtick/angle-brackets/whitespace-adjacent
# chars that trip up some web forms, shells, or URL contexts.
CHARSET_SAFE='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+'
CHARSET_PIN='0123456789'

gen_charpass() {
    local len="$1" charset="$2"
    local n=${#charset}
    local pass=""
    # pull random bytes, map each to a charset index, reject bias via modulo-rejection
    while [ "${#pass}" -lt "$len" ]; do
        local byte
        byte=$(od -An -tu1 -N1 /dev/urandom | tr -d ' ')
        # reject bytes that would bias the modulo distribution
        local max=$(( (256 / n) * n ))
        if [ "$byte" -lt "$max" ]; then
            local idx=$(( byte % n ))
            pass+="${charset:idx:1}"
        fi
    done
    echo "$pass"
}

gen_phrase() {
    local words=$1
    local wordlist=""
    for f in /usr/share/dict/words /usr/share/cracklib/cracklib-small; do
        [ -r "$f" ] && wordlist="$f" && break
    done
    if [ -z "$wordlist" ]; then
        echo "No wordlist found (install a dictionary package, e.g. words)." >&2
        exit 1
    fi
    local total
    total=$(wc -l < "$wordlist")
    local out=()
    for _ in $(seq 1 "$words"); do
        local r
        r=$(( $(od -An -tu4 -N4 /dev/urandom | tr -d ' ') % total + 1 ))
        out+=("$(sed -n "${r}p" "$wordlist" | tr -cd 'a-zA-Z')")
    done
    local sep=$(( $(od -An -tu1 -N1 /dev/urandom | tr -d ' ') % 100 ))
    IFS='-'
    echo "${out[*]}-${sep}"
    unset IFS
}

for _ in $(seq 1 "$COUNT"); do
    case "$MODE" in
        full)   gen_charpass "$LENGTH" "$CHARSET_FULL" ;;
        simple) gen_charpass "$LENGTH" "$CHARSET_SIMPLE" ;;
        safe)   gen_charpass "$LENGTH" "$CHARSET_SAFE" ;;
        pin)    gen_charpass "$LENGTH" "$CHARSET_PIN" ;;
        phrase) gen_phrase "${LENGTH:-6}" ;;
    esac
done
