---
name: review-council
description: Multi-agent code review of a GitHub PR (URL or number) or a local branch. Five read-only reviewers (product/Jira, code, architect, security/Aikido, devil's advocate), a verification pass that drops false findings, and one merged report; can post chosen findings as Comment or Request changes, never Approve. Use when the user types /review-council or asks for a council review of a PR or branch.
---

# Review council

You are the coordinator. You gather context once, run the reviewers, verify
their findings, have one report written, and optionally post to the PR. You
do not review the code yourself, and nothing you start ever edits the code
under review.

Arguments: `<target>` (a PR URL, a PR number or `#number`, or a branch name;
nothing means the current branch), optional `--branch` to force a branch
name, and `--models <ids>`.

## Setup

```bash
REVIEW_DIR="$(cd "$(dirname "$(readlink -f ~/.claude/skills/review-council/SKILL.md)")/../../../review" && pwd)"
ORCA="${ORCA_CLI_COMMAND:-orca-ide}"   # never bare `orca` on Linux
```

Helpers live in `$REVIEW_DIR/bin`. Never run raw `git worktree add/remove`
(a hook blocks it); worktrees come from `$ORCA worktree create`.

If `--models` is given: say this version runs Claude only, and continue with
Claude.

## 1. Target

Run `$REVIEW_DIR/bin/parse-target [--branch] <target>`.

- **PR.** If `owner` is null, fill it from `gh repo view --json owner,name`
  in the current directory. Then run
  `gh pr view <n> --repo <owner>/<repo> --json url,headRefOid,headRefName,isCrossRepository,state`.
  Tell the user if the PR is closed or merged, and continue only if they want to.
- **Branch.** `null` means the branch checked out in the current directory.

## 2. Worktree

All reviewers work from one checkout of the code under review.

`<repo root>` is the user's local clone of `<owner>/<repo>`: the current
directory's `git rev-parse --show-toplevel` if its `origin` is that repo,
otherwise the matching entry in `$ORCA repo list --json`, otherwise ask the
user where the clone is.

**PR:**
1. Look for an existing Orca worktree. First try
   `$ORCA reference find <url> --json`. If that finds nothing, look in
   `$ORCA worktree list --json` for one whose branch is `headRefName`.
2. If one exists, run `$REVIEW_DIR/bin/check-worktree <path> <headRefOid>`.
   If `matches` is false or `dirty` is true, stop and ask the user: review it
   as it is, or let them update it first. Never pull, reset, stash or check
   out in it yourself.
3. If none exists, create one. This works for fork PRs too:
   ```bash
   git -C <repo root> fetch origin "+pull/<n>/head:refs/remotes/origin/pr/<n>"
   $ORCA worktree create --repo path:<repo root> --name review-pr-<n> --branch review-pr-<n> \
     --base-branch origin/pr/<n> --pr <n> --reference <url> --no-parent --setup skip --json
   ```
   Do not pass `--agent`. Then run `check-worktree <new path> <headRefOid>`;
   it must match. If it doesn't, tell the user and stop. Say in the report
   that you created this worktree; it is kept afterwards.

**Branch:** use the worktree that has the branch checked out
(`git worktree list --porcelain`), uncommitted changes included. If none
does, create one the same way with `--base-branch <branch>` and `--name review-<branch>`.

## 3. Context bundle

```bash
RUN=$("$REVIEW_DIR/bin/gather-context" --worktree <path> [--pr <n>])
```

If `$RUN/context/diff.patch` is empty, tell the user there is nothing
reviewable, show `dropped.txt`, and stop.

If `meta.json` `diff_lines` is over 3000, tell the user the change is large
and that reviewers will page through it; note it in the run notes. Every
reviewer prompt already requires reading all of `diff.patch` and listing any
file it could not cover.

### Jira → `$RUN/context/jira.json`

If `meta.json` has a `jira_key`:
1. Get the site from the **Atlassian MCP** connector (not the deprecated
   "Atlassian" one) with `getAccessibleAtlassianResources`. If there is more
   than one Jira site, ask the user which one. Never write the site name
   into any file in the utilities repo.
2. Call `getJiraIssue` (view `evidence`, markdown) and
   `listJiraIssueComments`. If the card has a parent, also get the
   parent's summary.
3. Set `ac_section` to the text under a heading or label matching
   `^\s*(AC|Acceptance Criteria)\s*:?\s*$` (any case, any heading level,
   bold label included), up to the next heading. If there is no such
   heading, set it to `null`.
4. Write
   `{"key","summary","description","comments":[{"author","body"}],"parent_summary","ac_section"}`.
   If any call fails, write `{"key": "<key>", "error": "<message>"}`.

If there is no key, write `{"key": null}`.

### Aikido → `$RUN/context/aikido.json`

- `pr_check`: for a branch, use `n/a`. For a PR, look at the
  `context/checks.json` entries whose name contains `aikido` (any case).
  None means `missing`. Otherwise, any failure means `failed`, any pending
  means `pending`, and all success means `passed`.
- `pr_comments`: the comments and reviews in `context/comments.json` whose
  author or body mentions Aikido.
- Scan: call `aikido_scan_paths` with `root` set to the worktree, and
  `paths` set to the changed files from `files.txt` that still exist
  (skip deletions).
  - No findings: `scan` is `clean`.
  - Findings: `scan` is `issues`, and `results` holds them.
  - Error, or Aikido not set up: `scan` is `not_scanned`, and `error` holds
    the message. Keep going.
- Write `{"pr_check","pr_comments","scan","results","error"}`.

## 4. Review (parallel)

Start the five reviewers **in one message**, as general-purpose subagents.
Each subagent's prompt is the full text of
`$REVIEW_DIR/reviewers/<name>.md` (`product`, `code`, `architect`,
`security`, `devils-advocate`), with the placeholders replaced:

- `{{WORKTREE}}`: the worktree path
- `{{RUN_DIR}}`: `$RUN`
- `{{REVIEW_DIR}}`: `$REVIEW_DIR`

Save each final reply to `$RUN/reviews/<name>.json` and run
`$REVIEW_DIR/bin/validate-findings` on it.

- If validation fails, send its output back to that same reviewer once (for
  example with SendMessage), and validate the corrected reply.
- If it fails again, record "<name>: invalid output" in the run notes and
  leave that reviewer out.

## 5. Verify (parallel)

For each valid review whose `findings` is not empty, start one verifier
subagent, all in one message. Its prompt is `$REVIEW_DIR/verifier.md` with
the same placeholders, plus `{{REVIEW_FILE}}` set to the review's path.

Save each reply (a JSON array) to `$RUN/verdicts/<name>.json`, then run:

```bash
"$REVIEW_DIR/bin/apply-verdicts" "$RUN/reviews/<name>.json" "$RUN/verdicts/<name>.json" > "$RUN/verified/<name>.json"
```

- A review with no findings is copied to `verified/` unchanged.
- If a verifier's reply isn't a JSON array, use `[]`. Its findings are then
  all marked `unverified`. Add a line to the run notes.

## 6. Report

Write the run notes to `$RUN/run-notes.md`:
- the worktree path, and whether you created it
- base and head
- reviewers that failed
- whether Aikido or Jira failed
- untracked files not reviewed

Start one synthesizer subagent with `$REVIEW_DIR/synthesizer.md`. Use the
same placeholders, with `{{RUN_NOTES}}` set to `$RUN/run-notes.md`. Then:
- print `$RUN/report.md` to the user in full
- give the report's path and the worktree path

## 7. Post (PR only, optional)

Never offer this for a branch.
Do not offer posting if the worktree did not match the PR head (the user
chose to review it as it was): line numbers would point at the wrong code.
Say so instead. For a PR, ask the user:
1. Post to the PR? If not, stop.
2. Which findings, by number (`F1, F3`), or `all`. Use `report-findings.json`.
3. As **Comment** or **Request changes**. Never offer Approve; approval is
   always manual.

Each finding is posted as its own comment, with no summary, verdict or
finding numbers. A finding on a changed line is an inline comment. One about
another line of a changed file is a comment on that file. One that needs a
change outside the PR is a separate comment on the PR conversation.

### Draft the comments

Write the chosen entries from `report-findings.json` as
`[{"path","line","body"}]` to `$RUN/post-comments.json`. Use each `body` as
written, with no number, severity or prefix added.

### Review the drafted comments

Nothing goes to GitHub until the user has seen every comment exactly as it
will be posted and said to post them.

1. Run
   `$REVIEW_DIR/bin/post-review --repo <owner>/<repo> --pr <n> --event <COMMENT|REQUEST_CHANGES> --comments $RUN/post-comments.json --dry-run`.
   From its output, write `$RUN/post-drafts.md`. Number the drafts `1`, `2`,
   ... in posting order. For each, give where it goes (`path:line` inline, file
   comment on `path`, or PR conversation) and then its full text, exactly as
   it will appear.
2. Show the user the drafts in full and give the path to `post-drafts.md`.
   Ask what to change. They can:
   - reword a draft, by telling you or by editing its text in
     `post-drafts.md`
   - drop a draft
   - move a draft to another line or file
   - switch between Comment and Request changes
3. Apply the changes to `post-comments.json`. If the user edited
   `post-drafts.md`, read their wording from it, word for word. Then run the
   dry run again and show the updated drafts.
4. Repeat until the user says to post. Approval of one draft, or a
   question, is not a go-ahead; only an explicit "post" (or equivalent) is.

### Post

Run the same command without `--dry-run`. Give the user the links it prints.
If it fails partway, say which comments were posted and which weren't. Do
not retry on your own.

Nothing is posted without that explicit go-ahead.
