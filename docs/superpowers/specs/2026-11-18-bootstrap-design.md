# utilities: Fedora workstation bootstrap — design

Date: 2026-11-18
Status: draft, awaiting approval

## Intent

Replace the chezmoi-based `dotfiles` repo with something much smaller. The old
repo did too much (VS Code, Docker, Oh My Zsh + p10k, Aikido, Headlamp, a
systemd timer, a Konsole profile, templated dotfiles) and chezmoi needed git
credentials before it could even start, because the repo was private.

The new setup is two plain bash scripts in this **public** repo
(`Alex-Murtha/utilities`), inspired by
[dmythro/terminal-setup](https://github.com/dmythro/terminal-setup): one
readable script, a one-line install, re-runnable, with a README table of
everything it installs.

It is meant to be **run once** on a new machine. After that everything is
maintained by hand (`dnf upgrade`, `brew upgrade`, editing dotfiles directly).
Re-running exists to recover from a failed or partial run, not as a sync
mechanism.

## Goals

- **Script 1 (`install.sh`)**: a single-line, non-interactive install that
  turns a fresh Fedora install into a working dev environment:
  `curl -fsSL https://raw.githubusercontent.com/Alex-Murtha/utilities/main/install.sh | bash`.
  The only input is one sudo password prompt at the start.
- **Script 2 (`setup-interactive.sh`)**: everything that needs a human — GitHub
  login, git identity, Bitwarden token, secrets, repo cloning — run after
  script 1.
- **README** documents every installed tool and its install source, plus both
  commands. A separate `docs/post-setup.md` documents the remaining manual
  logins.
- Both scripts are **idempotent** and **atomic per step**: each step detects
  work already done and skips it; every file write goes to a temp file and is
  moved into place, so a crash never leaves a half-written file.

## Non-goals

- **Distro-agnostic.** Fedora only. Supporting another distro later is a
  future change, not a design constraint now. No OS/distro detection logic.
- **Ongoing dotfile sync.** No symlink farm, no templating, no `apply` command.
- **Runtime install fallbacks.** The install source for each tool is decided
  at design time (below) and hard-coded; the script does not try dnf, then
  brew, then something else.
- **Uninstall / reset script.**
- **Machines already set up by the old chezmoi `dotfiles` repo.** Fresh
  Fedora installs only; no migration or cleanup of the old setup, and the old
  repo's fate is out of scope.
- **Zsh framework, plugins, prompt.** Deliberately left out; the user is
  evaluating frameworks and will add one later. (Added on 2026-11-19: see
  `2026-11-19-zsh-prompt-design.md`, which supersedes every "no plugins or
  prompt" statement in this document.)
- **Version managers beyond nvm.** No mise, no asdf.
- **Deliberately dropped from the old setup:** ripgrep, fd, btop, Azure
  kubelogin, mise, VS Code + extensions, Docker, Oh My Zsh + p10k, Aikido
  (scanner, safe-chain, global git hooks), Headlamp, the disk-cleanup timer,
  the Konsole profile, shell aliases, zsh plugins, prompt. The tool list in
  this document is complete; don't add tools not listed here.

## Anti-goals (would be a failure even if it works)

- **Any reference to the user's employer in this public repo**: company or
  org names, work repo names, registry/subscription names, work email, secret
  names. Work-specific data lives only in Bitwarden Secrets Manager. This
  applies to code, comments, tests, docs, and commit messages.
- Needing GitHub credentials before script 1 can run.
- Overwriting the user's own lines in an existing dotfile.
- Downloading raw release binaries, unless that *is* the project's official
  install method.

## Constraints

- Target: Fedora (currently Fedora 45, including Fedora on WSL2).
- Install-source rule, applied per tool at design time: **dnf** if Fedora
  packages a reasonably current version → else **Homebrew** (core or the
  project's own tap) → else the **project's official install method**. Node is
  the stated exception (nvm preferred over dnf, whose `nodejs26` lags upstream
  by ~10 minors).
- zsh is the login shell; bash dotfiles are not managed.
- The repo is public and cloned over anonymous HTTPS.

## Approaches considered

1. **One readable `install.sh`, terminal-setup style** — helpers at the top,
   package arrays at the top, steps in order; snippets, hooks and docs are
   plain files read from the clone. **Chosen**: closest to the "single simple
   script" that motivated this, and since every step is idempotent, re-running
   the whole thing is cheap.
2. Thin bootstrap that execs numbered step scripts — re-run a single step, but
   recreates the chezmoi-style numbered layout and hides what runs.
3. Package lists in data files with a generic loop — nice for dnf/brew, but
   nvm, dotnet, bws, Claude, the font and bicep all need bespoke code anyway.

For dotfiles, three approaches were considered: overwrite whole files
(terminal-setup), clone + symlink, and **marker blocks appended to existing
files (chosen)** — the repo holds only the lines to add, not full dotfiles.

## Repo layout

```
install.sh                 # script 1
setup-interactive.sh       # script 2
bin/secrets-refresh        # on PATH via ~/code/utilities/bin
snippets/zshenv            # appended to ~/.zshenv
snippets/zshrc             # appended to ~/.zshrc
snippets/lazygit.yml       # appended to ~/.config/lazygit/config.yml
zsh/p10k.zsh               # powerlevel10k config, sourced from the clone (added 2026-11-19)
claude/hooks/*.sh          # Claude Code hooks + tests.sh
claude/settings-hooks.json # the "hooks" object merged into ~/.claude/settings.json
docs/post-setup.md         # manual logins, printed by script 2
README.md
```

## Script 1 — `install.sh`

Runs as the normal user under `bash`, `set -uo pipefail` (not `-e`: failures
are recorded, not fatal — see Error handling).

**Prelude**
- Refuse to run as root.
- Check `/etc/os-release` is Fedora; exit with a clear message if not.
- `sudo -v` once (the only prompt), then a background keep-alive loop
  (`sudo -n true` every ~60s) killed on exit via `trap`.

**Step 1 — dnf.** One `sudo dnf install -y` of the packages not yet installed:

| Package(s) | Purpose |
|---|---|
| zsh, git, git-lfs, gh, curl, wget, unzip, gcc, fontconfig, nano | base (nano because `KUBE_EDITOR=nano`; may be absent on Fedora's WSL image) |
| libatomic | needed by nvm's prebuilt node binaries |
| python3, python3-pip | carried over from the old setup |
| fzf, jq, zoxide, fastfetch, tree | CLI |
| azure-cli | Azure (bicep comes through it, step 4) |
| kubectl (Fedora's versioned `kubernetes1.XX-client`; builder picks the provide name that tracks newest), helm, k9s, yq | Kubernetes |
| lazygit | git TUI |
| golang | Go (current in Fedora: 1.27.x) |

Then: set zsh as login shell (`sudo usermod -s "$(command -v zsh)" "$USER"`)
if it isn't already; `git lfs install`; `git config --global pull.rebase true`.
No git identity here (that's script 2).

**Step 2 — clone this repo** to `~/code/utilities` over
`https://github.com/Alex-Murtha/utilities.git` (no credentials). If it already
exists: `git pull --ff-only`; if that fails (dirty/diverged) warn and continue
with what's there. Everything after this step reads files from the clone,
which is what makes the one-line `curl | bash` work.

**Step 3 — Homebrew.** Official installer with `NONINTERACTIVE=1` if
`/home/linuxbrew/.linuxbrew/bin/brew` is missing; `eval "$(brew shellenv)"` for
the rest of the run. Then install if missing:

| Formula | Why brew |
|---|---|
| k3d | not in Fedora |
| devspace | not in Fedora |
| `earthbuild/tap/earth` | EarthBuild's own tap (Linux supported). Binary is `earth`; no `earthly` alias. |

**Step 4 — official installers** (each skipped when already present):

| Tool | Method |
|---|---|
| nvm | official `install.sh` from nvm-sh/nvm at a pinned tag, with `PROFILE=/dev/null` so it does not edit rc files (our snippet loads it) |
| node 26 | `nvm install 26 && nvm alias default 26` |
| corepack | `npm install -g corepack && corepack enable` — Node 25+ no longer bundles it and yarn is pinned via `packageManager` (builder's call: keep, it was in the old setup) |
| .NET SDK 11 and 10 | `dotnet-install.sh` from `https://dot.net/v1/dotnet-install.sh` into `~/.dotnet` with `--no-path`: `--channel 11.0` first, then `--channel 10.0 --skip-non-versioned-files` so 11 owns the `dotnet` muxer. Fedora only ships 10.0.1xx; repos need 10.0.4xx+. |
| bicep | `az bicep install` (installs to `~/.azure/bin/bicep`, not on PATH; only used through `az`). If already installed, `az bicep upgrade`. |
| bws | Bitwarden's official `curl https://bws.bitwarden.com/install \| sh` |
| Claude Code | official `curl -fsSL https://claude.ai/install.sh \| bash` |
| Code New Roman Nerd Font | `CodeNewRoman.zip` from the ryanoasis/nerd-fonts release (the project's documented manual install), pinned version, into `~/.local/share/fonts/NerdFonts`, version stamp file, `fc-cache -f`. |

Pinned versions (nvm tag, Nerd Fonts version) are variables at the top of the
script.

**Step 5 — snippets.** For each `snippets/<name>` → target pair, apply the
marker-block algorithm (below):

- `snippets/zshenv` → `~/.zshenv` (every zsh, including Claude Code's
  non-interactive shells): PATH additions `~/.local/bin`,
  `~/code/utilities/bin`, `~/.dotnet`, `~/.dotnet/tools`, `~/go/bin`; brew
  shellenv; `DOTNET_ROOT=$HOME/.dotnet`; `KUBE_EDITOR=nano`; source
  `~/.config/secrets.env` with `set -a` if readable. **Node/npm must also be on
  PATH in non-interactive shells** (agents run builds); builder chooses how
  (e.g. prepend `$NVM_DIR/versions/node/<default>/bin` resolved from nvm's
  `alias/default`, rather than sourcing nvm.sh in every shell).
- `snippets/zshrc` → `~/.zshrc`: history (`HISTSIZE=SAVEHIST=50000`,
  `HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY`), `zoxide init zsh`, load
  nvm (`nvm.sh` + completion). Nothing else — no aliases, plugins or prompt.
- `snippets/lazygit.yml` → `~/.config/lazygit/config.yml`:
  `gui: nerdFontsVersion: "3"`.

**Step 6 — Claude Code hooks.**
- `~/.claude/hooks` → symlink to `~/code/utilities/claude/hooks`. Existing
  correct symlink: skip. Existing other symlink: replace. Existing real
  directory: move to `~/.claude/hooks.bak.<timestamp>` then link.
- Merge `claude/settings-hooks.json` into `~/.claude/settings.json` with jq:
  the `.hooks` key is replaced wholesale (the repo is authoritative for
  hooks); every other key is preserved. Missing file → created. Paths in the
  JSON use `$HOME/.claude/hooks/...` substituted at merge time. Temp file + mv.

**Summary.** Print installed / skipped / failed per item, then the next step:
open a new zsh and run `~/code/utilities/setup-interactive.sh`.

### Marker-block algorithm (shared helper)

```
apply_snippet <snippet_file> <target_file>
  mkdir -p dirname(target)
  tmp = mktemp next to target
  copy target to tmp (empty if target missing)
  delete any existing "# >>> utilities >>>" … "# <<< utilities <<<" block from tmp
  append marker start, snippet contents, marker end
  if tmp equals target: remove tmp, report "skipped"
  else preserve target's mode, mv tmp → target (through a symlink if target is one)
```

Lines outside the markers are never modified. Re-running replaces the block
with the current snippet. The YAML target uses the same `#` markers (valid
YAML comments).

### Error handling

terminal-setup's pattern: each install is wrapped so a failure is appended to a
`FAILED` list and the script continues. Exit non-zero at the end if anything
failed, listing what. Steps that later steps depend on (dnf base, the clone)
abort the run if they fail, since nothing after them can work.

## Script 2 — `setup-interactive.sh`

Run from `~/code/utilities` in a new zsh after script 1. Same helpers, same
idempotency. Steps:

1. **GitHub login.** If `gh auth status` fails: plain `gh auth login` (the
   user chooses SSH/HTTPS; gh handles keys and git credentials). No extra
   scopes, no SSH code in this repo.
2. **Git identity.** If `user.name`/`user.email` unset globally: read
   `gh api user` → `name` (fallback `login`) and `email` (fallback
   `<id>+<login>@users.noreply.github.com`); set with `git config --global`;
   print what was set. No prompt.
3. **Bitwarden token.** If `~/.config/bws/token` missing: prompt with hidden
   input (`read -rs`), write via temp file, mode 600, dir mode 700.
4. **Secrets.** Run `secrets-refresh`.
5. **Clone repos.** Fetch the `CLONE_REPOS` secret directly from bws (not from
   the env file); it is a newline-separated explicit list of `owner/repo`, no
   wildcards. For each: `gh repo clone owner/repo ~/code/<repo>` unless the
   directory exists. Blank lines and `#` comments ignored. Missing secret →
   warn, skip.
6. **Print `docs/post-setup.md`** with `cat`.

### `bin/secrets-refresh`

Port of the old script, made generic:
- No project id: the machine-account token only sees one project, so
  `bws secret list --output json` returns exactly the right secrets.
- Validates every key is a legal env var name; excludes `CLONE_REPOS`.
- Writes `export KEY='value'` lines (`@sh` quoting) to `~/.config/secrets.env`
  via temp file, mode 600. On any failure the previous file is kept and it
  exits non-zero. Never prints values.
- Also the manual command for rotating secrets later.

## Claude Code hooks (made generic)

| Hook | Change |
|---|---|
| `no-full-test-suite.sh`, `orca-worktrees.sh` | port unchanged |
| `no-secret-material.sh` | protect `~/.config/secrets.env`, `~/.config/bws/`, `bws secret` commands, `*.lic`; drop the dead sops-nix pattern |
| `prettier.sh` | no hard-coded paths: walk up from the edited file to the nearest directory with a prettier config (`.prettierrc*`, `prettier.config.*`, or a `prettier` key in `package.json`) and a `node_modules/.bin/prettier`; run that with `--write --ignore-unknown`; silent no-op otherwise |
| `azure-guardrails.sh` | same detection (`az acr show`, `az account set`), but **both now `ask`** instead of the first being `deny`; messages are generic (e.g. "prefer data-plane calls such as `az acr repository list --name <registry>`; don't switch subscriptions to fix ACR lookups") |
| `tests.sh` | updated to placeholder names and the new `ask` decisions; must pass |

Hook wiring (`claude/settings-hooks.json`): PreToolUse/Bash → no-secret-material,
no-full-test-suite, azure-guardrails, orca-worktrees; PostToolUse/Edit|Write →
prettier.

## Docs

- **README.md**: what this is; the one-line install; then script 2; a table
  **Tool | Source | Script** for every item above (dnf / brew / brew tap /
  official installer, with links); the files each script touches and the
  marker convention; one-time Bitwarden setup described generically
  (organization + Secrets Manager project, secret name = env var name, a
  `CLONE_REPOS` secret listing `owner/repo` per line, a machine account with
  read access); how to add a tool (edit the array + add a README row); link
  to `docs/post-setup.md`.
- **docs/post-setup.md**: plain, terminal-readable markdown (short headings,
  code blocks) for manual logins done on first need: `az login`, Claude Code
  login (first `claude` launch), `az acr login --name <registry>`. Also: on
  WSL the Nerd Font must be installed on the Windows side for Windows Terminal
  to use it.

## Left to the builder

- Exact helper function names and output formatting.
- Exact pinned versions (latest stable at build time).
- The kubectl package/provide name, and how node is put on PATH for
  non-interactive shells.
- Verification approach. Minimum: `shellcheck` clean on all scripts,
  `claude/hooks/tests.sh` passing, and an end-to-end run of both scripts on a
  fresh Fedora 45 (e.g. a new WSL distro), then a second run of each to prove
  idempotency.
- A final pass grepping the repo for employer references before each commit.
