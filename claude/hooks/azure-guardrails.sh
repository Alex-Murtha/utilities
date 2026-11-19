#!/usr/bin/env bash
# Azure/ACR guardrails.
#
# Two related mistakes, one root cause: a registry can live in a different
# subscription than the one selected. ARM calls resolve the registry as a
# resource in the *selected* subscription and so report a false "could not be
# found"; data-plane calls authenticate against the registry itself and work
# from anywhere. Reaching for `az account set` to "fix" that treats the symptom.
#
#   az acr show     -> ask. It is the ARM probe that manufactures the problem.
#   az account set  -> ask. Legitimate occasionally, never as a fix for the above.
#
# PreToolUse/Bash. Reads the tool-call JSON on stdin and prints a permission
# decision on stdout, or nothing at all to stay out of the way.
set -uo pipefail

c=$(jq -r '.tool_input.command // ""')

# `show([[:space:]]|$)` and not `show\b`, so sibling subcommands that merely start
# with "show" -- az acr show-usage, az acr show-manifest -- are left alone. The
# data-plane reader az acr repository show-tags never matches either: "repository"
# sits between "acr" and "show".
if grep -qE 'az[[:space:]]+acr[[:space:]]+show([[:space:]]|$)' <<<"$c"; then
cat <<'DECISION'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"az acr show is an ARM call: it resolves the registry as a resource in the currently selected subscription, so it can report a false could-not-be-found when the registry lives in another subscription. Prefer a data-plane call to test reachability or auth: az acr repository list --name <registry> -o none, which authenticates against the registry itself and works from any subscription. If that call fails, the session or registry token is stale -- run az acr login -n <registry> (and az login first if there is no session at all). Do not switch subscriptions. Approve only if you really need the ARM resource."}}
DECISION
    exit 0
fi

if grep -qE 'az[[:space:]]+account[[:space:]]+set\b' <<<"$c"; then
cat <<'DECISION'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Do not switch the Azure subscription as a fix for ACR lookups. Every ACR operation the tooling uses -- az acr repository list --name <registry>, az acr repository show-tags, az acr login -n <registry>, and the image pulls that follow -- is a data-plane call that works from any subscription. A could-not-be-found-in-subscription error means an ARM call is being used where a data-plane call belongs: fix the caller. For a genuine auth failure run az acr login -n <registry> (and az login first if there is no session at all). Approve only if you explicitly asked for a subscription switch."}}
DECISION
fi
