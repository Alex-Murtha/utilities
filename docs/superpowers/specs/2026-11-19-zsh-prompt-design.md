# Zsh prompt and plugins — design

Date: 2026-11-19. Extends `2026-11-18-bootstrap-design.md`, which left the
zsh framework, plugins and prompt out until the user had evaluated options.

## Intent

After trying stock Oh My Zsh and other options, the user prefers the prompt
from the old chezmoi `dotfiles` repo. `install.sh` should set up that prompt
and the zsh plugins that repo used, so a fresh machine ends up with the same
interactive shell.

## Goals

- Powerlevel10k with the user's hand-written config (ported unchanged apart
  from comments that refer to chezmoi).
- Oh My Zsh as the plugin loader, with the old plugin list.
- `zsh-autosuggestions` and `zsh-syntax-highlighting`.
- Same guarantees as the rest of `install.sh`: idempotent, atomic per step,
  failures recorded and not fatal, second run skips everything.

## Non-goals

- `you-should-use` and the `ll` / `gs` aliases (dropped by the user).
- Installing Docker. The `docker` and `docker-compose` plugins stay because
  Docker comes from Windows and is available inside WSL2.
- Cleaning lines outside the marker block in an existing `~/.zshrc` (for
  example a stock Oh My Zsh template). The user removes those by hand.
- A `~/.p10k.zsh` in `$HOME`, or support for `p10k configure`.

## Approaches

1. **Oh My Zsh + p10k, as in the old repo (chosen by the user).** Eight of the
   old plugins only exist inside Oh My Zsh, so this reproduces the old shell.
2. **p10k with no framework.** Fewer moving parts, but loses the git and
   kubectl aliases, double-Esc sudo, `extract` and coloured man pages unless
   they are rewritten by hand.

## Design

**Pins** (top of `install.sh`, listed in `docs/tools.md`):

- `OMZ_REF` — an Oh My Zsh commit SHA (it has no release tags).
- `P10K_REF=v1.20.0` — the tag the old repo used.

**dnf:** add `zsh-autosuggestions` and `zsh-syntax-highlighting`.

**New step `step_zsh`,** after the font step:

- Oh My Zsh into `~/.oh-my-zsh` at `OMZ_REF`. Already at that commit: skip.
  Existing git checkout at another commit: fetch the pinned commit and check
  it out. Missing: clone into a temp dir next to the target, then move into
  place. Exists but is not a git checkout: fail the step.
- Powerlevel10k into `~/.oh-my-zsh/custom/themes/powerlevel10k` at
  `P10K_REF`, same rules. It runs after Oh My Zsh and is skipped if that
  failed.

**`zsh/p10k.zsh`** in this repo: the old `dot_p10k.zsh`. `~/.zshrc` sources
it from `~/code/utilities/zsh/p10k.zsh` (the checkout is already relied on
for `bin/`), so a `git pull` updates the prompt and nothing is copied into
`$HOME`.

**`snippets/zshrc`** (the marker block), in this order:

1. `ZSH`, `ZSH_THEME=""`, Oh My Zsh auto-update disabled (the commit is
   pinned), `plugins=(git sudo extract colored-man-pages docker
   docker-compose kubectl helm)`, source `oh-my-zsh.sh`.
2. Source the p10k theme, then `zsh/p10k.zsh`.
3. History, zoxide, nvm (as today).
4. `zsh-autosuggestions`, then `zsh-syntax-highlighting` last.

Every `source` is guarded by a readability check, so a partial install never
breaks the shell.

**Known behaviour:** p10k downloads its `gitstatusd` helper the first time an
interactive shell starts (its official install method); `install.sh` does not
pre-fetch it.

## Tests

- Unit: the clone-at-pin helper against local git repos (fresh clone, already
  at pin, wrong commit, not a git checkout).
- `tests/readme.test.sh`: the new pins and tool rows are in `docs/tools.md`.
- `tests/e2e.sh`: both checkouts are at their pins, and an interactive zsh
  starts with no errors and has p10k and the plugins loaded.

## Left to the builder

Helper names, exact wording of log lines, and how the e2e test drives an
interactive zsh.
