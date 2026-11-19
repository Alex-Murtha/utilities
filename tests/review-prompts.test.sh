#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

R="$ROOT/review"
for name in product code architect security devils-advocate; do
  f="$R/reviewers/$name.md"
  for h in Role Inputs Focus 'Out of scope' Rules Output; do
    assert_contains "$name: ## $h" "$f" "## $h"
  done
  assert_contains "$name: read-only rule" "$f" "never edit, stage, commit or check out"
  assert_contains "$name: full suite rule" "$f" "never the full test suite"
  assert_contains "$name: schema reference" "$f" "findings-schema.md"
  assert_contains "$name: whole-diff rule" "$f" "Read all of \`context/diff.patch\`"
  assert_contains "$name: worktree placeholder" "$f" "{{WORKTREE}}"
  assert_contains "$name: run dir placeholder" "$f" "{{RUN_DIR}}"
done

assert_contains "verifier: schema reference" "$R/verifier.md" "findings-schema.md"
assert_contains "verifier: read-only rule" "$R/verifier.md" "never edit, stage, commit or check out"

for s in "What this PR does" "Suggested verdict" "Where to focus" "Findings" \
  "JIRA requirements" "Security and Aikido" "Alternatives" "Questions for the author" "Run details"; do
  assert_contains "synthesizer: section $s" "$R/synthesizer.md" "## $s"
done

assert_contains "synthesizer: findings index file" "$R/synthesizer.md" "report-findings.json"

S="$ROOT/claude/skills/review-council/SKILL.md"
assert_contains "skill: no posting after mismatched review" "$S" "Do not offer posting if the worktree did not match the PR head"
assert_contains "skill: large diff split" "$S" "diff_lines"

assert_contains "synthesizer: plain comment bodies" "$R/synthesizer.md" "never a finding number, severity, verdict or reviewer name"
assert_contains "skill: one comment per finding" "$S" "Each finding is posted as its own comment"
assert_count "skill: no summary body file" "$S" "post-body.md" 0
assert_count "skill: no --body-file" "$S" "--body-file" 0

assert_contains "skill: drafted comments review step" "$S" "Review the drafted comments"
assert_contains "skill: drafts file for the user" "$S" "post-drafts.md"

A="$R/already-raised.md"
assert_contains "already-raised: existing comments input" "$A" "existing-comments.json"
assert_contains "already-raised: output fields" "$A" '"comment_url"'
assert_contains "already-raised: read-only rule" "$A" "never edit, stage, commit or check out"
assert_contains "synthesizer: already-raised section" "$R/synthesizer.md" "## Already raised on the PR"
assert_contains "synthesizer: covered input" "$R/synthesizer.md" "covered.json"
assert_contains "skill: already-raised step" "$S" "Check what is already on the PR"
assert_contains "skill: uses drop-covered" "$S" "drop-covered"

# Agent-neutral: no Claude-specific tool names anywhere under review/.
hits=$(grep -rlE 'mcp__|Agent tool|subagent_type|TodoWrite' "$R" 2> /dev/null)
assert_eq "review/ is agent-neutral" "" "$hits"

finish
