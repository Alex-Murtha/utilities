#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

GC="$ROOT/review/bin/gather-context"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export REVIEW_COUNCIL_CACHE="$SANDBOX/cache"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# origin with main, cloned to widgets/
git init -q -b main "$SANDBOX/seed"
mkdir -p "$SANDBOX/seed/src"
printf 'a\n' > "$SANDBOX/seed/src/a.sh"
printf 'b\n' > "$SANDBOX/seed/src/b.sh"
printf '{}\n' > "$SANDBOX/seed/package-lock.json"
git -C "$SANDBOX/seed" add -A
git -C "$SANDBOX/seed" commit -q -m init
git clone -q --bare "$SANDBOX/seed" "$SANDBOX/widgets.git"
git clone -q "$SANDBOX/widgets.git" "$SANDBOX/widgets"
W="$SANDBOX/widgets"

git -C "$W" switch -q -c feature/ABC-123-foo
printf 'a2\n' >> "$W/src/a.sh"
printf '{"x":1}\n' > "$W/package-lock.json"
git -C "$W" commit -q -am change
printf 'b2\n' >> "$W/src/b.sh"
printf 'new\n' > "$W/new.txt"

# --- branch mode ---
run=$("$GC" --worktree "$W")
assert_eq "branch: exit 0" "0" "$?"
assert_eq "branch: run dir exists" "yes" "$([[ -d "$run/context" ]] && echo yes)"
assert_eq "branch: under cache" "$REVIEW_COUNCIL_CACHE" "$(dirname "$run")"
case $(basename "$run") in widgets-feature-ABC-123-foo-*) n=ok ;; *) n=$(basename "$run") ;; esac
assert_eq "branch: dir name" "ok" "$n"
C="$run/context"
assert_eq "branch: kind" "branch" "$(jq -r .kind "$C/meta.json")"
assert_eq "branch: jira key from branch" "ABC-123" "$(jq -r .jira_key "$C/meta.json")"
assert_eq "branch: base" "main" "$(jq -r .base_ref "$C/meta.json")"
assert_eq "branch: pr null" "null" "$(jq -r .pr "$C/meta.json")"
assert_contains "branch: committed change in diff" "$C/diff.patch" "src/a.sh"
assert_contains "branch: uncommitted change in diff" "$C/diff.patch" "src/b.sh"
assert_count "branch: lockfile not in diff" "$C/diff.patch" "package-lock.json" 0
assert_contains "branch: lockfile dropped" "$C/dropped.txt" "package-lock.json"
assert_contains "branch: files list" "$C/files.txt" "src/a.sh"
assert_contains "branch: untracked listed" "$C/untracked.txt" "new.txt"

# conventions
printf '# rules\n' > "$W/CLAUDE.md"
git -C "$W" add CLAUDE.md
git -C "$W" commit -q -m conv
run=$("$GC" --worktree "$W")
assert_contains "branch: conventions listed" "$run/context/conventions.txt" "CLAUDE.md"

# only a lockfile changed: empty diff, still exit 0
git -C "$W" stash -q -u
git -C "$W" switch -q -c only-lock origin/main
printf 'lock\n' > "$W/yarn.lock"
git -C "$W" add yarn.lock
git -C "$W" commit -q -m lock
run=$("$GC" --worktree "$W")
assert_eq "lock only: exit 0" "0" "$?"
assert_eq "lock only: empty diff" "0" "$(wc -c < "$run/context/diff.patch")"
assert_contains "lock only: dropped" "$run/context/dropped.txt" "yarn.lock"
assert_eq "lock only: no jira key" "null" "$(jq -r .jira_key "$run/context/meta.json")"

# --- PR mode with a gh stub ---
git -C "$W" switch -q feature/ABC-123-foo
git -C "$W" stash pop -q
git -C "$W" stash -q -u
head=$(git -C "$W" rev-parse HEAD)
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" << EOF
#!/usr/bin/env bash
args="\$*"
case "\$args" in
  "pr view 7 --json comments,reviews"*) echo '{"comments":[{"body":"Aikido: no issues"}],"reviews":[]}' ;;
  "pr view 7 --json"*) echo '{"number":7,"url":"https://github.com/acme/widgets/pull/7","title":"Fix ABC-9 crash","body":"Body","author":{"login":"dev"},"labels":[{"name":"bug"}],"headRefOid":"$head","baseRefName":"main","headRefName":"feature/ABC-123-foo"}' ;;
  "pr checks 7"*) echo '[{"name":"Aikido Security","state":"SUCCESS","link":"https://example.com"}]' ;;
  *) echo "unexpected gh \$args" >&2; exit 1 ;;
esac
EOF
chmod +x "$SANDBOX/bin/gh"
run=$(PATH="$SANDBOX/bin:$PATH" "$GC" --worktree "$W" --pr 7)
assert_eq "pr: exit 0" "0" "$?"
case $(basename "$run") in widgets-pr-7-*) n=ok ;; *) n=$(basename "$run") ;; esac
assert_eq "pr: dir name" "ok" "$n"
C="$run/context"
assert_eq "pr: kind" "pr" "$(jq -r .kind "$C/meta.json")"
assert_eq "pr: number" "7" "$(jq -r .pr.number "$C/meta.json")"
assert_eq "pr: head sha" "$head" "$(jq -r .pr.head_sha "$C/meta.json")"
assert_eq "pr: branch key wins over title" "ABC-123" "$(jq -r .jira_key "$C/meta.json")"
assert_eq "pr: checks.json valid" "Aikido Security" "$(jq -r '.[0].name' "$C/checks.json")"
assert_eq "pr: comments.json valid" "Aikido: no issues" "$(jq -r '.comments[0].body' "$C/comments.json")"
assert_contains "pr: diff" "$C/diff.patch" "src/a.sh"
assert_eq "pr: no untracked.txt" "no" "$([[ -e "$C/untracked.txt" ]] && echo yes || echo no)"

# title key used when the branch has none
git -C "$W" switch -q -c plain-branch
run=$(PATH="$SANDBOX/bin:$PATH" "$GC" --worktree "$W" --pr 7)
assert_eq "pr: title key when branch has none" "ABC-9" "$(jq -r .jira_key "$run/context/meta.json")"

finish
