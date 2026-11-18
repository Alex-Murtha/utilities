# utilities

Bootstrap for a fresh Fedora workstation. Two scripts, both idempotent (safe
to re-run) and atomic per step (files are written to a temp file, then moved
into place). Fedora only.

## Install

1. Non-interactive; the only prompt is one sudo password:

   ```
   curl -fsSL https://raw.githubusercontent.com/Alex-Murtha/utilities/main/install.sh | bash
   ```

2. Run `zsh` (or log out and back in so your login shell switches to zsh), then run the interactive part (GitHub login, git
   identity, Bitwarden token, secrets, repo cloning):

   ```
   ~/code/utilities/setup-interactive.sh
   ```

`install.sh` clones this repo to `~/code/utilities`; everything after that
reads files from the clone. A failed step is recorded and the script carries
on; it prints installed / skipped / failed lists and exits non-zero if
anything failed. Manual logins that remain are in
[docs/post-setup.md](docs/post-setup.md) (also printed at the end of
`setup-interactive.sh`).

## What gets installed

| Tool | Source | Script |
|---|---|---|
| `zsh` | dnf; set as login shell | install.sh |
| `git` | dnf | install.sh |
| `git-lfs` | dnf; `git lfs install` | install.sh |
| `gh` | dnf | install.sh |
| `curl` | dnf | install.sh |
| `wget` | dnf | install.sh |
| `unzip` | dnf | install.sh |
| `gcc` | dnf | install.sh |
| `fontconfig` | dnf | install.sh |
| `nano` | dnf (`KUBE_EDITOR=nano`) | install.sh |
| `which` | dnf (nvm needs it on minimal images) | install.sh |
| `libatomic` | dnf (runtime dependency of node) | install.sh |
| `python3` | dnf | install.sh |
| `python3-pip` | dnf | install.sh |
| `fzf` | dnf | install.sh |
| `jq` | dnf | install.sh |
| `zoxide` | dnf | install.sh |
| `fastfetch` | dnf | install.sh |
| `tree` | dnf | install.sh |
| `libicu` | dnf (runtime dependency of .NET and bicep) | install.sh |
| `azure-cli` | dnf | install.sh |
| `kubernetes-client` | dnf (provides `kubectl`; newest `kubernetes1.XX-client`) | install.sh |
| `helm` | dnf | install.sh |
| `k9s` | dnf | install.sh |
| `yq` | dnf | install.sh |
| `lazygit` | dnf | install.sh |
| `golang` | dnf | install.sh |
| `k3d` | brew (not in Fedora) | install.sh |
| `devspace` | brew (not in Fedora) | install.sh |
| `earthbuild/tap/earth` | brew tap, [EarthBuild](https://github.com/earthbuild/earthbuild) (binary is `earth`) | install.sh |
| `homebrew` | [official installer](https://brew.sh), non-interactive | install.sh |
| `nvm` | [official installer](https://github.com/nvm-sh/nvm), pinned v0.41.0, does not edit rc files | install.sh |
| `node` | `nvm install 26`, set as nvm default | install.sh |
| `corepack` | `npm install -g corepack && corepack enable` | install.sh |
| `dotnet` | [dotnet-install.sh](https://dot.net/v1/dotnet-install.sh), SDK channels 11.0 and 10.0 into `~/.dotnet` (11.0 owns the `dotnet` muxer) | install.sh |
| `bicep` | `az bicep install` (`az bicep upgrade` if present), in `~/.azure/bin` | install.sh |
| `bws` | [Bitwarden's official installer](https://bws.bitwarden.com/install) | install.sh |
| `claude` | [official installer](https://claude.ai/install.sh) (Claude Code) | install.sh |
| `code-new-roman-nerd-font` | [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) release v3.5.1 `CodeNewRoman.zip`, into `~/.local/share/fonts/NerdFonts` | install.sh |
| GitHub login, git identity | `gh auth login`, `gh api user` | setup-interactive.sh |
| Bitwarden token, secrets, repo clones | `bws` via `bin/secrets-refresh` | setup-interactive.sh |

Version pins (`NVM_VERSION`, `NERD_FONTS_VERSION`, `NODE_MAJOR`,
`DOTNET_CHANNELS`) are variables at the top of `install.sh`.

## Files touched

Shell and tool config is managed as marker blocks. Each block is delimited by
exactly these lines; re-running replaces the block with the current snippet
and never modifies lines outside it:

```
# >>> utilities >>>
...
# <<< utilities <<<
```

| Target | Source in this repo |
|---|---|
| `~/.zshenv` | `snippets/zshenv` (PATH, brew, `DOTNET_ROOT`, node, secrets) |
| `~/.zshrc` | `snippets/zshrc` (history, zoxide, nvm) |
| `~/.config/lazygit/config.yml` | `snippets/lazygit.yml` |
| `~/.claude/hooks` | symlink to `claude/hooks` (a real directory is moved to `hooks.bak.<timestamp>`) |
| `~/.claude/settings.json` | `.hooks` replaced from `claude/settings-hooks.json`; other keys kept |
| `~/.config/secrets.env` | written by `bin/secrets-refresh` (mode 600), sourced by `~/.zshenv` |
| `~/.config/bws/token` | Bitwarden machine-account token (mode 600, directory 700) |

## Bitwarden setup (one time)

Secrets live in Bitwarden Secrets Manager, never in this repo.

1. Create an organization with Secrets Manager enabled and a project.
2. Add one secret per environment variable. The secret name is the env var
   name (a valid shell identifier); the value is the value.
3. Add a secret named `CLONE_REPOS` whose value lists the repos to clone, one
   `owner/repo` per line (blank lines and `#` comments are ignored).
4. Create a machine account with read access to that project and generate an
   access token. `setup-interactive.sh` asks for it (hidden input) and saves
   it to `~/.config/bws/token`, after checking it with `bws`; a rejected
   token is not saved. If a saved token turns out to be wrong, run
   `rm ~/.config/bws/token` and re-run `setup-interactive.sh`.

`setup-interactive.sh` clones each repo to `~/code/<repo>` (override the
root with `CODE_DIR`) unless the directory already exists. To pull changed or
rotated secrets later, run `secrets-refresh` and open a new shell.
`CLONE_REPOS` is read directly and is not written to `secrets.env`.

## Adding a tool

Add it to `DNF_PACKAGES` or `BREW_FORMULAE` in `install.sh` (or write an
install function and call it from `step_installers`), add a row to the table
above, and run `bash tests/run.sh`; `tests/readme.test.sh` fails if the table
and `install.sh` disagree.

## Tests

`bash tests/run.sh` runs the unit tests. `bash tests/e2e.sh` runs
`install.sh` twice inside a Fedora container (it never touches the host);
`setup-interactive.sh` is covered by the unit tests with stubbed `gh` and
`bws`.
