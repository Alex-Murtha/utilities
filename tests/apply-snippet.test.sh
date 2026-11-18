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

START='# >>> utilities >>>'
END='# <<< utilities <<<'
snip="$SANDBOX/snippet"
printf 'export NEW=1\n' > "$snip"

# creates missing target
t="$SANDBOX/a/b/missing"
apply_snippet "$snip" "$t"
assert_eq "creates missing target" "$(printf '%s\nexport NEW=1\n%s\n' "$START" "$END")" "$(cat "$t")"

# appends to existing
t="$SANDBOX/existing"
printf 'export A=1\n' > "$t"
apply_snippet "$snip" "$t"
assert_eq "appends: line 1 preserved" "export A=1" "$(sed -n 1p "$t")"
assert_eq "appends: block follows" "$START" "$(sed -n 2p "$t")"

# no trailing newline
t="$SANDBOX/nonl"
printf 'export A=1' > "$t"
apply_snippet "$snip" "$t"
assert_eq "no trailing newline: line 1" "export A=1" "$(sed -n 1p "$t")"
assert_eq "no trailing newline: marker on own line" "$START" "$(sed -n 2p "$t")"

# refusals leave the file untouched
t="$SANDBOX/unterm"
printf 'a\n%s\nuser\n' "$START" > "$t"
before=$(cat "$t")
apply_snippet "$snip" "$t" > /dev/null 2>&1
assert_eq "unterminated start: rc 1" "1" "$?"
assert_eq "unterminated start: unchanged" "$before" "$(cat "$t")"
t="$SANDBOX/endfirst"
printf 'a\n%s\nuser\n%s\nb\n' "$END" "$START" > "$t"
before=$(cat "$t")
apply_snippet "$snip" "$t" > /dev/null 2>&1
assert_eq "end before start: rc 1" "1" "$?"
assert_eq "end before start: unchanged" "$before" "$(cat "$t")"

# idempotent
t="$SANDBOX/idem"
printf 'export A=1\n' > "$t"
apply_snippet "$snip" "$t"
before=$(cat "$t"); mtime=$(stat -c %Y "$t")
INSTALLED=(); SKIPPED=()
sleep 1
apply_snippet "$snip" "$t"
assert_count "idempotent: one start marker" "$t" "$START" 1
assert_eq "idempotent: SKIPPED" "$t" "${SKIPPED[*]:-}"
assert_eq "idempotent: not INSTALLED" "" "${INSTALLED[*]:-}"
assert_eq "idempotent: content unchanged" "$before" "$(cat "$t")"
assert_eq "idempotent: mtime unchanged" "$mtime" "$(stat -c %Y "$t")"

# replaces changed block
t="$SANDBOX/repl"
printf 'before\n%s\nOLDCONTENT\n%s\nafter\n' "$START" "$END" > "$t"
INSTALLED=()
apply_snippet "$snip" "$t"
assert_contains "replace: before kept" "$t" "before"
assert_contains "replace: after kept" "$t" "after"
assert_contains "replace: new content" "$t" "export NEW=1"
assert_count "replace: old content gone" "$t" "OLDCONTENT" 0
assert_count "replace: one start marker" "$t" "$START" 1
assert_eq "replace: INSTALLED" "$t" "${INSTALLED[*]:-}"

# writes through symlink
real="$SANDBOX/real"; link="$SANDBOX/link"
printf 'export A=1\n' > "$real"
ln -s "$real" "$link"
apply_snippet "$snip" "$link"
[[ -L "$link" ]] && l=yes || l=no
assert_eq "symlink: still a link" yes "$l"
assert_contains "symlink: real has block" "$real" "$START"

# preserves mode
t="$SANDBOX/mode"
printf 'export A=1\n' > "$t"; chmod 600 "$t"
apply_snippet "$snip" "$t"
assert_eq "preserves mode" 600 "$(stat -c %a "$t")"

# no temp files left behind
leftover=$(find "$SANDBOX" -name '*.utilities.*' | wc -l)
assert_eq "no temp files left" 0 "$leftover"

finish
