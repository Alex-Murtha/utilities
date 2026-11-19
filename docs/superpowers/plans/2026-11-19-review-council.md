# Review Council Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/review-council <target>` runs five read-only reviewers on a PR or local branch, verifies their findings, writes one merged report, and can post chosen findings to the PR (phase 1: Claude only).

**Architecture:** A Claude Code skill (`claude/skills/review-council/SKILL.md`) is the coordinator. Everything deterministic lives in small bash helpers under `review/bin/` with shell tests: target parsing, worktree check, context bundle, findings validation, verdict application, and posting. Reviewer, verifier and synthesizer instructions are agent-neutral Markdown under `review/`, so phase 2 can hand the same files to Orca workers.

**Tech Stack:** bash, git, gh, jq; Claude Code skill + subagents; Orca CLI (`orca-ide`); Atlassian MCP and Aikido MCP (called by the coordinator only).

**Spec:** `docs/superpowers/specs/2026-11-19-agent-code-review-design.md`

## Global Constraints

- The repo is **public**: no employer, company, work repo, Jira site or org names anywhere (code, tests, fixtures, docs, commit messages). Test fixtures use `acme/widgets`, `ABC-123`.
- Helpers: `#!/usr/bin/env bash`, `set -uo pipefail` (not `-e`), depend only on git, gh, jq. Errors go to stderr with a non-zero exit; machine output goes to stdout as JSON.
- Helpers never modify a worktree: no checkout, reset, stash, pull, add, commit. `git fetch` (refs only) is allowed.
- Raw `git worktree add|remove|…` is blocked by the user's hook; worktrees are made with the Orca CLI. Resolve it as `${ORCA_CLI_COMMAND:-orca-ide}`; never bare `orca` (on Linux it can start the GNOME screen reader).
- Never post an `APPROVE` review. Posting events are exactly `COMMENT` or `REQUEST_CHANGES`.
- Reviewers never run the full test suite (the user's `no-full-test-suite` hook enforces this too).
- Run directory: `${REVIEW_COUNCIL_CACHE:-$HOME/.cache/review-council}/<repo>-<pr-N|branch>-<YYYYmmdd-HHMMSS>/`. Never cleaned automatically.
- Tests follow `tests/*.test.sh` style (`source tests/lib.sh`, `mktemp -d` sandbox, `finish`); `tests/run.sh` picks them up automatically.
- Work happens on branch `review-council`; one commit per task.

## Review Focus

1. **Branch names with slashes** (`feature/ABC-123-foo`): the run dir name must be a single safe path segment (`/` → `-`), and the Jira key must still be found. Tests are in Task 2.
2. **A PR whose diff is only lockfiles or generated files**: `diff.patch` ends up empty, and `dropped.txt` lists the files. The coordinator must report "nothing reviewable" instead of starting reviewers. Tests are in Task 2; the coordinator rule is in Task 6.
3. **Reviewer output that isn't valid JSON or breaks the schema** (prose around the JSON, unknown severity, a missing `file`): validation fails with a message the coordinator can send back to the reviewer for one retry. Tests are in Task 3.
4. **A target that is a bare number vs a branch called `123`**: digits always mean a PR, and `--branch 123` forces a branch. Tests are in Task 1.
5. **Posting a finding whose line isn't in the diff**: GitHub rejects the whole review. `post-review` moves comments without a usable line into the review body instead of failing. Tests are in Task 5.

---

### Task 1: Target parsing and worktree check

**Files:**
- Create: `review/bin/parse-target`, `review/bin/check-worktree`
- Test: `tests/review-target.test.sh`

**Interfaces:**
- Produces: `parse-target [--branch] [<target>]` → stdout JSON, exit 0; exit 2 with a stderr message for an unrecognised URL.
  - `https://github.com/<owner>/<repo>/pull/<n>` (with an optional trailing `/files` etc. or a query string): `{"kind":"pr","owner":"…","repo":"…","number":N,"url":"https://github.com/<owner>/<repo>/pull/<n>"}`
  - `^[0-9]+$`, or `#123`, without `--branch`: `{"kind":"pr","owner":null,"repo":null,"number":N,"url":null}`
  - anything else, or with `--branch`: `{"kind":"branch","branch":"<target>"}`
  - empty: `{"kind":"branch","branch":null}` (meaning the current branch)
- Produces: `check-worktree <path> <expected_sha>` → stdout JSON `{"head":"<sha>","matches":bool,"dirty":bool,"untracked":bool}`, exit 0; exit 2 if `<path>` isn't a git work tree.

- [ ] **Step 1: Write failing tests** in `tests/review-target.test.sh`, using `assert_eq` with `jq -r` on the output:
  - PR URL `https://github.com/acme/widgets/pull/42` gives kind `pr`, owner `acme`, repo `widgets`, number `42`.
  - Same URL with `/files?w=1` appended gives number `42` and the canonical `url`.
  - `42` and `#42` give kind `pr` and number `42`.
  - `--branch 42` gives kind `branch` and branch `42`.
  - `feature/ABC-123-foo` gives kind `branch` with the branch unchanged.
  - No argument gives `.branch` as `null`.
  - `https://gitlab.com/x/y/merge_requests/1` exits with code 2.
  - For `check-worktree`, use a temp repo with one commit:
    - clean, at that sha: `matches` true, `dirty` false.
    - a different sha: `matches` false.
    - a modified tracked file: `dirty` true.
    - a new untracked file: `untracked` true and `dirty` false.
    - a non-repo directory: exits with code 2.
- [ ] **Step 2: Run** `bash tests/review-target.test.sh`. Expected: FAIL (scripts missing).
- [ ] **Step 3: Implement both scripts** (`chmod +x`). Build the JSON with `jq -n`; `dirty` comes from `git status --porcelain --untracked-files=no`.
- [ ] **Step 4: Run** `bash tests/review-target.test.sh`. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(review): parse review targets and check worktree state`.

### Task 2: Context bundle (`gather-context`)

**Files:**
- Create: `review/bin/gather-context`
- Test: `tests/review-gather-context.test.sh` (with a `gh` stub on `PATH`)

**Interfaces:**
- Consumes: nothing from Task 1 (the coordinator passes the resolved values in).
- Produces: `gather-context --worktree <path> [--pr <number>]`. It creates the run directory, prints its absolute path on stdout, and exits 0. Exit 1 means git or gh failed (with a stderr message). Inside the run directory, `context/` contains:
  - `meta.json`: `{"kind":"pr"|"branch","repo":"<name>","worktree":"<abs>","branch":"<name>","head_sha":"…","base_ref":"…","merge_base":"…","jira_key":"ABC-123"|null,"pr":null|{"number","url","title","body","author","labels":[…],"head_sha","base"}}`
  - `diff.patch`: the filtered diff, which may be empty.
  - `files.txt`: `git diff --name-status` for the filtered set.
  - `dropped.txt`: the excluded paths, one per line.
  - `untracked.txt`: branch mode only.
  - `conventions.txt`: paths of `CLAUDE.md`, `AGENTS.md` and `.github/copilot-instructions.md` that exist at the worktree root.
  - PR mode only: `checks.json` (from `gh pr checks <n> --json name,state,link`) and `comments.json` (from `gh pr view <n> --json comments,reviews`).
- The run directory name is `<repo>-pr-<n>-<ts>` or `<repo>-<branch with / → ->-<ts>`. `<repo>` is the basename of `git rev-parse --show-toplevel`'s common dir parent, or for PRs the repo name from gh.

Rules:
- **Base.** For PRs, the base is `baseRefName` from `gh pr view <n> --json number,url,title,body,author,labels,headRefOid,baseRefName,headRefName`. For branches, it is `git symbolic-ref --short refs/remotes/origin/HEAD` with `origin/` stripped, falling back to `main`. Run `git fetch origin <base>`, then `merge_base=$(git merge-base origin/<base> HEAD)`.
- **Diff.** In PR mode, diff `merge_base..HEAD`. In branch mode, diff from `merge_base` to the working tree (`git diff <merge_base>`), which includes uncommitted changes.
- **Excluded paths** (git pathspec `:(exclude,glob)`): `**/package-lock.json`, `**/yarn.lock`, `**/pnpm-lock.yaml`, `**/*.lock`, `**/go.sum`, `**/*.min.js`, `**/*.min.css`, `**/*.map`, `**/*.pb.go`, `**/*_pb2.py`, `**/*.generated.*`, `**/dist/**`, `**/build/**`, `**/vendor/**`, `**/node_modules/**`, `**/third_party/**`.
- **Jira key.** The first match of `[A-Z][A-Z0-9]+-[0-9]+`, searched in order: branch name, PR title, PR body.

- [ ] **Step 1: Write failing tests.** Build a sandbox origin repo with `main`, clone it, and on branch `feature/ABC-123-foo` commit a change to `src/a.sh` and `package-lock.json`. Then make an uncommitted edit to `src/b.sh` and add an untracked file `new.txt`. Export `REVIEW_COUNCIL_CACHE=$SANDBOX/cache`. Branch-mode cases:
  - The printed dir exists under the cache and its basename starts with `widgets-feature-ABC-123-foo-`.
  - `jira_key` is `ABC-123`.
  - `diff.patch` contains `src/a.sh` and `src/b.sh`, and does not contain `package-lock.json`.
  - `dropped.txt` contains `package-lock.json`.
  - `untracked.txt` contains `new.txt`.
  - `meta.json` `.kind` is `branch`.
  - A commit that only touches `yarn.lock` gives an empty `diff.patch` and exit 0.

  PR mode uses a stub `gh` in `$SANDBOX/bin`. It echoes fixture JSON for `pr view` (title `Fix ABC-9 crash`, `baseRefName` `main`, `headRefOid` equal to the clone's HEAD) and for `pr checks` / `pr view --json comments,reviews`. Cases:
  - The basename starts with `widgets-pr-7-`.
  - `jira_key` is `ABC-123`, because the branch name wins over the title.
  - `checks.json` is valid JSON.
  - `.pr.number` is `7`.
- [ ] **Step 2: Run** `bash tests/review-gather-context.test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `review/bin/gather-context` following the rules above.
- [ ] **Step 4: Run** the test again. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(review): gather-context builds the review bundle`.

### Task 3: Findings schema, validation, verdicts

**Files:**
- Create: `review/findings-schema.md`, `review/bin/validate-findings`, `review/bin/apply-verdicts`
- Test: `tests/review-findings.test.sh`, fixtures in `tests/fixtures/review/`

**Interfaces:**
- Produces: the reviewer output format, which `findings-schema.md` documents with one full example per reviewer:

```json
{
  "reviewer": "product|code|architect|security|devils-advocate",
  "model": "claude",
  "summary": "2-5 sentences",
  "findings": [
    {"id": "<reviewer>-<n>", "severity": "blocker|major|minor|nit",
     "confidence": "high|medium|low", "file": "path/in/repo", "line": 12,
     "title": "...", "evidence": "...", "suggestion": "..."}
  ],
  "extras": {}
}
```
  `line` may be `null`, and `file` may be `null` only for a whole-PR finding. `extras` depends on the reviewer:
  - product: `{"card": "ABC-123"|null, "ac_source": "card|inferred|none", "requirements": [{"requirement","status":"met|not_met|drift_documented|drift_undocumented","where"}]}`
  - security: `{"aikido": {"pr_check": "passed|failed|pending|missing|n/a", "scan": "clean|issues|not_scanned", "notes": "..."}}`
  - devils-advocate: `{"alternatives": [{"approach","strongest_argument","why_pr_may_still_win"}]}`, with at most 3 entries
  - code and architect: `{}`
- Produces: `validate-findings <file>` exits 0 when valid. Otherwise it exits 1 and prints one problem per line to stdout, ready to send back to the reviewer. If the file holds prose plus one fenced or bare JSON object, it extracts the object, rewrites the file to just the JSON, and validates that.
- Produces: `apply-verdicts <review.json> <verdicts.json>` prints the review JSON with every finding whose verdict is `refuted` removed, and a `verdict` and `verdict_reason` added to each remaining finding. The verdicts file looks like `[{"id","verdict":"confirmed|plausible|refuted","reason"}]`. A finding with no verdict is kept with verdict `unverified`.

- [ ] **Step 1: Write failing tests** with fixtures `valid-code.json`, `valid-product.json`, `bad-severity.json`, `missing-file-key.json`, `prose-wrapped.txt` and `verdicts.json`:
  - The valid fixtures pass.
  - The bad severity case fails, and its output contains `severity`.
  - A finding with no `file` key fails.
  - The prose-wrapped file passes, and the file afterwards is pure JSON (`jq -e .`).
  - A devils-advocate file with 4 alternatives fails.
  - `apply-verdicts` drops `code-2`, which is refuted, and keeps `code-1` with `.verdict == "confirmed"`.
  - A finding missing from the verdicts gets `unverified`.
- [ ] **Step 2: Run** `bash tests/review-findings.test.sh`. Expected: FAIL.
- [ ] **Step 3: Write `findings-schema.md` and implement both scripts** with jq. Validation checks the enums, required keys, types, and the per-reviewer `extras` shape.
- [ ] **Step 4: Run** the test again. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(review): findings schema, validation and verdicts`.

### Task 4: Reviewer, verifier and synthesizer instructions

**Files:**
- Create: `review/reviewers/{product,code,architect,security,devils-advocate}.md`, `review/verifier.md`, `review/synthesizer.md`
- Test: `tests/review-prompts.test.sh`

**Interfaces:**
- Consumes: `review/findings-schema.md` (Task 3) and the bundle layout (Task 2).
- Produces: each reviewer file has these exact `##` headings, in order: `Role`, `Inputs`, `Focus`, `Out of scope`, `Rules`, `Output`.
  - `Inputs` names `context/meta.json`, `context/diff.patch` and the worktree path, which the coordinator substitutes as `{{WORKTREE}}` and `{{RUN_DIR}}`.
  - `Output` says to return exactly one JSON object per `findings-schema.md`.
  - `Rules` carries the read-only rules word for word: never edit, stage, commit or check out; targeted tests, linters or type checks only, never the full suite; only report what you can point to in the code.

Content each file must cover (from the spec):
- **product:** read `context/jira.json`. If `ac_source` is `card`, use the card's AC section. Otherwise infer the criteria from the description; for a bug, that the error no longer happens. Mark which. Drift counts as documented only if the PR body explains it. If `jira.json` is missing or there's no card, use the PR description as the requirements and set `ac_source: none`.
- **code:** quality, simplicity, cohesion, naming, error handling, tests for the change, the repo's conventions files listed in `conventions.txt`. Style nits are `nit` severity.
- **architect:** fit with existing structure, boundaries and coupling, right scope, whether this is the right fix, and future cost. Read beyond the diff in the worktree.
- **security:** read `context/aikido.json`. A missing or failed PR check, or `not_scanned`, is itself a finding. Then do its own review: injection, authn/authz, secrets, unsafe deserialisation, SSRF, path traversal, dependency changes and logging of sensitive data.
- **devils-advocate:** the strongest case against the approach, failure scenarios, and up to 3 alternatives with honest counterpoints. No style comments.
- **verifier.md:** given one review JSON plus the worktree, try to disprove each finding by reading the code. Return the verdicts array (Task 3 format). `refuted` needs a concrete reason. Skip devils-advocate alternatives and product requirements.
- **synthesizer.md:** given `verified/*.json`, `context/` and the run details, write `report.md` with the spec's 9 sections in order:
  1. What this PR does
  2. Suggested verdict
  3. Where to focus
  4. Findings by severity
  5. JIRA requirements (marked inferred when inferred)
  6. Security and Aikido
  7. Alternatives
  8. Questions for the author (2–5)
  9. Run details

  Merge duplicates across reviewers and list every reviewer that raised each finding. Drop nits unless fewer than 3 other findings remain. The suggested verdict is one of `looks good` / `comment` / `needs changes`, and is never "approve".

- [ ] **Step 1: Write failing test** `tests/review-prompts.test.sh`:
  - For each reviewer file, assert each of the 6 headings with `assert_contains`.
  - Assert the Rules sentence `never edit, stage, commit or check out`.
  - Assert each file mentions `findings-schema.md`.
  - Assert that no file under `review/` matches `mcp__|Agent tool|subagent_type|TodoWrite` (they must stay agent-neutral).
  - Assert that `synthesizer.md` contains each of the 9 section titles.
- [ ] **Step 2: Run** `bash tests/review-prompts.test.sh`. Expected: FAIL.
- [ ] **Step 3: Write the seven files.** Keep each reviewer file under about 80 lines, and give one short example finding per reviewer.
- [ ] **Step 4: Run** the test again. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(review): reviewer, verifier and synthesizer instructions`.

### Task 5: Posting to the PR (`post-review`)

**Files:**
- Create: `review/bin/post-review`
- Test: `tests/review-post.test.sh` (with a `gh` stub that records its stdin and arguments)

**Interfaces:**
- Produces: `post-review --repo <owner/repo> --pr <n> --event COMMENT|REQUEST_CHANGES --body-file <md> --comments <json> [--dry-run]`.
  - `<json>` is `[{"path","line","body"}]`.
  - It fetches the PR's diff (`gh pr diff <n> --repo …`) and keeps an inline comment only when its `line` is on an added or context line of that file's right side. Every other comment is appended to the body under `### Other findings` as `` `path:line` — body ``.
  - It then sends one `gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews --input -` with `{"event","body","comments":[{"path","line","side":"RIGHT","body"}]}`.
  - `--dry-run` prints that payload instead of sending it.
  - Any event other than the two allowed (including `APPROVE`, in any case) exits 2 before any `gh` call.

- [ ] **Step 1: Write failing tests:**
  - `--event APPROVE` and `--event approve` both exit 2, and the stub log stays empty.
  - In dry-run with a fixture diff where `src/a.sh` adds lines 10–12:
    - the comment at line 11 stays inline with `side` `RIGHT`.
    - the comment at line 50 moves into the body under `### Other findings`.
    - `.event` is `REQUEST_CHANGES` when that event is given.
  - A non-dry run calls `gh api` exactly once, with `-X POST` and the `reviews` path.
- [ ] **Step 2: Run** `bash tests/review-post.test.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.** Parse the diff hunks (`@@ -a,b +c,d @@`) with awk to collect the right-side line numbers for each file.
- [ ] **Step 4: Run** the test again. Expected: all PASS.
- [ ] **Step 5: Commit** `feat(review): post-review posts Comment or Request changes, never Approve`.

### Task 6: Coordinator skill and install

**Files:**
- Create: `claude/skills/review-council/SKILL.md`
- Modify: `install.sh`: add `link_path <src> <dest>` (`link_claude_hooks` becomes a one-line call to it, with the same behaviour), and call `try "claude skill review-council" link_path "$UTILITIES_DIR/claude/skills/review-council" "$HOME/.claude/skills/review-council"` in `step_claude`
- Modify: `tests/claude.test.sh`: add cases for the skill link
- Modify: `README.md`: a short "Code review" section on what `/review-council` does and where reports go

**Interfaces:**
- Consumes: every script from Tasks 1–5 and the files from Task 4. The skill finds them through `REVIEW_DIR="$(cd "$(dirname "$(readlink -f ~/.claude/skills/review-council/SKILL.md)")/../../../review" && pwd)"`.
- Produces: `link_path <src> <dest>`. It creates the parent dir. A correct symlink adds `dest` to `SKIPPED`. A wrong symlink is replaced. A real file or dir is moved to `<dest>.bak.<timestamp>`. Anything it links is added to `INSTALLED`.

SKILL.md frontmatter: `name: review-council`. The description says to use it when the user asks to review a PR (URL or number) or a branch with the council, or types `/review-council`. The body sets out the coordinator steps, in order:
1. **Parse the target** with `parse-target`.
   - For a bare PR number, fill in owner and repo with `gh repo view --json owner,name`.
   - For a PR, get the head with `gh pr view <n> --json headRefOid,headRefName,isCrossRepository`.
2. **Find a worktree.**
   - PR: look for an existing one with `$ORCA reference find <url> --json`, then `$ORCA worktree list --json` matching `headRefName`. If none, run `$ORCA worktree create --repo path:<repo root> --name review-pr-<n> --pr <n> --reference <url> --json` with the flags that put it at the PR head (confirm with `--help` while building), no `--agent`.
   - Branch: use the worktree that has the branch checked out (`git worktree list --porcelain`). If none, create one the same way.
   - Run `check-worktree <path> <headRefOid>` for PRs. If it doesn't match, or the worktree is dirty, stop and ask the user: review as-is, or update the worktree first. Never touch it.
   - For a fork PR (`isCrossRepository`), first try the `$ORCA worktree create` flags. If they can't reach the fork's branch, tell the user and stop.
3. **Build the bundle.** Run `gather-context --worktree <path> [--pr <n>]`. If `diff.patch` is empty, report "nothing reviewable" with `dropped.txt` and stop.
4. **JIRA.**
   - If `meta.json.jira_key` is set, use the Atlassian MCP connector (not the deprecated one) to get the site (`getAccessibleAtlassianResources`; if there is more than one, ask the user) and the card with `getJiraIssue`.
   - Write `context/jira.json` as `{"key","summary","description","comments":[…],"parent_summary","ac_section":"<text>"|null}`. `ac_section` is the text under a heading or label matching `/^\s*(AC|Acceptance Criteria)\s*:?\s*$/i`, up to the next heading.
   - If fetching fails, write `{"key", "error":"<message>"}`.
5. **Aikido.**
   - Write `context/aikido.json` as `{"pr_check":"passed|failed|pending|missing|n/a","pr_comments":[…],"scan":"clean|issues|not_scanned","results":…,"error":null}`.
   - `pr_check` comes from `checks.json` entries whose name contains `aikido` (case-insensitive).
   - The scan uses the Aikido MCP `aikido_scan_paths` on the changed paths under the worktree. If it fails, set `not_scanned` and fill in `error`.
6. **Review.**
   - Start the 5 reviewers in parallel as subagents. Each prompt is its reviewer file with `{{WORKTREE}}` and `{{RUN_DIR}}` substituted.
   - Save each reply to `reviews/<reviewer>.json` and run `validate-findings`. On failure, send its output back to that reviewer once; if it still fails, record the reviewer as failed in the run details.
7. **Verify.** For each valid review that has findings, run one verifier subagent with `verifier.md`. Save the result to `verdicts/<reviewer>.json`, then run `apply-verdicts` into `verified/<reviewer>.json`.
8. **Synthesize.** One subagent with `synthesizer.md` writes `report.md`. Print it, its path, and the worktree path.
9. **Post (PR only).**
   - Ask whether to post. If yes, ask which findings, by number, and the event: Comment or Request changes. Approve is never offered.
   - Show the `post-review --dry-run` payload and get a final confirmation, then post. Do nothing if the user declines.
   - Never offer posting for a branch target.
10. **Phase 2 note.** If `--models` is given, say that only Claude is supported in this version and continue with Claude.

- [ ] **Step 1: Write failing install tests** in `tests/claude.test.sh`:
  - `link_path` fresh, idempotent (`SKIPPED`), replaces a wrong symlink, and backs up a real dir.
  - The existing `link_claude_hooks` cases still pass unchanged.
- [ ] **Step 2: Run** `bash tests/claude.test.sh`. Expected: the new cases FAIL.
- [ ] **Step 3: Implement** `link_path`, refactor `link_claude_hooks` onto it, and add the `step_claude` call.
- [ ] **Step 4: Run** `bash tests/claude.test.sh && bash tests/readme.test.sh`. Expected: all PASS.
- [ ] **Step 5: Write `SKILL.md`** per the steps above, under about 200 lines, plus the README section.
- [ ] **Step 6: Run** `bash tests/review-prompts.test.sh` (it only scans `review/`; the skill is meant to be Claude-specific). Then grep `review/ claude/ docs/ README.md` by hand for the user's employer and Jira site names (ask the user for them; never write them into a file). Expected: no matches.
- [ ] **Step 7: Commit** `feat(review): /review-council coordinator skill and install link`.

### Task 7: First real run (with the user)

**Files:** none new; fixes go back into the files above.

- [ ] **Step 1:** Re-run the install step to link the skill: `UTILITIES_SOURCE_ONLY=1 bash -c 'source install.sh; INSTALLED=() SKIPPED=() FAILED=(); step_claude'`. Check that `readlink ~/.claude/skills/review-council` points to the repo.
- [ ] **Step 2:** Ask the user for a real PR URL with a JIRA key, and run `/review-council <url>` in a fresh session. Expected:
  - A worktree is found or created at the PR head.
  - `context/jira.json` and `context/aikido.json` are filled in.
  - 5 files in `reviews/` pass `validate-findings`.
  - `report.md` has all 9 sections.
- [ ] **Step 3:** Run `/review-council` on a local branch with an uncommitted change. Expected: the change appears in `diff.patch`, and posting is not offered.
- [ ] **Step 4:** Do a dry run of posting on the PR from step 2, and post only if the user says so.
- [ ] **Step 5:** Fix whatever the runs turned up, re-run the affected tests, and commit `fix(review): adjustments from first real runs`.
