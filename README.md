# ipod-vault

A password vault for one person on Linux: an age-encrypted file on a removable
iPod, opened from a terminal with an fzf picker, and usable by a coding agent
through a pipe so that the password stays out of the agent's transcript.

![vault ls, the fzf picker and a password piped into a command, run against a throwaway demo vault](docs/demo/demo.gif)

The recording uses a throwaway vault built by
[`docs/demo/setup.sh`](docs/demo/setup.sh): a fresh age key and five fake
entries in a temp directory.

## Why it is built this way

The vault is split across two places, and neither one is enough on its own.

- **The iPod holds only ciphertext.** `vault/vault.age` is a single
  [age](https://age-encryption.org) file. The iPod is a plain FAT32 drive with
  no key on it, so whoever finds it has an encrypted blob.
- **The host holds only the key.** The age private key and its public
  recipient are items in the gnome-keyring login collection
  (`service=ipod-vault`), created by `install.sh`. Without the iPod there is
  nothing to decrypt.
- **No decrypted vault file is ever written.** `vault` decrypts into a pipe or
  a shell variable, edits the rows with `awk`, and re-encrypts to a temp file
  on the iPod that is renamed over `vault.age`. A copied password goes to the
  Wayland clipboard and is cleared after 45 seconds.
- **Agents get a pipe, not a value.** A coding agent (I use Claude Code) runs
  `vault decrypt`, picks one row with `awk` and pipes the password into the one
  command that needs it, so the value is not in the agent's transcript or in
  any process's argv.

The last point is a convention, not a mechanism. Nothing redacts output: an
agent that pipes the password into `cat` has leaked it. What the design gets
you, and what it does not, is spelled out in
[`docs/SECURITY.md`](docs/SECURITY.md).

## Run it

Requirements: Linux with a Wayland session and a running Secret Service
(gnome-keyring), plus `age`, `secret-tool` (libsecret), `fzf`, `wl-clipboard`,
`libnotify` and `util-linux`. Mounting runs `sudo mkdir`, `sudo mount` and
`sudo umount`, so the user needs sudo rights for those.

```bash
git clone https://github.com/minomat180/ipod-vault ~/Projects/ipod-vault
cd ~/Projects/ipod-vault
./install.sh    # checks dependencies, creates the age key in the keyring,
                # links vault and genpass.sh into ~/bin
```

`~/bin` has to be on your `PATH`. `install.sh` is safe to re-run; it keeps an
existing key. Back the key up right away
([`docs/SECURITY.md`](docs/SECURITY.md#back-up-your-key)): if the keyring item
is lost, the vault cannot be decrypted.

Give the iPod's FAT32 data partition the filesystem label `IPOD` (for example
`sudo fatlabel /dev/sdX2 IPOD`), plug it in and run `vault`. It mounts the
partition at `/mnt/ipod`, decrypts and opens the picker.

### The picker

| Key     | Action                                        |
|---------|-----------------------------------------------|
| enter   | copy the password, clear the clipboard in 45s |
| alt-u   | copy the username                             |
| alt-e   | edit the entry                                |
| alt-d   | delete the entry (asks first)                 |
| alt-a   | add an entry (generated or typed password)    |
| esc     | quit                                          |

### Commands

```bash
vault                     # the picker
vault ls                  # labels, usernames and dates; never passwords
vault add web/example     # add; offers a generated 32-character password
vault edit web/example
vault rm web/example
vault get web/example     # copy the password (--user: username, --show: print both)
vault import < rows.tsv   # add label<TAB>user<TAB>pass rows; same label replaces
vault decrypt             # plaintext to stdout, for pipes
vault mount
vault umount
```

The iPod tends to come back as a different `/dev/sdX` after a replug; `vault`
finds it by label and replaces a stale mount instead of failing.

Four environment variables change where things are, which is how the demo runs
without an iPod or a keyring:

| Variable              | Default         | Purpose                                       |
|-----------------------|-----------------|-----------------------------------------------|
| `IPOD_VAULT_MOUNT`    | `/mnt/ipod`     | mount point                                   |
| `IPOD_VAULT_LABEL`    | `IPOD`          | filesystem label to look for                  |
| `IPOD_VAULT_DIR`      | `<mount>/vault` | use this directory; skips mounting            |
| `IPOD_VAULT_IDENTITY` | keyring item    | age identity file instead of the keyring      |

### Agent recipes

The rules an agent follows: list labels freely; a password only ever travels
through a pipe into one command (on stdin, or as an environment variable set
inside `sh -c`); never print, echo, store or encode it. The `awk` below exits
non-zero when the label does not exist, so with `set -o pipefail` a mistyped
label shows up as a failed pipeline instead of passing silently. The agent's own
permission prompt is the only approval step, so it says which entry it reads
and why before it runs the command.

```bash
# list labels
vault decrypt | awk -F'\t' 'NF>=4 && $1!~/^#/ {print $1}'

# one password into one command on stdin
vault decrypt \
  | awk -F'\t' -v l=web/example '$1==l {p=$3} END {if (p=="") exit 1; printf "%s", p}' \
  | some-cli login --password-stdin

# one password as an environment variable, never in argv
vault decrypt \
  | awk -F'\t' -v l=db/staging '$1==l {p=$3} END {if (p=="") exit 1; printf "%s", p}' \
  | sh -c 'PGPASSWORD=$(cat) psql -h db.example.internal -U app -c "select 1"'
```

On a machine without the iPod, a copy of `vault.age` and an identity file work
the same way: `age -d -i <identity> vault.age` replaces `vault decrypt`.

### Password generator

`vault add` uses `bin/genpass.sh`, which also works on its own. Character
passwords are drawn from `/dev/urandom` with rejection sampling, so every
character in the set is equally likely. Passphrase mode picks words with a
plain modulo over 32 random bits (off from uniform by less than one part in
ten thousand for a wordlist under 400,000 words) and appends a number from 0
to 99 that is not uniform, so count its strength by the words alone.

```bash
genpass.sh                # 32 of the 94 printable ASCII characters (about 210 bits)
genpass.sh -l 20 -n 3     # three 20-character passwords
genpass.sh -s -l 24       # letters and digits only
genpass.sh -p list        # presets: paypal, short20, pin, simple16
genpass.sh -w             # six-word passphrase (needs /usr/share/dict/words)
```

## How it works

```text
  host (Linux)                                 iPod (FAT32, label IPOD)
  +----------------------------+               +---------------------------+
  | gnome-keyring              |               | vault/vault.age           |
  |   age private key          |               |   age ciphertext          |
  |        |                   |    age -d     |                           |
  |        v                   | <------------ |   (only vault file)       |
  | bin/vault                  |               |                           |
  |   plaintext in pipes and   |    age -r     |                           |
  |   shell variables only     | ------------> | temp file, renamed over   |
  |                            |               | vault.age                 |
  +----------------------------+               +---------------------------+
```

Decrypted, the vault is a tab-separated file, one entry per line:

```text
# label        username    password    date
web/example    demo-user   ...         2026-08-25
```

Everything is Bash: `bin/vault` (about 300 lines) is the CLI and picker,
`bin/genpass.sh` the generator, `install.sh` the setup. There is no daemon
and no state besides `vault.age` and the keyring item.

## Status and limits

It holds my own passwords. It is a personal tool, not a product:

- **No protection against code running as you.** While the keyring is unlocked,
  any process of your user can read the key and decrypt the vault without a
  prompt. With an identity file instead of the keyring, the same holds for
  anything that can read that file.
- **Decrypted data is in memory, and memory is not sealed.** Bash variables
  can be paged to an unencrypted swap partition. wl-copy keeps a copied
  password in a temp file under `$TMPDIR` (or `/tmp`) until the clipboard is
  cleared, so `/tmp` should be a tmpfs. A clipboard history manager may keep
  its own copy.
- **Linux only.** Mounting uses `blkid` and `findmnt`, copying uses
  `wl-clipboard`. On macOS I read the vault with `age` and an identity file.
- **No sync, no history.** There is one `vault.age`; back it up yourself.
- **No automated tests.** The scripts pass `shellcheck` and were checked by
  hand against the demo vault.

## License

MIT, see [LICENSE](LICENSE). Encryption is [age](https://github.com/FiloSottile/age)
by Filippo Valsorda; the picker is [fzf](https://github.com/junegunn/fzf).
