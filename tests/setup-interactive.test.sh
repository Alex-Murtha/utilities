#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
mkdir -p "$HOME" "$SANDBOX/stubs"
export PATH="$SANDBOX/stubs:$PATH"
export UTILITIES_SOURCE_ONLY=1 SETUP_SOURCE_ONLY=1
# shellcheck source=setup-interactive.sh
source "$ROOT/setup-interactive.sh"

GH_LOG="$SANDBOX/gh.log"
cat > "$SANDBOX/stubs/gh" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
if [[ "\$1 \$2" == "api user" ]]; then
  printf '%s\n' '{"login":"u","id":7,"name":null,"email":null}'
fi
STUB
chmod +x "$SANDBOX/stubs/gh"

# parse_repo_list
got=$(printf 'o/a\r\n\n  # c\n o/b \n' | parse_repo_list | od -An -c | tr -s ' ')
want=$(printf 'o/a\no/b\n' | od -An -c | tr -s ' ')
assert_eq "parse_repo_list" "$want" "$got"

# clone_repos
dest="$SANDBOX/code"
mkdir -p "$dest/b"
: > "$GH_LOG"
printf 'o/a\no/b\n' | clone_repos "$dest"
assert_eq "clone_repos: one call" "repo clone o/a $dest/a" "$(cat "$GH_LOG")"

# set_git_identity
: > "$GH_LOG"
set_git_identity > /dev/null
assert_eq "identity: name" "u" "$(git config --global user.name)"
assert_eq "identity: email" "7+u@users.noreply.github.com" "$(git config --global user.email)"
: > "$GIT_CONFIG_GLOBAL"
git config --global user.email keep@example.com
set_git_identity > /dev/null
assert_eq "identity: email kept" "keep@example.com" "$(git config --global user.email)"
assert_eq "identity: name filled" "u" "$(git config --global user.name)"

# save_bws_token
tf="$SANDBOX/cfg/bws/token"
printf 'secret1\n' | save_bws_token "$tf" > /dev/null
assert_eq "token: content" "secret1" "$(cat "$tf")"
assert_eq "token: file mode" "600" "$(stat -c %a "$tf")"
assert_eq "token: dir mode" "700" "$(stat -c %a "$(dirname "$tf")")"
printf 'secret2\n' | save_bws_token "$tf" > /dev/null
assert_eq "token: not overwritten" "secret1" "$(cat "$tf")"

# fetch_clone_list
printf 'tok\n' > "$SANDBOX/tokfile"
cat > "$SANDBOX/stubs/bws" << STUB
#!/usr/bin/env bash
printf '%s|%s\n' "\${BWS_ACCESS_TOKEN:-}" "\$*" > "$SANDBOX/bws.args"
printf '%s\n' '[{"key":"X","value":"no"},{"key":"CLONE_REPOS","value":"o/a\no/b"}]'
STUB
chmod +x "$SANDBOX/stubs/bws"
got=$(BWS_TOKEN_FILE="$SANDBOX/tokfile" fetch_clone_list)
assert_eq "fetch_clone_list: value" $'o/a\no/b' "$got"
if cut -d'|' -f2- "$SANDBOX/bws.args" | grep -q tok; then _bad "token not on command line"; else _ok "token not on command line"; fi
assert_eq "fetch_clone_list: token via env" "tok" "$(cut -d'|' -f1 "$SANDBOX/bws.args")"

finish
