#!/usr/bin/env bash
# Worktrees are Orca's to manage.
#
# A worktree made with raw `git worktree add` is invisible to Orca: no terminals,
# no metadata, no cleanup, and it lands wherever the caller guessed (a scratchpad,
# /tmp) instead of under ~/orca/workspaces. The orca-cli skill already says to
# prefer Orca; this makes it stick.
#
#   git worktree add|remove|move|prune|repair|lock|unlock -> denied
#   git worktree list                                     -> allowed (read-only)
#
# PreToolUse/Bash. Reads the tool-call JSON on stdin and prints a permission
# decision on stdout, or nothing at all to stay out of the way.
set -uo pipefail

c=$(jq -r '.tool_input.command // ""')

# `[^|;&]*` lets global options sit between git and worktree (git -C path
# worktree add) without reaching across into the next command of a pipeline.
if grep -qE '(^|[^[:alnum:]_-])git[[:space:]][^|;&]*worktree[[:space:]]+(add|remove|move|prune|repair|lock|unlock)([[:space:]]|$)' <<<"$c"; then
cat <<'DECISION'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Worktrees are managed by Orca, not raw git worktree. Load the orca-cli skill and use the Orca CLI (installed as orca-ide): orca-ide worktree create --repo path:<repo> --name <name> [--base-branch <ref>] to make one, orca-ide worktree list / current / show to find one, and orca-ide worktree rm to remove one. Run orca-ide worktree create --help for its options. git worktree list is still fine for read-only inspection."}}
DECISION
fi
