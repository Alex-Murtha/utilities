#!/usr/bin/env bash
# Block reads of key/secret material.
set -uo pipefail

c=$(jq -r '.tool_input.command // ""')

if grep -qE '\.config/secrets\.env|\.config/bws/|bws +secret|\.lic\b' <<<"$c"; then
cat <<'DECISION'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Never read or touch key/secret material (~/.config/secrets.env, ~/.config/bws/, bws secret commands, *.lic files). Secrets for builds come from environment variables; notify the user if one is missing."}}
DECISION
fi
