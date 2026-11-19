# Review council: multi-agent code review — design

Date: 2026-11-19.

## Intent

AI has sharply increased the number of pull requests the team produces, and
everyone has to review to keep velocity up. The user considers themselves
weak at code review and wants AI agents to raise their review throughput and
quality. The long-term aim is to run the same review through several
different models (Claude, GPT via Codex, GitHub Copilot, others) to get
independent perspectives.

This setup is personal: only the user runs it. Nothing here needs to work for
teammates, in CI, or without Orca.

The reviewer instructions are written once, in agent-neutral files. The first
build runs them all on Claude. A second phase sends the same files to the
other agents configured in Orca, with no rewrite.

## Goals

- One command, `/review-council <target>`, where `<target>` is a GitHub PR
  URL, a PR number (in the current repo), or a local branch name (the
  user's own work before opening a PR). No target means the current branch.
- Five reviewers run in parallel, each with its own focus:
  1. **Product:** finds the linked JIRA card and checks every requirement
     and acceptance criterion is met, or that the PR description documents
     the drift.
  2. **Code:** quality, simplicity, cohesion, readability, best practice,
     tests, and the repo's own conventions (CLAUDE.md / AGENTS.md).
  3. **Architect:** whether this is the right solution at the right scope:
     fit with the existing design, boundaries, coupling, future cost.
  4. **Security/compliance:** makes sure Aikido scanning happened and is
     clean, then does its own security review of the change.
  5. **Devil's advocate:** pokes holes in the approach and argues the
     strongest case for alternatives.
- High signal over volume: every finding is checked by a separate
  verification pass that tries to disprove it before it reaches the report.
- One merged report that helps a reviewer who isn't confident yet: what the
  PR does, where to focus, ranked findings, and questions to ask the author.
- Optionally post chosen findings to the PR as a Comment or a Request
  changes review, on the user's behalf.
- Phase 2: the reviewers also run on every other agent configured in Orca,
  picked up automatically, and the report shows where models agree.

## Non-goals

- Sharing with the team, CI / GitHub Action integration, running without
  Orca.
- Approving a PR (always manual) or fixing the code.
- Replacing the human review: the user still decides and signs off.

## Anti-goals (failure even if it works)

- A long, noisy report the user skims past. A report with 3 real issues
  beats one with 30 maybes.
- Anything posted to GitHub or JIRA without the user confirming it first.
- Reviewer definitions duplicated per model, so they drift apart.
- A reviewer changing the code it is reviewing.

## Design

### Layout in this repo

```
review/
  reviewers/
    product.md
    code.md
    architect.md
    security.md
    devils-advocate.md
  verifier.md          # instructions for the disprove-it pass
  synthesizer.md       # instructions for the merged report
  findings-schema.md   # the output format every reviewer uses
  bin/                 # small bash helpers the coordinator calls, so the
                       # deterministic parts are tested (target parsing,
                       # worktree check, context bundle, findings checks,
                       # posting); exact set is in the plan
claude/skills/review-council/SKILL.md   # the Claude coordinator
```

`install.sh`'s `step_claude` symlinks `claude/skills/review-council` into
`~/.claude/skills/` (same pattern as the hooks symlink). The reviewer files
are agent-neutral Markdown: role, focus, what to read, what to ignore, and
the output format. No Claude-specific tool names in them; the coordinator
tells each reviewer where the worktree and context bundle are.

### Flow

1. **Get a worktree for the change.** All reviewers work from one checkout
   of the code being reviewed, so they can read the whole repo with normal
   tools, Aikido can scan real paths, and phase-2 Orca workers have a
   workspace to run in.
   - PR: look for an existing Orca worktree linked to the PR
     (`orca reference find <pr-url>`, then a worktree on the PR's head
     branch). If none, create one with `orca worktree create` on the PR's
     head branch, linked to the PR (`--pr`, `--reference <pr-url>`), with
     no agent launched. If an existing worktree's HEAD isn't the PR's head
     commit, or it has uncommitted changes, stop and tell the user, offering
     to review as-is or to let them update it first; the coordinator never
     pulls, resets or stashes in the user's worktree.
   - Local branch: use the worktree that has the branch checked out (usually
     the current one), including uncommitted changes, since this is work in
     progress. If the branch isn't checked out anywhere, create an Orca
     worktree for it as above.
   - A worktree the coordinator created is kept afterwards (the user may
     want to look at the code) and named in the report.
2. **Build the context bundle** (`gather-context`, run against the
   worktree) in a run directory,
   `~/.cache/review-council/<repo>-<pr-or-branch>-<timestamp>/context/`:
   - PR metadata from `gh pr view` (title, body, author, base, head SHA,
     labels), `gh pr diff`, `gh pr checks`. For a local branch, the diff
     from the merge-base with the default branch to the working tree, plus
     a warning listing untracked files that aren't included.
   - Changed-file list and repo conventions files (CLAUDE.md, AGENTS.md).
   - Lockfiles, generated and vendored files are dropped from the diff
     given to reviewers, with a list of what was dropped.

   The coordinator then fetches the two below once and writes them in, so
   reviewers on any model need no JIRA or Aikido access of their own:
   - **JIRA:** find a key matching `[A-Z][A-Z0-9]+-\d+` in the branch name,
     PR title, then PR body; fetch the card (summary, description,
     comments, linked parent epic summary). No key: record "no linked card".
     Cards are inconsistent, so acceptance criteria are found like this:
     - If the description has an "AC" / "Acceptance Criteria" section (any
       heading or label with that name, any case), that section is the AC.
     - Otherwise the product reviewer infers the AC from the description
       (for a bug, often just "the error no longer happens"), and the report
       marks the checklist as **inferred** so the user knows it isn't the
       card's own wording.
   - **Aikido:** for a PR, record the Aikido status from `gh pr checks`
     (missing, pending, failed, passed) and any Aikido PR comments. For both
     PRs and branches, run an Aikido scan on the changed paths in the
     worktree and record the results.
3. **Review:** start the five reviewers in parallel, each given its
   reviewer file, the worktree path and the bundle path. Reviewers are
   read-only: they never edit, stage, commit or check out anything. They
   may run read-only commands, and targeted tests, linters or type checks
   for the changed area, but never the full test suite. Each returns
   findings in the shared format, which the coordinator writes to
   `reviews/<reviewer>.json` in the run directory.
4. **Verify:** for each reviewer's findings, a verifier agent reads the
   code and tries to disprove each one. It marks each finding
   `confirmed`, `plausible`, or `refuted`, and refuted ones are dropped.
   Devil's-advocate alternatives and product requirement checks are not
   bugs; they skip this pass.
5. **Synthesize:** one agent merges everything, removes duplicates, ranks
   by severity, drops nits unless there is little else, and writes
   `report.md` in the run directory. The coordinator prints the report in
   the terminal and gives its path.
6. **Optional posting:** after the report, the coordinator offers to post
   chosen findings to the PR as one review with inline comments. It asks
   whether to post as "Comment" or "Request changes" on the user's behalf.
   It never approves; approval is always manual. Nothing is posted
   without the user picking which findings and confirming.

### Finding format

Each finding: `reviewer`, `severity` (`blocker` / `major` / `minor` / `nit`),
`confidence` (`high` / `medium` / `low`), `file`, `line` (optional),
`title`, `evidence` (what in the code shows it), `suggestion`. Reviewers
also write a short free-text summary. Extras:

- Product: a requirements checklist, one row per requirement or acceptance
  criterion: `met` / `not met` / `drift documented` / `drift undocumented`,
  with where in the code or PR text, and whether the AC was taken from the
  card or inferred.
- Security: Aikido status and scan results, alongside its own findings.
- Devil's advocate: up to 3 alternatives, each with its strongest argument
  and why the PR's approach might still win.

### Report shape (`report.md`)

1. What this PR does (3–5 lines) and how big/risky it is.
2. Suggested verdict for the user to consider (looks good / comment /
   needs changes), with the one-line reason.
3. Where to focus your own attention (files and why).
4. Findings by severity, each with file:line, evidence, suggestion, and
   which reviewers (and in phase 2, which models) raised it.
5. JIRA requirements checklist (marked inferred where it is).
6. Security and Aikido status.
7. Alternatives worth discussing (devil's advocate, architect).
8. Questions to ask the author (2–5).
9. Run details: worktree used, files dropped from the diff, anything that
   failed or was skipped.

### Phase 2: every configured agent, automatically

There is no flag to pick models. Each run asks Orca which agent CLIs are set
up (`orca agent installed`) and runs every reviewer once per agent. Setting
up a new agent in Orca adds it to the council on the next run, with no change
to the review setup. An optional `--models <ids>` narrows a single run (for
example, a quick Claude-only pass on a small PR).

- `claude` reviewers keep running as Claude subagents. Every other agent
  (Codex, Copilot, and so on) runs as an Orca worker:
  `orca orchestration worker-start --worktree <the review worktree> --agent <id>`,
  with a spec that points at the reviewer file, worktree and bundle, and
  repeats the read-only rules.
- Workers return their findings in Orca's done message and the coordinator
  writes the file, so no agent's sandbox needs to write outside the
  worktree.
- The coordinator waits for Orca to report every worker done (no polling).
  An agent that is installed but fails (not logged in, times out) is listed
  in the report as missing, and the review continues.
- Verify and synthesize stay on Claude. The synthesizer matches findings
  across models (same file, overlapping lines, same issue) and marks how
  many models raised each; agreement raises its rank.
- Today `orca agent installed` lists only `claude` in WSL, so phase 2 starts
  by installing the Codex and Copilot CLIs there (via `install.sh`).

## Decided by the user

- Reviewer instructions written once, agent-neutral; Claude first, other
  Orca agents in phase 2.
- Five reviewer roles as listed in Goals.
- Personal use only.
- Command name `/review-council`.
- Acceptance criteria: use the card's AC section when present, otherwise
  infer from the description.
- Posting: user chooses Comment or Request changes each time; never Approve.
- Reviewers work from a real checkout: an existing Orca worktree for the
  PR, or one the coordinator creates.
- Phase 2 uses every agent configured in Orca automatically, not a flag.

## Calls made in the design (user may override)

- **Scope of the first build is phase 1 only.** Phase 2 gets its own plan
  once phase 1 has been used on real PRs.
- An existing worktree that is behind the PR or has uncommitted changes is
  never touched; the user is asked how to proceed.
- Worktrees the coordinator creates are kept, not removed, after the run.
- Local-branch reviews include uncommitted changes.
- Reviewers may run targeted tests and linters but never the full suite.
- The coordinator fetches JIRA and Aikido data once and hands it to the
  reviewers, so non-Claude models need no extra connections.
- A verification pass drops refuted findings; nits are dropped unless the
  report would otherwise be nearly empty.
- Report is a local Markdown file plus terminal output.
- Run directories live under `~/.cache/review-council/` and are never
  cleaned up automatically.
- **Aikido runs from the Claude coordinator** (there is no Aikido CLI; the
  scan uses the Aikido plugin's tools). If Aikido isn't set up for the repo
  or the scan fails, the review continues and the report says "not scanned"
  prominently; a missing or failed Aikido PR check is itself a security
  finding.
- **JIRA uses the "Atlassian MCP" connector** (not the deprecated one).
  The site is discovered at run time from the connection (today there is
  exactly one, with read-only access, which is all the review needs); if
  there are several, the coordinator asks. The site name is never written
  into this repo, which is public and must not name the user's employer.
  If the card can't be fetched, the product reviewer says so instead of
  returning an empty checklist.

## Left to the builder

- Exact wording of each reviewer file, within the focus described.
- Whether `gather-context` emits JSON or a directory of files.
- How large diffs are handled (splitting by area, or summarising), as long
  as no reviewer silently skips files.
- How to create an Orca worktree for a PR from a fork.
- Tests: shell tests for `gather-context` and the install symlink, in the
  existing `tests/` style.
