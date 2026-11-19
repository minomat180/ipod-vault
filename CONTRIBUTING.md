# Contributing

ipod-vault is a personal tool that I maintain for my own setup, so I am not
looking for feature contributions. Bug reports are welcome as issues, and
security problems go through the private route in
[`docs/SECURITY.md`](docs/SECURITY.md#reporting-a-problem).

If you change the scripts, run `shellcheck bin/vault bin/genpass.sh install.sh
docs/demo/setup.sh` from the repo root, then try them against the throwaway
vault from `source docs/demo/setup.sh` rather than a real one.
