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

# Upstream repo: two commits, the first tagged v1.
UP="$SANDBOX/upstream"
g() { git -C "$UP" -c user.name=t -c user.email=t@example.invalid "$@"; }
git init -q -b main "$UP"
printf 'one\n' > "$UP/file"
g add file && g commit -q -m one && g tag v1
printf 'two\n' > "$UP/file"
g commit -q -am two
SHA1=$(g rev-parse v1)
SHA2=$(g rev-parse HEAD)
URL="file://$UP"

head_of() { git -C "$1" rev-parse HEAD 2> /dev/null; }
has() { # <needle> <items...>
  local needle=$1 x
  shift
  for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}
reset_lists() { INSTALLED=() SKIPPED=() FAILED=(); }

# fresh clone at a commit SHA
d="$SANDBOX/a/b/repo"
reset_lists
git_checkout_at thing "$URL" "$SHA2" "$d"
assert_eq "fresh: returns 0" 0 "$?"
assert_eq "fresh: HEAD is the pinned commit" "$SHA2" "$(head_of "$d")"
assert_eq "fresh: working tree checked out" two "$(cat "$d/file" 2> /dev/null)"
assert_eq "fresh: recorded as installed" "thing" "${INSTALLED[*]}"
assert_eq "fresh: no temp dirs left" "" "$(find "$SANDBOX/a/b" -mindepth 1 -maxdepth 1 -name '.*')"

# second call: skipped
reset_lists
git_checkout_at thing "$URL" "$SHA2" "$d"
assert_eq "re-run: returns 0" 0 "$?"
assert_eq "re-run: recorded as skipped" "thing" "${SKIPPED[*]}"
assert_eq "re-run: nothing installed" 0 "${#INSTALLED[@]}"

# existing checkout at another commit moves to a tag; untracked files survive
mkdir -p "$d/custom"
printf 'mine\n' > "$d/custom/keep"
reset_lists
git_checkout_at thing "$URL" v1 "$d"
assert_eq "move to tag: returns 0" 0 "$?"
assert_eq "move to tag: HEAD is the tagged commit" "$SHA1" "$(head_of "$d")"
assert_eq "move to tag: working tree updated" one "$(cat "$d/file" 2> /dev/null)"
assert_eq "move to tag: recorded as installed" "thing" "${INSTALLED[*]}"
assert_eq "move to tag: untracked file kept" mine "$(cat "$d/custom/keep" 2> /dev/null)"

reset_lists
git_checkout_at thing "$URL" v1 "$d"
assert_eq "tag re-run: recorded as skipped" "thing" "${SKIPPED[*]}"
assert_eq "tag re-run: nothing installed" 0 "${#INSTALLED[@]}"

# fresh clone at a tag
d2="$SANDBOX/tagclone"
reset_lists
git_checkout_at thing "$URL" v1 "$d2"
assert_eq "fresh tag: HEAD is the tagged commit" "$SHA1" "$(head_of "$d2")"
reset_lists
git_checkout_at thing "$URL" v1 "$d2"
assert_eq "fresh tag re-run: skipped" "thing" "${SKIPPED[*]}"

# target exists but is not a git checkout (even inside another repo)
plain="$d/custom/plain"
mkdir -p "$plain"
printf 'data\n' > "$plain/f"
reset_lists
git_checkout_at thing "$URL" "$SHA2" "$plain" 2> /dev/null
assert_eq "not a checkout: returns 1" 1 "$?"
assert_eq "not a checkout: contents untouched" data "$(cat "$plain/f" 2> /dev/null)"
assert_eq "not a checkout: nothing recorded" 0 "$((${#INSTALLED[@]} + ${#SKIPPED[@]}))"
assert_eq "not a checkout: parent repo HEAD unchanged" "$SHA1" "$(head_of "$d")"

# target has a .git that is not a repository: git must not fall back to the
# enclosing repo (here: the checkout at $d)
broken="$d/custom/broken"
mkdir -p "$broken/.git"
reset_lists
git_checkout_at thing "$URL" "$SHA2" "$broken" 2> /dev/null
assert_eq "broken .git: returns 1" 1 "$?"
assert_eq "broken .git: nothing recorded" 0 "$((${#INSTALLED[@]} + ${#SKIPPED[@]}))"
assert_eq "broken .git: parent repo HEAD unchanged" "$SHA1" "$(head_of "$d")"

# upstream missing: nothing left behind
d3="$SANDBOX/c/repo"
reset_lists
git_checkout_at thing "file://$SANDBOX/nope" "$SHA2" "$d3" 2> /dev/null
assert_eq "bad url: returns 1" 1 "$?"
if [[ -e "$d3" ]]; then _bad "bad url: target not created"; else _ok "bad url: target not created"; fi
assert_eq "bad url: no temp dirs left" "" "$(find "$SANDBOX/c" -mindepth 1 2> /dev/null)"

# unknown ref on an existing checkout: stays where it was
reset_lists
git_checkout_at thing "$URL" no-such-tag "$d" 2> /dev/null
assert_eq "bad ref: returns 1" 1 "$?"
assert_eq "bad ref: HEAD unchanged" "$SHA1" "$(head_of "$d")"

finish
