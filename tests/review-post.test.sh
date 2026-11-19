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
  "api -X") { printf 'ARGS %s\n' "\$*"; cat; printf '\n'; } >> "$LOG"; echo '{"html_url":"https://example.com/x"}' ;;
  *) echo "unexpected gh \$*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"
export PATH="$SANDBOX/bin:$PATH"

cat > "$SANDBOX/comments.json" << 'EOF2'
[
  {"path": "src/a.sh", "line": 11, "body": "Quote this variable."},
  {"path": "src/a.sh", "line": 9, "body": "Context line comment."},
  {"path": "src/a.sh", "line": 50, "body": "Changed file, line outside the diff."},
  {"path": "src/gone.sh", "line": null, "body": "Deleted file comment."},
  {"path": "src/other.ts", "line": 131, "body": "File not in the PR."},
  {"path": null, "line": null, "body": "Whole PR comment."}
]
EOF2
args=(--repo acme/widgets --pr 7 --comments "$SANDBOX/comments.json")

for ev in APPROVE approve Approve; do
  "$PR" "${args[@]}" --event "$ev" > /dev/null 2>&1
  assert_eq "event $ev refused: exit 2" "2" "$?"
done
"$PR" "${args[@]}" --event DISMISS > /dev/null 2>&1
assert_eq "unknown event refused: exit 2" "2" "$?"
assert_eq "refused events: gh never called" "0" "$(wc -c < "$LOG")"

out=$("$PR" "${args[@]}" --event REQUEST_CHANGES --dry-run)
assert_eq "dry run: exit 0" "0" "$?"
assert_eq "dry run: event" "REQUEST_CHANGES" "$(jq -r .review.event <<< "$out")"
assert_eq "dry run: no summary body" "" "$(jq -r .review.body <<< "$out")"
assert_eq "dry run: one review comment per in-PR finding" "4" "$(jq '.review.comments | length' <<< "$out")"
assert_eq "dry run: added line inline" "RIGHT" "$(jq -r '.review.comments[] | select(.line == 11) | .side' <<< "$out")"
assert_eq "dry run: inline body unchanged" "Quote this variable." "$(jq -r '.review.comments[] | select(.line == 11) | .body' <<< "$out")"
assert_eq "dry run: context line inline" "src/a.sh" "$(jq -r '.review.comments[] | select(.line == 9) | .path' <<< "$out")"
assert_eq "dry run: off-hunk line becomes a file comment" "file" \
  "$(jq -r '.review.comments[] | select(.body | contains("outside the diff")) | .subject_type' <<< "$out")"
assert_eq "dry run: file comment says the line" "yes" \
  "$(jq -r '.review.comments[] | select(.subject_type == "file" and (.body | contains("outside the diff"))) | .body' <<< "$out" | grep -q '^Line 50:' && echo yes)"
assert_eq "dry run: deleted file gets a file comment" "src/gone.sh" \
  "$(jq -r '.review.comments[] | select(.body == "Deleted file comment.") | .path' <<< "$out")"
assert_eq "dry run: two standalone PR comments" "2" "$(jq '.pr_comments | length' <<< "$out")"
assert_eq "dry run: outside-PR comment names the file" "yes" \
  "$(jq -r '.pr_comments[0]' <<< "$out" | grep -qF '`src/other.ts` (line 131)' && echo yes)"
assert_eq "dry run: whole-PR comment unchanged" "Whole PR comment." "$(jq -r '.pr_comments[1]' <<< "$out")"
assert_eq "dry run: no summary anywhere" "no" "$(grep -qiE 'other findings|verdict|F[0-9]' <<< "$out" && echo yes || echo no)"
assert_eq "dry run: gh api not called" "0" "$(grep -c '^ARGS' "$LOG")"

# Request changes with nothing that can go on the review: first PR comment becomes its body.
printf '[{"path":"src/other.ts","line":1,"body":"Outside A."},{"path":null,"line":null,"body":"Whole B."}]' > "$SANDBOX/outside.json"
out=$("$PR" --repo acme/widgets --pr 7 --comments "$SANDBOX/outside.json" --event REQUEST_CHANGES --dry-run)
assert_eq "request changes, no inline: review body is first finding" "yes" "$(jq -r .review.body <<< "$out" | grep -qF 'Outside A.' && echo yes)"
assert_eq "request changes, no inline: rest stay PR comments" "Whole B." "$(jq -r '.pr_comments | join("|")' <<< "$out")"
out=$("$PR" --repo acme/widgets --pr 7 --comments "$SANDBOX/outside.json" --event COMMENT --dry-run)
assert_eq "comment, no inline: no review" "null" "$(jq -r .review <<< "$out")"
assert_eq "comment, no inline: all PR comments" "2" "$(jq '.pr_comments | length' <<< "$out")"

printf '[]' > "$SANDBOX/empty.json"
"$PR" --repo acme/widgets --pr 7 --comments "$SANDBOX/empty.json" --event COMMENT --dry-run > /dev/null 2>&1
assert_eq "nothing to post: exit 2" "2" "$?"

out=$("$PR" "${args[@]}" --event comment)
assert_eq "post: exit 0" "0" "$?"
assert_eq "post: one review + two PR comments" "3" "$(grep -c '^ARGS' "$LOG")"
assert_eq "post: review first" "yes" "$(grep '^ARGS' "$LOG" | head -1 | grep -q 'pulls/7/reviews' && echo yes)"
assert_eq "post: PR comments to the issue endpoint" "2" "$(grep -c 'ARGS.*repos/acme/widgets/issues/7/comments' "$LOG")"
assert_contains "post: event normalised" "$LOG" '"event": "COMMENT"'

finish
