# Fedora bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two bash scripts (`install.sh` non-interactive, `setup-interactive.sh` interactive) that turn a fresh Fedora install into the dev environment described in the spec, plus README and post-setup docs.

**Architecture:** One readable `install.sh` with helpers at the top, package arrays at the top, and step functions called from `main`. A source-only guard lets tests load the helpers without running anything. Snippets, Claude hooks, `secrets-refresh` and docs are plain files read from the `~/code/utilities` clone that `install.sh` makes.

**Tech Stack:** bash, dnf, Homebrew, jq, plain-bash test scripts (no bats), shellcheck via `docker run koalaman/shellcheck`, end-to-end runs in a `fedora:45` container via docker.

**Spec:** `docs/superpowers/specs/2026-11-18-bootstrap-design.md`

## Global Constraints

- **Public repo: no employer references anywhere** (code, comments, tests, docs, commit messages): no company/org names, work repo names, registry or subscription names, work email, secret names other than `CLONE_REPOS`.
- Fedora only. `install.sh` exits with a clear message if `/etc/os-release` `ID` is not `fedora`.
- Install source per tool is fixed by the spec's tables; no runtime fallbacks; no tools beyond the spec's list.
- No raw release-binary downloads except where that is the official method (only the Nerd Font).
- Marker lines are exactly `# >>> utilities >>>` and `# <<< utilities <<<`.
- Every file write: temp file in the target's directory, then `mv`.
- Repo clone URL: `https://github.com/Alex-Murtha/utilities.git`; clone path `~/code/utilities`.
- Secrets file `~/.config/secrets.env` (600); token file `~/.config/bws/token` (600, dir 700).
- Scripts use `#!/usr/bin/env bash` and `set -uo pipefail` (no `-e` in `install.sh`/`setup-interactive.sh`; `secrets-refresh` may use `-e`).
- shellcheck clean.

## Review Focus

