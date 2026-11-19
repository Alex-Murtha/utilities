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

# Agent-neutral: no Claude-specific tool names anywhere under review/.
hits=$(grep -rlE 'mcp__|Agent tool|subagent_type|TodoWrite' "$R" 2> /dev/null)
assert_eq "review/ is agent-neutral" "" "$hits"

finish
