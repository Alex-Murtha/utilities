#!/usr/bin/env bash
# Block running the full test suite locally.
set -uo pipefail

c=$(jq -r '.tool_input.command // ""')

if grep -qE 'earth[[:space:]]+\+test' <<<"$c"; then
cat <<'DECISION'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"CLAUDE.md: Do not run the full test suite locally. Run only the individual tests affected by your changes; rely on CI for the full suite."}}
DECISION
fi
