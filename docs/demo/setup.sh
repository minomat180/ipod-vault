#!/usr/bin/env bash
# Build a throwaway demo vault for docs/demo/demo.tape.
#
#   source docs/demo/setup.sh
#
# Creates a temp dir with a fresh age key and a vault.age holding obviously
# fake entries, then points bin/vault at it through IPOD_VAULT_DIR and
# IPOD_VAULT_IDENTITY. No iPod, no keyring, nothing outside the temp dir.
set -euo pipefail

DEMO="$(mktemp -d "${TMPDIR:-/tmp}/ipod-vault-demo.XXXXXX")"
mkdir -p "$DEMO/ipod/vault"
age-keygen -o "$DEMO/demo-key.txt" 2>/dev/null

{
    printf '# label\tusername\tpassword\tdate\n'
    printf 'web/github\tdemo-user\tcorrect-horse-battery-staple\t2026-08-25\n'
    printf 'web/forum\tdemo-user\tnot-a-real-password-1\t2026-09-02\n'
    printf 'mail/example\tdemo@example.com\tnot-a-real-password-2\t2026-10-14\n'
    printf 'db/staging\tpostgres\tnot-a-real-password-3\t2026-11-01\n'
    printf 'router/admin\tadmin\tnot-a-real-password-4\t2026-11-12\n'
} | age -r "$(age-keygen -y "$DEMO/demo-key.txt")" -o "$DEMO/ipod/vault/vault.age"

set +eu
export IPOD_VAULT_DIR="$DEMO/ipod/vault"
export IPOD_VAULT_IDENTITY="$DEMO/demo-key.txt"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$REPO/bin:$PATH"
cd "$DEMO"
