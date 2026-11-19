# ipod-vault

A **portable, encrypted password vault on a removable iPod**, with a terminal
browser for humans and a pipe-only recipe that lets a coding agent (Claude
Code) *use* a password without ever *seeing* it.

- **Encrypted at rest.** The iPod holds only `vault.age` (age ciphertext). The
  private key lives in your login keyring, never on the iPod. Lose the iPod and
  the finder gets nothing.
- **fzf browser.** `vault` mounts the iPod, decrypts in RAM, lists entries, and
  copies a password (or username) to the clipboard with a 45-second auto-clear.
- **Agent use.** Claude Code decrypts into a pipe that feeds one command; the
  value never reaches the transcript, argv or a file (see "Agents" below).
- **Strong password generator** using `/dev/urandom` with modulo-rejection
  sampling (no bias, no `$RANDOM`).

Built for [mino's setup](#assumptions) (Void Linux + mango compositor), but the
pieces are portable to any Wayland/libsecret system.

---

## How it works

```
            ┌─────────────── your laptop ───────────────┐
            │                                            │
  vault ──▶ (fzf browser)                                 │
            │   │ decrypt in /dev/shm (RAM)              │
            │   ▼                                        │
 gnome-keyring: age private key ──┐                      │
            │                     │ age -d               │
            │                     ▼                      │
            │            plaintext (RAM only)            │
            │                     ▲                      │
            │                     │ age -r (re-encrypt)  │
            └─────────────────────┼──────────────────────┘
                                  │
                        ┌─────────▼─────────┐
                        │   iPod (FAT32)    │
                        │  vault/vault.age  │  <-- only ciphertext ever touches the iPod
                        └───────────────────┘
```

An agent uses the same `vault decrypt` path (or `age -d` on a copy of
`vault.age`), picks one entry with `awk`, and pipes the password straight into
the one command that needs it.

## Layout

```
bin/
  genpass.sh     strong password / passphrase generator
  genpass-copy   generate -> clipboard (+ auto-clear); used by the menu
  vault          the fzf browser + mount/decrypt/encrypt CLI
docs/
  SECURITY.md    threat model, key backup/restore
  mango-keybinds.conf
install.sh       idempotent setup (keyring keypair, symlinks, migration)
```

## Install

```bash
# not a git repo; copy the folder to ~/Projects/ipod-vault
cd ~/Projects/ipod-vault
./install.sh          # deps check, age keypair -> keyring, ~/bin symlinks
```

Then add the keybindings it prints to `~/.config/mango/config.conf` and reload:

```bash
mmsg dispatch reload_config
```

### Dependencies

`age`, `secret-tool` (libsecret) + a running Secret Service (gnome-keyring),
`wl-clipboard`, `libnotify`, `fzf`, `util-linux` (`blkid`/`findmnt`).

## Usage

### The browser (`vault`)

- Pick an entry -> **Copy password** / **Copy username** / **Show both**
- **Add new entry** -> label, username, then auto-generate or type a password
- **Unmount iPod** -> safe eject

The menu auto-mounts the iPod by its `IPOD` filesystem label and **heals stale
mounts** (the iPod often reappears as a different `/dev/sdX` after re-plugging).

### CLI

```bash
vault            # open the menu
vault mount      # mount (auto-detect by label, heal stale mount)
vault umount     # safe unmount before unplugging
vault decrypt    # print the decrypted vault to stdout (RAM only)
```

### Password generator

```bash
genpass.sh                # 32-char, full symbol set (~209 bits)
genpass.sh -l 20 -n 3     # three 20-char passwords
genpass.sh -s -l 24       # alnum only (sites that reject symbols)
genpass.sh -w -l 5        # 5-word passphrase (needs a wordlist)
genpass.sh -p paypal      # 20 chars, safe symbol subset (PayPal's 20-char cap)
genpass.sh -p list        # list all named presets
```

### Agents (Claude Code)

There is no agent plugin: Claude Code uses the vault through the shell, under
two rules. A secret only ever travels through a pipe into the one command that
needs it (stdin, or an environment variable set inside `sh -c '...'`), and the
agent never prints, echoes, stores or base64s it. Labels and usernames are fine
to list. Claude Code's own permission prompt is the only approval step, so an
agent says which entry it reads and why before it does.

Copies of the ciphertext also live in `~/.ipod-vault/` on mino's machines
(`vault.age`, and `agent-vault-tokens.json.age`, a JSON object of API tokens).
The age key is the keyring item on Linux and `~/.ipod-vault/age-identity.txt`
on the Mac.

```bash
# key: Linux <(secret-tool lookup service ipod-vault key age-identity), Mac ~/.ipod-vault/age-identity.txt
KEY=~/.ipod-vault/age-identity.txt

# list labels (never passwords)
age -d -i "$KEY" ~/.ipod-vault/vault.age | awk -F'\t' 'NF>=4 && $1!~/^#/{print $1}'

# feed one password to one command on stdin
age -d -i "$KEY" ~/.ipod-vault/vault.age \
  | awk -F'\t' -v l=bitwarden '$1==l{p=$3} END{printf "%s", p}' \
  | some-command --password-stdin

# one API token into one command as an env var
age -d -i "$KEY" ~/.ipod-vault/agent-vault-tokens.json.age \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["NAME"], end="")' \
  | sh -c 'TOKEN=$(cat); CLOUDFLARE_API_TOKEN=$TOKEN wrangler whoami'
```

With the iPod attached on Linux, `vault decrypt` replaces the first `age -d`.
Entries named `pi-vault/<NAME>` are API passwords moved over from the old
keyring store on 2026-11-12; the names are historical.

## Vault format

Decrypted, the vault is tab-separated:

```
# label        username   password   date
web/github     me@x.com   ...        2026-08-25
```

## Security

Short version: **theft-safe and no plaintext at rest**, and secrets stay out of
AI transcripts and process listings. It is **not** a hardware-enforced boundary —
while your keyring is unlocked, anything with your shell access can decrypt the
file. Read [`docs/SECURITY.md`](docs/SECURITY.md) before trusting it with
anything critical, and **back up your key** (instructions there).

## Assumptions

- **OS:** Void Linux (glibc). **Compositor:** mango (Wayland). **Shell:** bash.
- The iPod's data partition is FAT32 and labeled `IPOD`, mounted at `/mnt/ipod`.
- Passwordless `sudo` for `mount`/`umount` (so the menu can mount from a keybind).

Adjust `MP`, `LABEL`, and the paths at the top of `bin/vault` for other setups.

## History

Until 2026-11-19 this folder also held a TypeScript extension for the pi coding
agent (`ipod_vault_use` / `ipod_vault_list` tools with an approval dialog and a
Capri approval prompt). mino now uses only Claude Code, so it was removed; a
copy is in `~/Backups/pi-removal-20261119/ipod-vault/pi-extension/` on both
machines.

## License

MIT — see [LICENSE](LICENSE).
