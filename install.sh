#!/usr/bin/env bash
# install.sh - set up the encrypted iPod vault on this machine.
#
# Idempotent: safe to run multiple times. It will
#   1. check dependencies
#   2. generate an age keypair and store the PRIVATE key in gnome-keyring
#      (never on the iPod) if one does not already exist
#   3. symlink bin/ scripts into ~/bin
#
# It never writes plaintext passwords to disk and never puts the key on the iPod.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVC="ipod-vault"
BINDIR="$HOME/bin"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# 1. dependencies -----------------------------------------------------------
say "Checking dependencies"
missing=()
for c in age age-keygen secret-tool fzf wl-copy notify-send blkid findmnt column; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing: ${missing[*]}"
    warn "Packages: age, libsecret, fzf, wl-clipboard, libnotify, util-linux"
    exit 1
fi
pgrep -x gnome-keyring-d >/dev/null 2>&1 || pgrep -f gnome-keyring-daemon >/dev/null 2>&1 \
    || warn "No gnome-keyring daemon detected; a Secret Service provider must be running."

# 2. age keypair in keyring -------------------------------------------------
if secret-tool lookup service "$SVC" key age-identity >/dev/null 2>&1; then
    say "age identity already present in gnome-keyring; keeping it"
    if ! secret-tool lookup service "$SVC" key recipient >/dev/null 2>&1; then
        say "Recipient missing; deriving it from the identity"
        age-keygen -y <(secret-tool lookup service "$SVC" key age-identity) \
            | secret-tool store --label="$SVC recipient" service "$SVC" key recipient
    fi
else
    say "Generating age keypair (private key -> gnome-keyring, never the iPod)"
    umask 077
    tmp="/dev/shm/ipod-vault-key.$$"; rm -f "$tmp"
    age-keygen -o "$tmp" 2>"/dev/shm/ipod-vault-pub.$$"
    recipient="$(grep -oE 'age1[0-9a-z]+' "/dev/shm/ipod-vault-pub.$$" | head -1)"
    secret-tool store --label="$SVC age identity" service "$SVC" key age-identity < "$tmp"
    printf '%s' "$recipient" | secret-tool store --label="$SVC recipient" service "$SVC" key recipient
    shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
    rm -f "/dev/shm/ipod-vault-pub.$$"
    say "Public recipient: $recipient"
    warn "BACK UP YOUR KEY. If you lose the gnome-keyring item you lose the vault:"
    warn "  secret-tool lookup service $SVC key age-identity > age-identity.backup   (store offline!)"
fi

# 3. link scripts into ~/bin ------------------------------------------------
say "Linking scripts into $BINDIR"
mkdir -p "$BINDIR"
for f in genpass.sh vault; do
    ln -sf "$HERE/bin/$f" "$BINDIR/$f"
done

say "Done. Connect the iPod and run:  vault"
