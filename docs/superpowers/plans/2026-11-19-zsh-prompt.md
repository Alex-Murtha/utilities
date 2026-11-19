# Zsh Prompt and Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `install.sh` sets up Oh My Zsh, powerlevel10k with the user's config, and the old zsh plugins.

**Architecture:** One new helper in `install.sh` checks a git repo out at a pinned ref (clone in a temp dir then move, or fetch + checkout in place). A new `step_zsh` calls it twice. The prompt config lives in the repo and is sourced from the checkout by the `~/.zshrc` marker block.

**Tech Stack:** bash (`install.sh`, tests), zsh (snippets), git, docker (e2e only).

**Spec:** `docs/superpowers/specs/2026-11-19-zsh-prompt-design.md` (extends `2026-11-18-bootstrap-design.md`, whose constraints still apply).

## Global Constraints

- Fedora only; `install.sh` runs under `set -uo pipefail`, never `-e`.
- Idempotent: a second run reports nothing installed. Failures go through `try` into `FAILED`; they are not fatal.
- Atomic: nothing half-written at a final path (temp dir next to the target, then `mv`).
- No reference to the user's employer anywhere (code, comments, tests, docs, commit messages).
- Never modify lines outside the marker block of a dotfile.
- `OMZ_REF=c0140703a53eb0d22be44f7bac318d0baacc927c`, `P10K_REF=v1.20.0`.
- Plugins, exactly: `git sudo extract colored-man-pages docker docker-compose kubectl helm`. No `you-should-use`, no aliases.
- Every `source` in a snippet is guarded by a readability check.
- Do not commit unless the user asks.

## Review Focus

