#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

PT="$ROOT/review/bin/parse-target"
CW="$ROOT/review/bin/check-worktree"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# --- parse-target ---
out=$("$PT" https://github.com/acme/widgets/pull/42)
assert_eq "pr url: kind" "pr" "$(jq -r .kind <<< "$out")"
assert_eq "pr url: owner" "acme" "$(jq -r .owner <<< "$out")"
assert_eq "pr url: repo" "widgets" "$(jq -r .repo <<< "$out")"
assert_eq "pr url: number" "42" "$(jq -r .number <<< "$out")"

out=$("$PT" 'https://github.com/acme/widgets/pull/42/files?w=1')
assert_eq "pr url with suffix: number" "42" "$(jq -r .number <<< "$out")"
assert_eq "pr url with suffix: canonical url" "https://github.com/acme/widgets/pull/42" "$(jq -r .url <<< "$out")"

out=$("$PT" 42)
assert_eq "bare number: kind" "pr" "$(jq -r .kind <<< "$out")"
assert_eq "bare number: number" "42" "$(jq -r .number <<< "$out")"
assert_eq "bare number: owner null" "null" "$(jq -r .owner <<< "$out")"

out=$("$PT" '#42')
assert_eq "hash number: number" "42" "$(jq -r .number <<< "$out")"

out=$("$PT" --branch 42)
assert_eq "--branch 42: kind" "branch" "$(jq -r .kind <<< "$out")"
assert_eq "--branch 42: branch" "42" "$(jq -r .branch <<< "$out")"

out=$("$PT" feature/ABC-123-foo)
assert_eq "branch name: kind" "branch" "$(jq -r .kind <<< "$out")"
assert_eq "branch name: unchanged" "feature/ABC-123-foo" "$(jq -r .branch <<< "$out")"

out=$("$PT")
assert_eq "no target: kind" "branch" "$(jq -r .kind <<< "$out")"
assert_eq "no target: branch null" "null" "$(jq -r .branch <<< "$out")"

"$PT" https://gitlab.com/x/y/merge_requests/1 > /dev/null 2>&1
assert_eq "unknown url: exit 2" "2" "$?"

# --- check-worktree ---
repo="$SANDBOX/repo"
git init -q "$repo"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
printf 'a\n' > "$repo/a.txt"
git -C "$repo" add a.txt
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m two
head=$(git -C "$repo" rev-parse HEAD)
first=$(git -C "$repo" rev-parse HEAD~1)

out=$("$CW" "$repo" "$head")
assert_eq "clean at sha: matches" "true" "$(jq -r .matches <<< "$out")"
assert_eq "clean at sha: dirty" "false" "$(jq -r .dirty <<< "$out")"
assert_eq "clean at sha: head" "$head" "$(jq -r .head <<< "$out")"

out=$("$CW" "$repo" "$first")
assert_eq "other sha: matches false" "false" "$(jq -r .matches <<< "$out")"

printf 'new\n' > "$repo/u.txt"
out=$("$CW" "$repo" "$head")
assert_eq "untracked: untracked" "true" "$(jq -r .untracked <<< "$out")"
assert_eq "untracked: not dirty" "false" "$(jq -r .dirty <<< "$out")"

printf 'b\n' >> "$repo/a.txt"
out=$("$CW" "$repo" "$head")
assert_eq "modified tracked: dirty" "true" "$(jq -r .dirty <<< "$out")"

mkdir -p "$SANDBOX/plain"
"$CW" "$SANDBOX/plain" "$head" > /dev/null 2>&1
assert_eq "not a repo: exit 2" "2" "$?"

finish
