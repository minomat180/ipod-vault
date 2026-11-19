# Security model

ipod-vault keeps passwords in an [age](https://age-encryption.org)-encrypted
file on a removable iPod and the key on the host. This page says what that
protects against and what it does not.

## Reporting a problem

This is a personal tool with a single maintainer. If you find a flaw, use
"Report a vulnerability" on this repository's Security tab. If that button is
not there, open an issue asking for a private contact, without details.

## What it protects against

- **Losing the iPod.** The iPod holds only `vault/vault.age`. The private key
  is never written to it. Whoever finds the iPod sees age ciphertext.
- **Losing the host's disk.** Without the iPod there is no vault to decrypt.
  The keyring item alone is useless. This stops being true once you keep a
  copy of `vault.age` on the same host, which is a convenience trade-off you
  make yourself.
- **A decrypted vault file.** `bin/vault` decrypts to stdout and keeps rows in
  pipes and shell variables. Edits are re-encrypted to a temp file on the iPod
  and renamed over `vault.age`; no decrypted copy of the vault is written.
  Every command that rewrites the vault decrypts first and stops if that
  fails, so a wrong key cannot replace the vault with an empty one.
- **Passwords in argv.** No command line carries a password. The edit path
  hands values to `awk` through the environment, which only processes of the
  same user can read, rather than `awk -v`, which would show them in `ps`.
- **Passwords in an agent's transcript.** A coding agent pipes the decrypted
  value into the one command that needs it and never prints it (README,
  "Agent recipes"). This is a rule the agent follows, not a mechanism: nothing
  redacts output, so a command that echoes its input leaks the value.

## What it does not protect against

- **Anything running as your user while the keyring is unlocked.** The
  gnome-keyring login collection stays unlocked for the whole session, and
  reading the key needs no prompt:

  ```bash
  age -d -i <(secret-tool lookup service ipod-vault key age-identity) /mnt/ipod/vault/vault.age
  ```

  Malware, a compromised dependency or an agent that ignores its rules can run
  that. With `IPOD_VAULT_IDENTITY` pointing at a key file, anything that can
  read the file can do the same. The pipe-only rule guards against accidents,
  not against intent.
- **Swap.** Decrypted data lives in ordinary process memory. Without encrypted
  swap it can be paged to disk.
- **The clipboard.** A copied password sits in the Wayland clipboard for 45
  seconds, where any client can read it. wl-copy serves it from a temp file
  under `$TMPDIR` (or `/tmp`), which is on disk unless that is a tmpfs.
  `vault get --show` prints it to the terminal.
- **A replaced `vault.age`.** age detects a modified file, but it does not
  prove who wrote one: anyone who knows your public recipient can encrypt a
  new `vault.age` that decrypts cleanly, and an older copy also decrypts
  without warning. Someone with the iPod can also simply delete it. Keep a
  backup copy.

Closing the first gap would need a keyring backend that prompts per read, or a
hardware token holding the age key (age supports YubiKeys through
`age-plugin-yubikey`). Neither is implemented.

## Where things live

| Item                     | Location                                               |
|--------------------------|--------------------------------------------------------|
| age private key          | gnome-keyring, `service=ipod-vault key=age-identity`   |
| age public key           | gnome-keyring, `service=ipod-vault key=recipient`      |
| encrypted vault          | `/mnt/ipod/vault/vault.age`                            |

## Back up your key

If the keyring item is lost, the vault cannot be decrypted. Export the key once
straight to offline storage (a second encrypted drive, or print it), never to
the iPod and never to a scratch file you plan to delete later:

```bash
secret-tool lookup service ipod-vault key age-identity > /path/to/offline-drive/age-identity
```

Restore on a new machine:

```bash
secret-tool store --label='ipod-vault age identity' service ipod-vault key age-identity < /path/to/offline-drive/age-identity
age-keygen -y /path/to/offline-drive/age-identity \
  | secret-tool store --label='ipod-vault recipient' service ipod-vault key recipient
```