1. `~/.oh-my-zsh` already exists at another commit (the user's machine today) — it is moved to the pin, not re-cloned and not failed.
2. `~/.oh-my-zsh` exists but is not a git checkout — the step fails with a clear warning and the directory is untouched.
3. Network failure mid-clone — nothing is left at the target path.
4. A shell started before `install.sh` finishes, or with p10k missing — `~/.zshrc` loads without errors.
5. An existing `~/.oh-my-zsh/custom` (user's own plugins) survives a move to the pin.

Tests for 1, 2, 3 and 5 are in Task 1; 4 is in Task 2.

---

### Task 1: `git_checkout_at` helper and `step_zsh`

**Files:**
- Modify: `install.sh` (pins block, `DNF_PACKAGES`, helpers section, steps, `main`)
- Create: `tests/git-checkout-at.test.sh`

**Interfaces:**
- Produces: `git_checkout_at <label> <url> <ref> <dir>` — `ref` is a 40-hex commit SHA or a tag name. Returns 0 and appends `<label>` to `SKIPPED` when `<dir>` is a git checkout whose `HEAD` is `<ref>`; otherwise brings it to `<ref>` (detached), appends to `INSTALLED`, returns 0. Returns 1 with a `warn` on any failure.
- Produces: `step_zsh`, globals `OMZ_REF`, `P10K_REF`, `OMZ_DIR="$HOME/.oh-my-zsh"`.

- [ ] **Step 1: Write the failing test** `tests/git-checkout-at.test.sh`, same shape as `tests/apply-snippet.test.sh` (source `lib.sh`, source `install.sh` with `UTILITIES_SOURCE_ONLY=1`, work in a `mktemp -d`). Build a local upstream repo with two commits, the first tagged `v1`. Cases:
  - fresh clone at the tip SHA: returns 0, `HEAD` is that SHA, label in `INSTALLED`
  - second call, same args: returns 0, label in `SKIPPED`, `INSTALLED` unchanged
  - checkout at tip, called with ref `v1`: `HEAD` becomes the tagged commit, label in `INSTALLED`; an untracked file created under `<dir>/custom/` beforehand still exists
  - then called again with `v1`: `SKIPPED`
  - `<dir>` is a plain directory containing a file: returns 1, the file is still there
  - url that does not exist, `<dir>` absent: returns 1, `<dir>` does not exist, no `.*.XXXXXX` temp dir left beside it

- [ ] **Step 2: Run it** — `bash tests/git-checkout-at.test.sh` — expected: FAIL, `git_checkout_at: command not found`.

- [ ] **Step 3: Implement `git_checkout_at`** in the helpers section of `install.sh`. "At ref" means `git -C <dir> rev-parse HEAD` equals `git -C <dir> rev-parse -q --verify "<ref>^{commit}"`. Fetch with `--depth 1`; for a tag fetch `refs/tags/<ref>:refs/tags/<ref>` so the tag resolves locally afterwards. Fresh install: `git init` + fetch + checkout in `mktemp -d "<parent>/.<name>.XXXXXX"`, then `mv`; remove the temp dir on any failure. Use `-c advice.detachedHead=false`.

- [ ] **Step 4: Run it** — expected: all PASS.

- [ ] **Step 5: Wire it in.** Add the two pins to the pins block; add `zsh-autosuggestions zsh-syntax-highlighting` to `DNF_PACKAGES`; add:

```bash
step_zsh() {
  log "oh my zsh + powerlevel10k"
  try "oh my zsh" git_checkout_at "oh my zsh" https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_REF" "$OMZ_DIR" || return 0
  try powerlevel10k git_checkout_at "powerlevel10k $P10K_REF" https://github.com/romkatv/powerlevel10k.git \
    "$P10K_REF" "$OMZ_DIR/custom/themes/powerlevel10k"
}
```

  Call it in `main` between `step_font` and `step_snippets`.

- [ ] **Step 6: Verify** — `bash tests/run.sh`: `readme.test.sh` now fails only on the two missing dnf rows (fixed in Task 3); everything else passes. `shellcheck install.sh tests/git-checkout-at.test.sh` if shellcheck is installed.

### Task 2: prompt config and zshrc snippet

**Files:**
- Create: `zsh/p10k.zsh`
- Modify: `snippets/zshrc`
- Create: `tests/zshrc.test.sh`

**Interfaces:**
- Consumes: `~/.oh-my-zsh` and `~/.oh-my-zsh/custom/themes/powerlevel10k` from Task 1.

- [ ] **Step 1: Copy** `~/code/dotfiles/home/dot_p10k.zsh` to `zsh/p10k.zsh`. Change only comments that mention chezmoi, `~/.p10k.zsh` or the old install script so they describe this repo. No setting changes. `grep -ci chezmoi zsh/p10k.zsh` must print 0.

- [ ] **Step 2: Write the failing test** `tests/zshrc.test.sh`: with `HOME` set to an empty temp dir (nothing installed), `zsh -f -c 'source snippets/zshrc'` exits 0 with empty stderr; `zsh -n snippets/zshrc` and `zsh -n zsh/p10k.zsh` exit 0; the snippet contains the exact line `plugins=(git sudo extract colored-man-pages docker docker-compose kubectl helm)`; it does not contain `you-should-use` or `alias `; the line number of `zsh-syntax-highlighting.zsh` is the largest of all `source` lines.

- [ ] **Step 3: Run it** — expected: FAIL on the plugins line.

- [ ] **Step 4: Rewrite `snippets/zshrc`** in the order the spec gives: Oh My Zsh block (`ZSH`, `ZSH_THEME=""`, `zstyle ':omz:update' mode disabled`, `plugins=(...)`, guarded source); p10k theme then `$HOME/code/utilities/zsh/p10k.zsh`, both guarded, config only when the theme loaded; the existing history / zoxide / nvm lines unchanged; `/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh` then `/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`, guarded.

- [ ] **Step 5: Run it** — `bash tests/zshrc.test.sh` — expected: all PASS.

### Task 3: docs and end-to-end

**Files:**
- Modify: `docs/tools.md`, `README.md`, `tests/readme.test.sh`, `tests/e2e.sh`, `docs/superpowers/specs/2026-11-18-bootstrap-design.md`

- [ ] **Step 1: Extend the tests first.** `tests/readme.test.sh`: add `oh-my-zsh powerlevel10k` to the installer-row loop and `"$OMZ_REF" "$P10K_REF"` to the pins loop. `tests/e2e.sh`, after the existing assertions:
  - `git -C ~/.oh-my-zsh rev-parse HEAD` equals `OMZ_REF` (source `install.sh` with `UTILITIES_SOURCE_ONLY=1` on the host to read the pins)
  - `git -C ~/.oh-my-zsh/custom/themes/powerlevel10k describe --tags --exact-match` equals `P10K_REF`
  - an interactive zsh (`zsh -ic`, clean env as `in_zsh`, `TERM=xterm-256color`) prints `1` for each of `$+functions[p10k]`, `$+functions[_zsh_autosuggest_start]`, `$+functions[_zsh_highlight]`, `$+aliases[gst]`, `$+aliases[k]`, and its stderr is empty

- [ ] **Step 2: Run** `bash tests/run.sh` — expected: `readme.test.sh` fails on the new rows and pins.

- [ ] **Step 3: Docs.** `docs/tools.md`: dnf rows for the two packages; rows `oh-my-zsh` (git checkout at pinned commit, `~/.oh-my-zsh`, auto-update off) and `powerlevel10k` (git checkout at tag, config in `zsh/p10k.zsh`); add both pins to the closing sentence. `README.md`: a short "Shell prompt" section — what is set up, that p10k fetches `gitstatusd` on first start, and that lines outside the utilities block in an existing `~/.zshrc` (such as a stock Oh My Zsh template) must be removed by hand. Old spec: one line under the "Zsh framework, plugins, prompt" non-goal pointing to the new spec; add `zsh/p10k.zsh` to its repo layout.

- [ ] **Step 4: Run** `bash tests/run.sh` — expected: all pass.

- [ ] **Step 5: Run** `bash tests/e2e.sh` (several minutes, needs docker) — expected: all PASS, including "run 2: nothing installed".
