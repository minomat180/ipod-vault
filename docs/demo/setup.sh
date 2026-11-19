#!/usr/bin/env bash
# Build a throwaway demo vault for docs/demo/demo.tape. Source it from the
# repo root:
#
#   source docs/demo/setup.sh
#
# It creates a temp dir with a fresh age key and a vault.age holding obviously
# fake entries, points bin/vault at it through IPOD_VAULT_DIR and
# IPOD_VAULT_IDENTITY, puts bin/ on PATH and cd's into the temp dir. No iPod,
# no keyring. Remove it afterwards with: rm -rf "$DEMO"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || return 1
DEMO="$(mktemp -d "${TMPDIR:-/tmp}/ipod-vault-demo.XXXXXX")" || return 1
mkdir -p "$DEMO/ipod/vault" || return 1
age-keygen -o "$DEMO/demo-key.txt" 2>/dev/null || return 1

{
    printf '# label\tusername\tpassword\tdate\n'
    printf 'web/github\tdemo-user\tcorrect-horse-battery-staple\t2026-08-25\n'
    printf 'web/forum\tdemo-user\tnot-a-real-password-1\t2026-09-02\n'
    printf 'mail/example\tdemo@example.com\tnot-a-real-password-2\t2026-10-14\n'
    printf 'db/staging\tpostgres\tnot-a-real-password-3\t2026-11-01\n'
    printf 'router/admin\tadmin\tnot-a-real-password-4\t2026-11-12\n'
} | age -r "$(age-keygen -y "$DEMO/demo-key.txt")" -o "$DEMO/ipod/vault/vault.age" || return 1

export DEMO
export IPOD_VAULT_DIR="$DEMO/ipod/vault"
export IPOD_VAULT_IDENTITY="$DEMO/demo-key.txt"
export PATH="$REPO/bin:$PATH"
cd "$DEMO" || return 1
