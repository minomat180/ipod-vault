# Terminal recording for the README. Render from the repo root with:
#   vhs docs/demo/demo.tape
# Needs age, fzf and vhs on PATH. Uses only the throwaway vault from setup.sh.
Output docs/demo/demo.gif

Set Shell "bash"
Set FontSize 20
Set Width 1400
Set Height 560
Set Padding 24
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type "export PS1='$ ' && source docs/demo/setup.sh && clear"
Enter
Sleep 1s
Show

Type "# the vault directory on the iPod: one file of age ciphertext"
Enter
Type "ls ipod/vault && head -c 60 ipod/vault/vault.age; echo"
Enter
Sleep 2.5s

Hide
Type "clear"
Enter
Show

Type "vault ls"
Enter
Sleep 3s

Type "vault"
Enter
Sleep 1.5s
Type@150ms "web"
Sleep 1.2s
Down
Sleep 1.2s
Escape
Sleep 1s

Hide
Type "clear"
Enter
Show

Type "# an agent pipes one password into one command; the terminal never shows it"
Enter
Type `vault decrypt | awk -F'\t' -v l=web/github '$1==l {p=$3} END {printf "%s", p}' | wc -c`
Enter
Sleep 3s

Type "genpass.sh -l 24 -n 2"
Enter
Sleep 3s

Hide
Type `cd - >/dev/null && rm -rf "$DEMO"`
Enter
