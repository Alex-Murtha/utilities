#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

PR="$ROOT/review/bin/post-review"
F="$ROOT/tests/fixtures/review"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

LOG="$SANDBOX/gh.log"
: > "$LOG"
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" << STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr diff") cat "$F/pr.diff" ;;
  "api -X") { printf 'ARGS %s\n' "\$*"; cat; printf '\n'; } >> "$LOG"; echo '{"id":1}' ;;
  *) echo "unexpected gh \$*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"
export PATH="$SANDBOX/bin:$PATH"

printf 'Overall: looks mostly fine.\n' > "$SANDBOX/body.md"
cat > "$SANDBOX/comments.json" << 'EOF2'
[
  {"path": "src/a.sh", "line": 11, "body": "F1: quote this"},
  {"path": "src/a.sh", "line": 50, "body": "F2: not in the diff"},
  {"path": "src/a.sh", "line": 9, "body": "F3: context line"},
  {"path": "src/gone.sh", "line": 1, "body": "F4: deleted file"}
]
EOF2
args=(--repo acme/widgets --pr 7 --body-file "$SANDBOX/body.md" --comments "$SANDBOX/comments.json")

for ev in APPROVE approve Approve; do
  "$PR" "${args[@]}" --event "$ev" > /dev/null 2>&1
  assert_eq "event $ev refused: exit 2" "2" "$?"
done
"$PR" "${args[@]}" --event DISMISS > /dev/null 2>&1
assert_eq "unknown event refused: exit 2" "2" "$?"
assert_eq "refused events: gh never called" "0" "$(wc -c < "$LOG")"

out=$("$PR" "${args[@]}" --event REQUEST_CHANGES --dry-run)
assert_eq "dry run: exit 0" "0" "$?"
assert_eq "dry run: event" "REQUEST_CHANGES" "$(jq -r .event <<< "$out")"
assert_eq "dry run: inline count" "2" "$(jq '.comments | length' <<< "$out")"
assert_eq "dry run: added line inline" "RIGHT" "$(jq -r '.comments[] | select(.line == 11) | .side' <<< "$out")"
assert_eq "dry run: context line inline" "src/a.sh" "$(jq -r '.comments[] | select(.line == 9) | .path' <<< "$out")"
assert_eq "dry run: body kept" "yes" "$(jq -r .body <<< "$out" | grep -q 'Overall: looks mostly fine.' && echo yes)"
assert_eq "dry run: other findings heading" "yes" "$(jq -r .body <<< "$out" | grep -q '^### Other findings' && echo yes)"
assert_eq "dry run: off-diff comment in body" "yes" "$(jq -r .body <<< "$out" | grep -qF '`src/a.sh:50` — F2: not in the diff' && echo yes)"
assert_eq "dry run: deleted-file comment in body" "yes" "$(jq -r .body <<< "$out" | grep -qF 'F4: deleted file' && echo yes)"
assert_eq "dry run: gh api not called" "0" "$(grep -c '^ARGS' "$LOG")"

out=$("$PR" "${args[@]}" --event comment)
assert_eq "post: exit 0" "0" "$?"
assert_eq "post: gh api called once" "1" "$(grep -c '^ARGS' "$LOG")"
assert_contains "post: POST to reviews" "$LOG" "-X POST repos/acme/widgets/pulls/7/reviews"
assert_contains "post: event normalised" "$LOG" '"event": "COMMENT"'

finish
