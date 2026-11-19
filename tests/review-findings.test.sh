#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

VF="$ROOT/review/bin/validate-findings"
AV="$ROOT/review/bin/apply-verdicts"
F="$ROOT/tests/fixtures/review"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

"$VF" "$F/valid-code.json" > /dev/null
assert_eq "valid code review passes" "0" "$?"
"$VF" "$F/valid-product.json" > /dev/null
assert_eq "valid product review passes" "0" "$?"

out=$("$VF" "$F/bad-severity.json")
assert_eq "bad severity fails" "1" "$?"
assert_eq "bad severity named" "yes" "$(grep -q severity <<< "$out" && echo yes)"

out=$("$VF" "$F/missing-file-key.json")
assert_eq "missing file key fails" "1" "$?"
assert_eq "missing file key named" "yes" "$(grep -q file <<< "$out" && echo yes)"

"$VF" "$F/too-many-alternatives.json" > /dev/null
assert_eq "4 alternatives fails" "1" "$?"

printf 'not json at all\n' > "$SANDBOX/garbage.txt"
"$VF" "$SANDBOX/garbage.txt" > /dev/null
assert_eq "no JSON at all fails" "1" "$?"

cp "$F/prose-wrapped.txt" "$SANDBOX/wrapped.json"
"$VF" "$SANDBOX/wrapped.json" > /dev/null
assert_eq "prose-wrapped passes" "0" "$?"
jq -e . "$SANDBOX/wrapped.json" > /dev/null 2>&1
assert_eq "prose-wrapped rewritten to pure JSON" "0" "$?"
assert_eq "prose-wrapped content kept" "code-1" "$(jq -r '.findings[0].id' "$SANDBOX/wrapped.json")"

out=$("$AV" "$F/valid-code.json" "$F/verdicts.json")
assert_eq "apply-verdicts: refuted dropped" "0" "$(jq '[.findings[] | select(.id == "code-2")] | length' <<< "$out")"
assert_eq "apply-verdicts: confirmed kept" "confirmed" "$(jq -r '.findings[] | select(.id == "code-1") | .verdict' <<< "$out")"
assert_eq "apply-verdicts: reason kept" "Line 11 is unquoted." "$(jq -r '.findings[] | select(.id == "code-1") | .verdict_reason' <<< "$out")"
assert_eq "apply-verdicts: missing verdict is unverified" "unverified" "$(jq -r '.findings[] | select(.id == "code-3") | .verdict' <<< "$out")"
assert_eq "apply-verdicts: other keys kept" "code" "$(jq -r .reviewer <<< "$out")"

finish
