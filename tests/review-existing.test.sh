#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

FC="$ROOT/review/bin/fetch-pr-comments"
DC="$ROOT/review/bin/drop-covered"
F="$ROOT/tests/fixtures/review"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# gh stub: --paginate --jq '.[]' output is one JSON value per line.
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" << 'STUB'
#!/usr/bin/env bash
case "$*" in
  *"repos/acme/widgets/pulls/7/comments"*)
    echo '{"user":{"login":"bot-reviewer"},"path":"src/a.ts","line":94,"body":"Early return skips the reset.","html_url":"https://example.com/c1"}'
    echo '{"user":{"login":"dev"},"path":"src/b.ts","line":null,"original_line":12,"body":"Old note.","html_url":"https://example.com/c2"}' ;;
  *"repos/acme/widgets/pulls/7/reviews"*)
    echo '{"user":{"login":"lead"},"state":"COMMENTED","body":"Please add a test for the save path.","html_url":"https://example.com/r1"}'
    echo '{"user":{"login":"lead"},"state":"APPROVED","body":"","html_url":"https://example.com/r2"}' ;;
  *"repos/acme/widgets/issues/7/comments"*)
    echo '{"user":{"login":"pm"},"body":"Does this cover deleted items?","html_url":"https://example.com/i1"}' ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$SANDBOX/bin/gh"

out=$(PATH="$SANDBOX/bin:$PATH" "$FC" --repo acme/widgets --pr 7)
assert_eq "fetch: exit 0" "0" "$?"
assert_eq "fetch: empty review bodies skipped" "4" "$(jq length <<< "$out")"
assert_eq "fetch: inline comment" "inline|bot-reviewer|src/a.ts|94|false|https://example.com/c1" \
  "$(jq -r '.[] | select(.url == "https://example.com/c1") | [.kind, .author, .path, .line, .outdated, .url] | join("|")' <<< "$out")"
assert_eq "fetch: outdated inline keeps original line" "12|true" \
  "$(jq -r '.[] | select(.url == "https://example.com/c2") | [.line, .outdated] | join("|")' <<< "$out")"
assert_eq "fetch: review body" "review|lead" "$(jq -r '.[] | select(.url == "https://example.com/r1") | [.kind, .author] | join("|")' <<< "$out")"
assert_eq "fetch: conversation comment" "conversation|Does this cover deleted items?" \
  "$(jq -r '.[] | select(.url == "https://example.com/i1") | [.kind, .body] | join("|")' <<< "$out")"

cat > "$SANDBOX/broken-gh" << 'STUB'
#!/usr/bin/env bash
exit 1
STUB
mkdir -p "$SANDBOX/bin2" && mv "$SANDBOX/broken-gh" "$SANDBOX/bin2/gh" && chmod +x "$SANDBOX/bin2/gh"
PATH="$SANDBOX/bin2:$PATH" "$FC" --repo acme/widgets --pr 7 > /dev/null 2>&1
assert_eq "fetch: gh failure exits 1" "1" "$?"

# drop-covered
cat > "$SANDBOX/covered.json" << 'EOF2'
[{"id": "code-1", "title": "Unquoted variable", "comment_url": "https://example.com/c1", "author": "bot-reviewer", "reason": "Same issue."}]
EOF2
out=$("$DC" "$F/valid-code.json" "$SANDBOX/covered.json")
assert_eq "drop: covered finding removed" "0" "$(jq '[.findings[] | select(.id == "code-1")] | length' <<< "$out")"
assert_eq "drop: others kept" "code-2,code-3" "$(jq -r '[.findings[].id] | join(",")' <<< "$out")"
assert_eq "drop: other keys kept" "code" "$(jq -r .reviewer <<< "$out")"
printf '[]' > "$SANDBOX/none.json"
assert_eq "drop: nothing covered keeps all" "3" "$("$DC" "$F/valid-code.json" "$SANDBOX/none.json" | jq '.findings | length')"

finish
