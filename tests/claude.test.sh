#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME"
export UTILITIES_SOURCE_ONLY=1
# shellcheck source=install.sh
source "$ROOT/install.sh"

repo_hooks="$SANDBOX/repo/hooks"
mkdir -p "$repo_hooks"

# link fresh
cd="$SANDBOX/c1"
mkdir -p "$cd"
SKIPPED=() INSTALLED=()
link_claude_hooks "$repo_hooks" "$cd"
assert_eq "link fresh" "$repo_hooks" "$(readlink "$cd/hooks")"
assert_eq "link fresh: recorded installed" "1" "${#INSTALLED[@]}"

# link idempotent
SKIPPED=()
link_claude_hooks "$repo_hooks" "$cd"
assert_eq "link idempotent" "1" "${#SKIPPED[@]}"
assert_eq "link idempotent: still correct" "$repo_hooks" "$(readlink "$cd/hooks")"

# link replaces wrong symlink
cd="$SANDBOX/c2"
mkdir -p "$cd" "$SANDBOX/elsewhere"
ln -s "$SANDBOX/elsewhere" "$cd/hooks"
link_claude_hooks "$repo_hooks" "$cd"
assert_eq "link replaces wrong symlink" "$repo_hooks" "$(readlink "$cd/hooks")"

# link backs up real dir
cd="$SANDBOX/c3"
mkdir -p "$cd/hooks"
printf 'orig\n' > "$cd/hooks/x.sh"
link_claude_hooks "$repo_hooks" "$cd"
assert_eq "link backs up real dir: linked" "$repo_hooks" "$(readlink "$cd/hooks")"
bak=$(compgen -G "$cd/hooks.bak.*" | head -n1)
assert_eq "link backs up real dir: contents" "orig" "$(cat "$bak/x.sh" 2>/dev/null)"

# link_path: generic symlink with the same rules
src="$SANDBOX/repo/skills/review-council"
mkdir -p "$src"
dest="$SANDBOX/lp/skills/review-council"
SKIPPED=() INSTALLED=()
link_path "$src" "$dest"
assert_eq "link_path fresh (creates parent)" "$src" "$(readlink "$dest")"
assert_eq "link_path fresh: recorded installed" "1" "${#INSTALLED[@]}"
link_path "$src" "$dest"
assert_eq "link_path idempotent" "1" "${#SKIPPED[@]}"
ln -sfn "$SANDBOX/elsewhere" "$dest"
link_path "$src" "$dest"
assert_eq "link_path replaces wrong symlink" "$src" "$(readlink "$dest")"
dest2="$SANDBOX/lp2/review-council"
mkdir -p "$dest2"
printf 'mine\n' > "$dest2/SKILL.md"
link_path "$src" "$dest2"
assert_eq "link_path backs up real dir: linked" "$src" "$(readlink "$dest2")"
bak=$(compgen -G "$dest2.bak.*" | head -n1)
assert_eq "link_path backs up real dir: contents" "mine" "$(cat "$bak/SKILL.md" 2>/dev/null)"

tpl="$ROOT/claude/settings-hooks.json"
hd="$SANDBOX/h"

# merge creates settings
s="$SANDBOX/new/settings.json"
merge_claude_settings "$tpl" "$s" "$hd"
assert_eq "merge creates settings" "$hd/no-secret-material.sh" "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$s")"
assert_eq "merge: no placeholder left" "0" "$(grep -c '__HOOKS_DIR__' "$s")"

# merge keeps other keys
s="$SANDBOX/keep.json"
printf '{"model":"x","hooks":{"Old":[]}}' > "$s"
merge_claude_settings "$tpl" "$s" "$hd"
assert_eq "merge keeps other keys: model" "x" "$(jq -r '.model' "$s")"
assert_eq "merge keeps other keys: old hooks gone" "false" "$(jq '.hooks | has("Old")' "$s")"
assert_eq "merge keeps other keys: new hooks" "Edit|Write" "$(jq -r '.hooks.PostToolUse[0].matcher' "$s")"

# merge rejects invalid json
s="$SANDBOX/bad.json"
printf '{not json' > "$s"
merge_claude_settings "$tpl" "$s" "$hd"
rc=$?
assert_eq "merge rejects invalid json: rc" "1" "$rc"
assert_eq "merge rejects invalid json: untouched" "{not json" "$(cat "$s")"

finish
