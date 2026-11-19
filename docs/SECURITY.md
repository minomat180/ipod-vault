# Security model

## What this protects against

- **Losing the iPod.** The iPod holds only `vault.age`, an [age](https://age-encryption.org)-encrypted
  file. The private key is **never** written to the iPod. Someone who finds or
  steals the iPod and plugs it into any computer sees ciphertext and nothing else.
- **Plaintext at rest.** Passwords are never stored unencrypted on the iPod.
  During normal use the file is decrypted only into `/dev/shm` (a RAM-backed
  tmpfs) or into shell variables, never onto the iPod's FAT32 filesystem.
- **Leaking through the agent.** When Claude Code uses a password, it pipes the
  decrypted value straight into the one command that needs it (stdin, or an
  environment variable set inside `sh -c`). It is never returned to the model,
  never printed in the transcript and never placed on a command line where `ps`
  could see it. This is a rule the agent follows (README, "Agents"), not a
  mechanism: nothing redacts output, so a command that echoes its input would
  leak the value into the transcript. Use only commands that do not.

## What this does NOT protect against (yet)

- **A determined local attacker while you are logged in.** Your gnome-keyring
  login collection is unlocked for your whole session. Anyone (or any process)
  with your shell access can run:

  ```bash
  age -d -i <(secret-tool lookup service ipod-vault key age-identity) /mnt/ipod/vault/vault.age
  ```

  and read everything, with no prompt. On the Mac the key is a plain file
  (`~/.ipod-vault/age-identity.txt`, mode 600), so the same holds there. The
  only approval step for an agent is Claude Code's permission prompt; the
  pipe-only rule keeps secrets out of the transcript and out of argv, which is
  a guard against accident and drift, not against intent.

- **Malware running as your user.** Same reason.

## Where the key lives

| Item | Location | Why |
|------|----------|-----|
| age **private** key | gnome-keyring (`service=ipod-vault key=age-identity`) | login-locked, never leaves the machine |
| age **public** recipient | gnome-keyring (`service=ipod-vault key=recipient`) | used to re-encrypt on every edit |
| encrypted vault | `/mnt/ipod/vault/vault.age` | portable, useless without the key |

## Back up your key

If you lose the gnome-keyring item, the vault is unrecoverable. Export the private
key once and store it offline (paper, a second encrypted drive, a password
manager — **not** the iPod):

```bash
secret-tool lookup service ipod-vault key age-identity > age-identity.backup
# move age-identity.backup somewhere safe, then shred the copy on disk
```

To restore on a new machine:

```bash
secret-tool store --label='ipod-vault age identity' service ipod-vault key age-identity < age-identity.backup
grep -oE 'age1[0-9a-z]+' <(age-keygen -y age-identity.backup) \
  | secret-tool store --label='ipod-vault recipient' service ipod-vault key recipient
```

## Threat-model summary

This is a **portable, theft-resistant password store that agents can use without seeing it**, not a
hardware-enforced vault. The realistic wins are: nothing readable if the iPod is
lost, no plaintext at rest, and secrets that stay out of AI transcripts and
process listings. If you need protection against a local attacker who already has
your session, you need a keyring backend that prompts per read (or a hardware
token), which is out of scope for v0.1.