1. A target dotfile that is a **symlink** (e.g. user's `.zshrc` → elsewhere) must be written through, leaving the link intact. Test in Task 1.
2. A target **without a trailing newline** must still get the marker block on its own line. Test in Task 1.
3. **Re-running after a snippet changed** must replace the block, not duplicate it, and keep user lines both before and after the block. Test in Task 1.
4. `~/.claude/settings.json` that is **missing** (create it) or **not valid JSON** (fail, leave file untouched). Test in Task 2.
5. `CLONE_REPOS` pasted in Bitwarden's web UI may carry **CRLF line endings, blank lines, `#` comments, surrounding whitespace**: all must be tolerated. Test in Task 4.

---

## File Structure

```
install.sh                    # Task 1 (helpers), Task 3 (steps)
setup-interactive.sh          # Task 4
bin/secrets-refresh           # Task 4
snippets/zshenv               # Task 3
snippets/zshrc                # Task 3
snippets/lazygit.yml          # Task 3
claude/hooks/*.sh             # Task 2 (ported from ~/code/dotfiles/claude/hooks)
claude/settings-hooks.json    # Task 2
tests/lib.sh                  # Task 1: assert helpers
tests/run.sh                  # Task 1: runs tests/*.test.sh + claude/hooks/tests.sh
tests/*.test.sh               # unit tests per task
tests/e2e.sh                  # Task 3: fedora:45 container run, twice
README.md, docs/post-setup.md # Task 5
```

---

### Task 1: install.sh skeleton, helpers, apply_snippet

**Files:**
- Create: `install.sh`, `tests/lib.sh`, `tests/run.sh`, `tests/apply-snippet.test.sh`
- Commit also: `docs/superpowers/specs/2026-11-18-bootstrap-design.md`, this plan

**Interfaces:**
- Produces (in `install.sh`, all usable after `UTILITIES_SOURCE_ONLY=1 source install.sh`):
  - `log <msg>`, `warn <msg>`, `die <msg>` (exit 1)
  - globals `INSTALLED=()`, `SKIPPED=()`, `FAILED=()`
  - `try <label> <cmd...>`: runs cmd; on non-zero appends label to `FAILED` and returns 1, else 0
  - `apply_snippet <snippet_file> <target_file>`: returns 0 and appends target to `INSTALLED` (changed) or `SKIPPED` (identical); returns 1 on error
  - `UTILITIES_DIR` default `$HOME/code/utilities` (overridable by env)
  - main guard: `[[ -n "${UTILITIES_SOURCE_ONLY:-}" ]] || main "$@"`; `main` is a stub in this task.
- `tests/lib.sh`: `assert_eq <label> <expected> <actual>`, `assert_contains <label> <file> <string>`, `assert_count <label> <file> <string> <n>`, `finish` (prints totals, exits non-zero on failures). Each test file makes its own `mktemp -d` sandbox and sets `HOME` to it.

- [ ] **Step 1: Write failing tests** in `tests/apply-snippet.test.sh`:
  - `creates missing target`: target absent → file == markers + snippet; parent dir created.
  - `appends to existing`: target `export A=1\n` → line 1 is `export A=1`, block follows.
  - `no trailing newline`: target `export A=1` (no `\n`) → `export A=1` and `# >>> utilities >>>` are on separate lines.
  - `idempotent`: apply twice → `assert_count` of `# >>> utilities >>>` is 1, second call appends to `SKIPPED`, file mtime/content unchanged.
  - `replaces changed block`: target has `before`, block(old), `after`; apply new snippet → contains `before`, `after`, new content, not old content, one start marker.
  - `writes through symlink`: target is symlink to `real` → after apply, target still `-L`, `real` contains block.
  - `preserves mode`: target mode 600 → still 600.
- [ ] **Step 2:** `bash tests/apply-snippet.test.sh` → FAIL (install.sh missing).
- [ ] **Step 3:** Implement helpers and `apply_snippet` per the spec's marker-block algorithm (resolve symlinks with `readlink -f` before choosing the temp-file directory; strip the old block with awk; ensure a newline before appending; `cmp -s` for unchanged; `chmod --reference`).
- [ ] **Step 4:** `bash tests/run.sh` → all PASS. Shellcheck: `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable install.sh tests/*.sh` → no output.
- [ ] **Step 5: Commit** `feat: install.sh helpers and marker-block snippets` (include spec and plan).

---

### Task 2: Generic Claude Code hooks and settings merge

**Files:**
- Create: `claude/hooks/{no-full-test-suite,orca-worktrees,no-secret-material,prettier,azure-guardrails}.sh`, `claude/hooks/tests.sh`, `claude/settings-hooks.json`, `tests/claude.test.sh`
- Modify: `install.sh` (add two functions)

**Interfaces:**
- Consumes: `try`, `log`, `INSTALLED/SKIPPED` from Task 1.
- Produces in `install.sh`:
  - `link_claude_hooks <repo_hooks_dir> <claude_dir>`: makes `<claude_dir>/hooks` a symlink to `<repo_hooks_dir>`; correct link → SKIPPED; other symlink → replaced; real dir → moved to `hooks.bak.<YYYYmmddHHMMSS>` first.
  - `merge_claude_settings <hooks_json> <settings_file> <hooks_dir>`: replaces `.hooks` with the template's `.hooks` after substituting the literal placeholder `__HOOKS_DIR__` with `<hooks_dir>`; keeps all other keys; creates the file (`{}` base) if missing; returns 1 and leaves file untouched if existing file is invalid JSON.

- [ ] **Step 1: Port hooks.** Copy `no-full-test-suite.sh` and `orca-worktrees.sh` from `~/code/dotfiles/claude/hooks/` unchanged. Port `tests.sh`, replacing every registry/subscription name with placeholders (`myregistry`, `other-sub`) and changing every azure-guardrails expectation to `ask`; drop the "reason names az acr login -n …" loop in favour of one asserting the reason mentions `az acr repository list`. Add cases:
  - no-secret-material: `cat ~/.config/secrets.env` → deny; `cat ~/.config/bws/token` → deny; `bws secret list` → deny; `cat license.lic` → deny; `cat README.md` → quiet.
  - prettier (PostToolUse JSON `{"tool_input":{"file_path":…}}`): file under a temp project with `.prettierrc` and a fake executable `node_modules/.bin/prettier` that records its args → fake called with `--write --ignore-unknown <file>`; file in a dir with no prettier config → fake not called, exit 0; config present but no `node_modules/.bin/prettier` → silent exit 0.
- [ ] **Step 2:** `bash claude/hooks/tests.sh` → new cases FAIL.
- [ ] **Step 3:** Rewrite `no-secret-material.sh` (patterns: `\.config/secrets\.env`, `\.config/bws/`, `bws +secret`, `\.lic\b`; generic reason), `prettier.sh` (walk up from `dirname $f` to `/`, stop at first dir containing `.prettierrc*`, `prettier.config.*`, or `package.json` with a `prettier` key via `jq -e 'has("prettier")'`; run its `node_modules/.bin/prettier` if executable), `azure-guardrails.sh` (same two regexes, both `ask`, generic reasons: ARM vs data-plane, suggest `az acr repository list --name <registry> -o none` and `az acr login -n <registry>`, don't switch subscriptions to fix lookups). Comments must not name any company resource.
- [ ] **Step 4:** `bash claude/hooks/tests.sh` → all PASS.
- [ ] **Step 5: Write failing tests** `tests/claude.test.sh`:
  - `link fresh`, `link idempotent` (second → SKIPPED), `link replaces wrong symlink`, `link backs up real dir` (a `hooks.bak.*` dir exists with original contents).
  - `merge creates settings`: missing file → `jq -r '.hooks.PreToolUse[0].hooks[0].command'` == `<hooks_dir>/no-secret-material.sh`.
  - `merge keeps other keys`: existing `{"model":"x","hooks":{"Old":[]}}` → `.model == "x"`, `.hooks.Old` absent.
  - `merge rejects invalid json`: file `{not json` → returns 1, file content unchanged.
- [ ] **Step 6:** Write `claude/settings-hooks.json` (`{"hooks":{…}}`, wiring exactly as the spec's hook table, `statusMessage`s as in the old template, paths `__HOOKS_DIR__/<name>.sh`) and implement both functions. `bash tests/run.sh` → all PASS; shellcheck clean.
- [ ] **Step 7: Commit** `feat: generic Claude Code hooks and settings merge`.

---

### Task 3: install.sh steps, snippets, end-to-end container test

**Files:**
- Modify: `install.sh`
- Create: `snippets/zshenv`, `snippets/zshrc`, `snippets/lazygit.yml`, `tests/e2e.sh`

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces: `main` running, in order, `prelude`, `step_dnf`, `step_clone`, `step_brew`, `step_installers`, `step_font`, `step_snippets`, `step_claude`, `summary`. Arrays at top: `DNF_PACKAGES`, `BREW_FORMULAE`. Pins at top: `NVM_VERSION`, `NERD_FONTS_VERSION`, `NODE_MAJOR=26`, `DOTNET_CHANNELS=(11.0 10.0)`.

Values, all from the spec:
- `DNF_PACKAGES`: zsh git git-lfs gh curl wget unzip gcc fontconfig nano libatomic python3 python3-pip fzf jq zoxide fastfetch tree azure-cli helm k9s yq lazygit golang, plus the kubectl provide — check `dnf repoquery --whatprovides kubectl` on Fedora 45 and use the provide/package that tracks the newest client.
- `BREW_FORMULAE`: k3d devspace earthbuild/tap/earth.
- `prelude`: refuse root; Fedora check; `sudo -v`; keep-alive loop `while sleep 60; do sudo -n true; done &` killed by `trap … EXIT`.
- `step_dnf` also: `sudo usermod -s "$(command -v zsh)" "$USER"` if the login shell isn't zsh; `git lfs install`; `git config --global pull.rebase true`.
- `step_clone`: clone if missing; else `git -C … pull --ff-only`, on failure `warn` and continue with the existing checkout.
- `step_brew`: official installer with `NONINTERACTIVE=1` if `/home/linuxbrew/.linuxbrew/bin/brew` is missing, then `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`; each formula installed only if `brew list --formula --versions <name>` fails.
- `step_dnf` and `step_clone` failures call `die` (later steps depend on them); every other install goes through `try`.
- `step_installers`: nvm (`PROFILE=/dev/null`, `https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh`), `nvm install $NODE_MAJOR && nvm alias default $NODE_MAJOR`, corepack (`npm install -g corepack && corepack enable`) only if `corepack` missing; dotnet-install.sh with `--install-dir ~/.dotnet --no-path`, `--channel 11.0` then `--channel 10.0 --skip-non-versioned-files`, skipped per channel when `~/.dotnet/dotnet --list-sdks` already has a `<channel major>.` SDK; `az bicep install` if `~/.azure/bin/bicep` missing else `az bicep upgrade`; bws via `curl -fsSL https://bws.bitwarden.com/install | sh` if `bws` missing; Claude via `curl -fsSL https://claude.ai/install.sh | bash` if `~/.local/bin/claude` missing.
- `step_font`: `https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_VERSION/CodeNewRoman.zip` → `~/.local/share/fonts/NerdFonts`, stamp `.version`, `fc-cache -f`.
- `step_snippets`: the three `apply_snippet` calls from the spec.
- `step_claude`: `link_claude_hooks "$UTILITIES_DIR/claude/hooks" ~/.claude`, `merge_claude_settings "$UTILITIES_DIR/claude/settings-hooks.json" ~/.claude/settings.json ~/.claude/hooks`.
- `summary`: counts and lists of INSTALLED/SKIPPED/FAILED, next-step line, `exit 1` if FAILED non-empty.
- `snippets/zshenv`: exactly the spec's list. Node on PATH for non-interactive shells: read `~/.nvm/alias/default`, resolve to the newest `~/.nvm/versions/node/v<major>.*` dir, prepend its `bin`. Guard every source/eval with existence checks so a partial install never breaks the shell. `typeset -U path`.
- `snippets/zshrc`: history settings, zoxide init, nvm load + completion. Nothing else.
- `UTILITIES_REF` env var (default `main`) controls the branch `step_clone` checks out; `UTILITIES_REPO_URL` overridable — both for e2e only.

- [ ] **Step 1: Write `tests/e2e.sh`** (the failing test): builds a throwaway `fedora:45` container with `sudo` installed and a non-root `tester` user with NOPASSWD sudo; mounts the working tree read-only at `/src`; runs `UTILITIES_REPO_URL=/src UTILITIES_REF=<current branch> bash /src/install.sh` as `tester` **twice**. Asserts: run 1 exit 0; run 2 exit 0 with empty FAILED and every install line SKIPPED; then inside `zsh -c` (non-interactive): `command -v git gh az kubectl helm k9s yq lazygit go node npm corepack dotnet bws claude k3d devspace earth` all succeed, `dotnet --list-sdks` shows a 10.x and an 11.x SDK, `node --version` starts with `v26`, `test -x ~/.azure/bin/bicep`; `grep -c '# >>> utilities >>>' ~/.zshenv` == 1; `~/.claude/hooks` is a symlink; `getent passwd tester` shell is zsh. Prints PASS/FAIL per assertion.
- [ ] **Step 2:** `bash tests/e2e.sh` → FAIL (steps not implemented).
- [ ] **Step 3:** Implement the snippets and the step functions per the values above.
- [ ] **Step 4:** `bash tests/run.sh` (unit) → PASS; shellcheck clean; `bash tests/e2e.sh` → all PASS (this takes several minutes; Homebrew's first install is slow).
- [ ] **Step 5: Commit** `feat: install.sh steps and snippets`.

---

### Task 4: secrets-refresh and setup-interactive.sh

**Files:**
- Create: `bin/secrets-refresh`, `setup-interactive.sh`, `tests/secrets-refresh.test.sh`, `tests/setup-interactive.test.sh`

**Interfaces:**
- Consumes: `log/warn/try` — `setup-interactive.sh` sources `install.sh` with `UTILITIES_SOURCE_ONLY=1` from its own directory; it has its own source-only guard `SETUP_SOURCE_ONLY`.
- Produces:
  - `bin/secrets-refresh`: env overrides `BWS_TOKEN_FILE` (default `~/.config/bws/token`), `SECRETS_FILE` (default `~/.config/secrets.env`). Exit 0 on success, 1 on any failure leaving `SECRETS_FILE` untouched. Never prints values.
  - In `setup-interactive.sh`: `parse_repo_list` (stdin → one clean `owner/repo` per line on stdout), `clone_repos <dest_root>` (reads list from stdin, `gh repo clone owner/repo <dest_root>/<repo>` unless dir exists), `set_git_identity` (only sets unset keys, from `gh api user`), `save_bws_token <token_file>`, `fetch_clone_list` (stdout: value of `CLONE_REPOS` via `bws secret list -o json` + jq; empty + warn if absent), `main` per the spec's six steps ending with `cat "$UTILITIES_DIR/docs/post-setup.md"`.

- [ ] **Step 1: Write failing tests.** Tests put stub `bws`/`gh` executables on `PATH` that print canned JSON / record their args to a log file.
  - `secrets-refresh writes file`: stub returns `[{"key":"A","value":"x y"},{"key":"B","value":"it's"},{"key":"CLONE_REPOS","value":"o/r"}]` → file mode 600, sourcing it gives `A="x y"`, `B="it's"`, and `CLONE_REPOS` absent.
  - `secrets-refresh keeps file on bws failure`: stub exits 1 → exit 1, existing file unchanged.
  - `secrets-refresh rejects bad key`: key `BAD-NAME` → exit 1, file unchanged.
  - `secrets-refresh missing token`: no token file → exit 1 with message naming the token path.
  - `parse_repo_list`: input `"o/a\r\n\n  # c\n o/b \n"` → output exactly `o/a\no/b\n`.
  - `clone_repos`: list `o/a`, `o/b` with `<dest>/b` pre-existing → gh log shows exactly one call `repo clone o/a <dest>/a`.
  - `set_git_identity`: stub `gh api user` → `{"login":"u","id":7,"name":null,"email":null}` and empty git config (`GIT_CONFIG_GLOBAL` temp file) → `user.name` == `u`, `user.email` == `7+u@users.noreply.github.com`; pre-set `user.email` stays unchanged.
  - `save_bws_token`: writes token, file mode 600, dir mode 700; existing file → not overwritten.
- [ ] **Step 2:** `bash tests/run.sh` → new tests FAIL.
- [ ] **Step 3:** Implement `bin/secrets-refresh` (port of `~/code/dotfiles/home/dot_local/bin/executable_secrets-refresh.tmpl` without project id, excluding `CLONE_REPOS`, new paths, generic wording) and `setup-interactive.sh` (token prompt with `read -rs` from `/dev/tty`; `gh auth login` only if `gh auth status` fails).
- [ ] **Step 4:** `bash tests/run.sh` → all PASS; shellcheck clean.
- [ ] **Step 5: Commit** `feat: secrets-refresh and setup-interactive.sh`.

---

### Task 5: README, post-setup doc, final verification

**Files:**
- Create: `docs/post-setup.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: final arrays/pins in `install.sh` (the README table must match them exactly).

- [ ] **Step 1: Write `docs/post-setup.md`**: terminal-readable (short `##` headings, fenced commands, lines ≤ 80 chars): `az login`; Claude Code login on first `claude` launch; `az acr login --name <registry>`; WSL note that the Nerd Font must be installed on Windows for Windows Terminal.
- [ ] **Step 2: Write `README.md`** with the sections the spec's Docs section lists: what it is; the one-liner `curl -fsSL https://raw.githubusercontent.com/Alex-Murtha/utilities/main/install.sh | bash`; then `~/code/utilities/setup-interactive.sh`; a **Tool | Source | Script** table covering every `DNF_PACKAGES`/`BREW_FORMULAE` entry and every official installer with links; files touched and the marker convention; generic one-time Bitwarden setup (Secrets Manager project, secret name = env var name, `CLONE_REPOS` = one `owner/repo` per line, machine account with read access, `secrets-refresh` to rotate); how to add a tool; link to `docs/post-setup.md`.
- [ ] **Step 3: Consistency check:** every package in `install.sh` arrays/installers appears in the README table and vice versa (a short `tests/readme.test.sh` that extracts `DNF_PACKAGES` and `BREW_FORMULAE` by sourcing `install.sh` and greps the README for each). `bash tests/run.sh` → PASS.
- [ ] **Step 4: Employer-reference sweep** across the whole tree and `git log`: grep (case-insensitive) for the employer and org names known from `~/code/dotfiles` and the user's email domain — run the grep locally only; the pattern itself must never be written into this repo. Expected: no matches.
- [ ] **Step 5: Final verification:** `bash tests/run.sh`, shellcheck on all scripts, `bash tests/e2e.sh` → all PASS.
- [ ] **Step 6: Commit** `docs: README and post-setup guide`.
