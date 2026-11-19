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

Every tool, its install source, and the version pins are listed in
[docs/tools.md](docs/tools.md).

## Shell prompt

`install.sh` sets up [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh) (for
plugins) and [powerlevel10k](https://github.com/romkatv/powerlevel10k) (for
the prompt), both pinned, plus `zsh-autosuggestions` and
`zsh-syntax-highlighting`. The prompt is configured by
[zsh/p10k.zsh](zsh/p10k.zsh), which `~/.zshrc` reads straight from the
clone: edit it there and open a new shell. Don't run `p10k configure`; it
writes a separate `~/.p10k.zsh` and offers to load it from `~/.zshrc`, which
would override the config in this repo.

- The first interactive shell downloads powerlevel10k's `gitstatusd` helper
  (its own installer), so it needs network access once.
- `install.sh` only manages the block between the `# >>> utilities >>>`
  markers in `~/.zshrc`. If the file already loads Oh My Zsh or sets a theme
  above that block (for example the stock Oh My Zsh template), delete those
  lines by hand, or Oh My Zsh is loaded twice.

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

## Code review (`/review-council`)

`install.sh` links `claude/skills/review-council` into `~/.claude/skills/`.
In Claude Code, `/review-council <PR URL | PR number | branch>` (no target
means the current branch) runs five read-only reviewers (product/Jira,
code, architect, security/Aikido, devil's advocate) on one Orca worktree of
the change. A second pass tries to disprove each finding, and the rest go
into one report.

- Reports and everything the run gathered go to
  `~/.cache/review-council/<repo>-<pr|branch>-<time>/` (`report.md`). They
  are never cleaned up automatically.
- An existing Orca worktree for the PR is reused. Otherwise one is created
  and kept afterwards.
- Posting to the PR is opt-in. You pick the findings and Comment or Request
  changes, then review every drafted comment (reword, drop or move any of
  them, in chat or in `post-drafts.md`) before saying to post. Each finding
  is its own comment, and it never approves.

Reviewer instructions live in `review/` and are agent-neutral, so other
agents can run them later. The helpers in `review/bin/` are tested by
`tests/review-*.test.sh`. Design:
[docs/superpowers/specs/2026-11-19-agent-code-review-design.md](docs/superpowers/specs/2026-11-19-agent-code-review-design.md).

## Adding a tool

Add it to `DNF_PACKAGES` or `BREW_FORMULAE` in `install.sh` (or write an
install function and call it from `step_installers`), add a row to the table
in [docs/tools.md](docs/tools.md), and run `bash tests/run.sh`;
`tests/readme.test.sh` fails if the table and `install.sh` disagree.

## Tests

`bash tests/run.sh` runs the unit tests. `bash tests/e2e.sh` runs
`install.sh` twice inside a Fedora container (it never touches the host);
`setup-interactive.sh` is covered by the unit tests with stubbed `gh` and
`bws`.
