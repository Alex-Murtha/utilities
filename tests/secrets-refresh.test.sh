#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME" "$SANDBOX/stubs"
export PATH="$SANDBOX/stubs:$PATH"
export BWS_TOKEN_FILE="$SANDBOX/token"
export SECRETS_FILE="$SANDBOX/out/secrets.env"
printf 'tok\n' > "$BWS_TOKEN_FILE"

# stub_bws <json> <exit>: stub prints json, records whether the token arrived by env.
stub_bws() {
  printf '%s\n' "$1" > "$SANDBOX/bws.json"
  cat > "$SANDBOX/stubs/bws" << STUB
#!/usr/bin/env bash
printf '%s\n' "\${BWS_ACCESS_TOKEN:-}" > "$SANDBOX/bws.token"
cat "$SANDBOX/bws.json"
exit $2
STUB
  chmod +x "$SANDBOX/stubs/bws"
}

# writes file
stub_bws '[{"key":"A","value":"x y"},{"key":"B","value":"it'"'"'s"},{"key":"CLONE_REPOS","value":"o/r"}]' 0
bash "$ROOT/bin/secrets-refresh" > "$SANDBOX/out.log" 2>&1
assert_eq "writes file: exit" "0" "$?"
assert_eq "writes file: mode" "600" "$(stat -c %a "$SECRETS_FILE")"
got=$(
  # shellcheck disable=SC1090
  source "$SECRETS_FILE"
  printf '%s|%s|%s' "$A" "$B" "${CLONE_REPOS-absent}"
)
assert_eq "writes file: values, CLONE_REPOS excluded" "x y|it's|absent" "$got"
assert_eq "token passed via env" "tok" "$(cat "$SANDBOX/bws.token")"
if grep -q "x y" "$SANDBOX/out.log"; then _bad "no values printed"; else _ok "no values printed"; fi

# keeps file on bws failure
before=$(sha256sum < "$SECRETS_FILE")
stub_bws '[]' 1
bash "$ROOT/bin/secrets-refresh" > /dev/null 2>&1
assert_eq "bws failure: exit" "1" "$?"
assert_eq "bws failure: file unchanged" "$before" "$(sha256sum < "$SECRETS_FILE")"

# rejects bad key
stub_bws '[{"key":"BAD-NAME","value":"v"}]' 0
bash "$ROOT/bin/secrets-refresh" > /dev/null 2>&1
assert_eq "bad key: exit" "1" "$?"
assert_eq "bad key: file unchanged" "$before" "$(sha256sum < "$SECRETS_FILE")"

# missing token
rm -f "$BWS_TOKEN_FILE"
out=$(bash "$ROOT/bin/secrets-refresh" 2>&1)
assert_eq "missing token: exit" "1" "$?"
if grep -qF "$BWS_TOKEN_FILE" <<< "$out"; then _ok "missing token: names path"; else _bad "missing token: names path"; fi

finish
