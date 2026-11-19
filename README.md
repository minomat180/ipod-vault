# ipod-vault

A password vault for one person on Linux: an age-encrypted file on a removable
iPod, opened from a terminal with an fzf picker, and usable by a coding agent
through a pipe so that the agent never sees the password.

![vault ls, the fzf picker and a password piped into a command, run against a throwaway demo vault](docs/demo/demo.gif)

The recording uses a throwaway vault built by
[`docs/demo/setup.sh`](docs/demo/setup.sh): a fresh age key and five fake
entries in a temp directory.

## Why it is built this way

The vault is split across two places, and neither one is enough on its own.

- **The iPod holds only ciphertext.** `vault/vault.age` is a single
  [age](https://age-encryption.org) file. The iPod is a plain FAT32 drive with
  no key on it, so whoever finds it has an encrypted blob.
- **The host holds only the key.** The age private key is an item in the
  gnome-keyring login collection (`service=ipod-vault key=age-identity`),
  created by `install.sh`. Without the iPod there is nothing to decrypt.
- **Plaintext never touches a disk.** `vault` decrypts into a pipe or a shell
  variable, edits the rows with `awk`, and re-encrypts to a temp file on the
  iPod that is renamed over `vault.age`. The password itself goes to the
  Wayland clipboard and is cleared after 45 seconds.
- **Agents get a pipe, not a value.** A coding agent (I use Claude Code) runs
  `vault decrypt`, picks one row with `awk` and pipes the password into the one
  command that needs it. The value never appears in the agent's transcript or
  in a process's argv.

The last point is a convention, not a mechanism. Nothing redacts output: an
agent that pipes the password into `cat` has leaked it. What the design gets
you, and what it does not, is spelled out in
[`docs/SECURITY.md`](docs/SECURITY.md).

## Run it

Requirements: Linux with a Wayland session and a running Secret Service
(gnome-keyring), plus `age`, `secret-tool` (libsecret), `fzf`, `wl-clipboard`,
`libnotify` and `util-linux`. Mounting uses `sudo mount`, so the user needs
sudo rights for `mount` and `umount`.

```bash
git clone https://github.com/minomat180/ipod-vault ~/Projects/ipod-vault
cd ~/Projects/ipod-vault
./install.sh    # checks dependencies, creates the age key in the keyring,
                # links vault and genpass.sh into ~/bin
```

`install.sh` is safe to re-run; it keeps an existing key. Back the key up
right away ([`docs/SECURITY.md`](docs/SECURITY.md#back-up-your-key)): if the
keyring item is lost, the vault cannot be decrypted.

Give the iPod's data partition the filesystem label `IPOD`, plug it in and run
`vault`. It mounts the partition at `/mnt/ipod`, decrypts and opens the picker.

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
vault import < rows.tsv   # merge label<TAB>user<TAB>pass rows in
vault decrypt             # plaintext to stdout, for pipes
vault mount | vault umount
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
inside `sh -c`); never print, echo, store or encode it. The agent's own
permission prompt is the only approval step, so it says which entry it reads
and why before it runs the command.

```bash
# list labels
vault decrypt | awk -F'\t' 'NF>=4 && $1!~/^#/ {print $1}'

# one password into one command on stdin
vault decrypt \
  | awk -F'\t' -v l=web/example '$1==l {p=$3} END {printf "%s", p}' \
  | some-cli login --password-stdin

# one password as an environment variable, never in argv
vault decrypt \
  | awk -F'\t' -v l=db/staging '$1==l {p=$3} END {printf "%s", p}' \
  | sh -c 'PGPASSWORD=$(cat) psql -h db.example.internal -U app -c "select 1"'
```

On a machine without the iPod, a copy of `vault.age` and an identity file work
the same way: `age -d -i <identity> vault.age` replaces `vault decrypt`.

### Password generator

`vault add` uses `bin/genpass.sh`, which also works on its own. Characters are
drawn from `/dev/urandom` with rejection sampling, so every character in the
set is equally likely.

```bash
genpass.sh                # 32 characters from all 94 printable ASCII symbols (about 209 bits)
genpass.sh -l 20 -n 3     # three 20-character passwords
genpass.sh -s -l 24       # letters and digits only
genpass.sh -p list        # presets: paypal, short20, pin, simple16
genpass.sh -w             # six-word passphrase (needs /usr/share/dict/words)
```

## How it works

```text
            host (Linux)                                   iPod (FAT32, label IPOD)
  +--------------------------------------+               +-------------------------+
  | gnome-keyring: age private key       |               | vault/vault.age         |
  |        |                             |               | (age ciphertext, the    |
  |        v                             |    age -d     |  only thing stored)     |
  |  vault: plaintext in pipes and  <----+---------------+                         |
  |  shell variables, edited with awk    |               |                         |
  |        |                             |    age -r     |                         |
  |        +-----------------------------+-------------->+ temp file, renamed over |
  |                                      |               | vault.age               |
  +--------------------------------------+               +-------------------------+
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
- **Plaintext lives in RAM, not on disk, but RAM can be swapped.** Bash
  variables are ordinary process memory; without encrypted swap they can reach
  the swap partition.
- **Linux only.** Mounting uses `blkid` and `findmnt`, copying uses
  `wl-clipboard`. On macOS I read the vault with `age` and an identity file.
- **No sync, no history.** There is one `vault.age`; back it up yourself.
- **No tests.** The scripts were checked by hand against the demo vault.

## License

MIT, see [LICENSE](LICENSE). Encryption is [age](https://github.com/FiloSottile/age)
by Filippo Valsorda; the picker is [fzf](https://github.com/junegunn/fzf).
