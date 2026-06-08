# dotfiles

Personal dotfiles managed with [chezmoi](https://chezmoi.io).

## New machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply fspinolo
```

(or `chezmoi init --apply git@github.com:fspinolo/dotfiles.git` if chezmoi
is already installed)

On first run you'll be prompted for:

- **machine** — `work`, `personal`, etc. Drives the machine-specific split.
- **email** — the git email for `~/.gitconfig` on this machine.

Answers are stored in `~/.config/chezmoi/chezmoi.toml`, which is **not**
part of the repo — it's the one per-machine file you keep local.

## How the machine split works

Three mechanisms, smallest to biggest hammer:

1. **Per-machine data** (`~/.config/chezmoi/chezmoi.toml`) holds values
   like `machine` and `email`. Nothing secret, never committed.

2. **Templates** (`*.tmpl`) substitute those values into file content.
   `dot_gitconfig.tmpl` pulls the git email from `{{ .email }}`, so each
   machine gets its own identity from one shared source file.

3. **`.chezmoiignore`** (itself a template) drops whole files on machines
   where they don't belong. Work-only files (`tmuxinator/`,
   `zsh/work.zsh`) are committed to the repo for backup but only written
   out when `machine == "work"`.

`dot_zprofile` needs no machine data — it detects the Homebrew prefix at
runtime (Apple Silicon `/opt/homebrew` vs Intel `/usr/local`), so it's
portable as-is.

`dot_zshrc` stays universal and ends with a conditional
`source ~/.config/zsh/work.zsh` — present only on work machines.

## Secrets

Secrets and machine-local state are never managed here (see
`.chezmoiignore`): `gh/hosts.yml`, `bk.yaml`, `cagent/`, `temporalio/`,
`~/.aws`, `~/.ssh`. Re-authenticate manually on a new machine
(`gh auth login`, `aws configure`, generate SSH keys, etc).

## Day-to-day

```sh
chezmoi edit ~/.zshrc     # edit the source, then apply
chezmoi diff              # preview pending changes to $HOME
chezmoi apply             # write changes to $HOME
chezmoi add ~/.foo        # bring a new file under management
chezmoi cd                # drop into the source repo (git lives here)
chezmoi update            # git pull + apply (e.g. on another machine)
```

After editing in the source repo, commit and push from `chezmoi cd`.
