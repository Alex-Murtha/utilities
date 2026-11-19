#!/usr/bin/env bash
# Behaviour tests for the Claude Code hook scripts.
# Pipes synthetic PreToolUse/PostToolUse JSON in and asserts whether a decision
# comes out, and that anything emitted is valid JSON with the expected verdict.
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0

check() { # <label> <fire|quiet> <script> <stdin-json> [expected-decision]
  local label="$1" expect="$2" script="$3" payload="$4" want="${5:-}"
  local out got="quiet"
  out=$(printf '%s' "$payload" | "$H/$script" 2>&1)
  [ -n "$out" ] && got="fire"
  if [ "$got" != "$expect" ]; then
    echo "FAIL: $label — expected $expect, got $got ${out:+($out)}"
    fails=$((fails+1)); return
  fi
  if [ "$got" = "fire" ]; then
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      echo "FAIL: $label — emitted invalid JSON: $out"; fails=$((fails+1)); return
    fi
    local d
    d=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')
    if [ -n "$want" ] && [ "$d" != "$want" ]; then
      echo "FAIL: $label — expected decision '$want', got '$d'"; fails=$((fails+1)); return
    fi
    echo "PASS: $label (decision=$d)"
  else
    echo "PASS: $label (silent)"
  fi
}

cmd() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')"; }

echo "--- azure-guardrails: ARM probe asks ---"
check "acr show asks"                fire  azure-guardrails.sh "$(cmd 'az acr show --name myregistry')" ask
check "bare acr show asks"           fire  azure-guardrails.sh "$(cmd 'az acr show')" ask
check "acr show at end of pipeline"  fire  azure-guardrails.sh "$(cmd 'set -e; az acr show -n myregistry -o tsv')" ask

echo "--- azure-guardrails: data-plane calls must stay allowed ---"
check "repository show-tags allowed" quiet azure-guardrails.sh "$(cmd 'az acr repository show-tags --name myregistry --repository api-server')"
check "repository list allowed"      quiet azure-guardrails.sh "$(cmd 'az acr repository list --name myregistry -o none')"
check "acr login allowed"            quiet azure-guardrails.sh "$(cmd 'az acr login -n myregistry')"
check "show-usage sibling allowed"   quiet azure-guardrails.sh "$(cmd 'az acr show-usage --name myregistry')"
check "show-manifest sibling ok"     quiet azure-guardrails.sh "$(cmd 'az acr show-manifest -n myregistry')"

echo "--- azure-guardrails: subscription switch ---"
check "account set asks"             fire  azure-guardrails.sh "$(cmd 'az account set --subscription other-sub')" ask
check "odd spacing still asks"       fire  azure-guardrails.sh "$(cmd 'az  account   set -s foo')" ask
check "account show allowed"         quiet azure-guardrails.sh "$(cmd 'az account show --query name -o tsv')"
check "account list allowed"         quiet azure-guardrails.sh "$(cmd 'az account list -o table')"
check "unrelated command allowed"    quiet azure-guardrails.sh "$(cmd 'ls -la')"

echo "--- azure-guardrails: both patterns present still asks ---"
check "acr show + account set"       fire  azure-guardrails.sh "$(cmd 'az acr show -n myregistry || az account set -s other-sub')" ask

echo "--- azure-guardrails: reasons point at the data-plane call ---"
for c in 'az acr show -n myregistry' 'az account set -s x'; do
  out=$(printf '%s' "$(cmd "$c")" | "$H/azure-guardrails.sh" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  if grep -q 'az acr repository list' <<<"$out"; then
    echo "PASS: reason for [$c] mentions az acr repository list"
  else
    echo "FAIL: reason for [$c] does not mention az acr repository list"; fails=$((fails+1))
  fi
done

echo "--- no-secret-material ---"
check "secrets.env blocked"          fire  no-secret-material.sh "$(cmd 'cat ~/.config/secrets.env')" deny
check "bws token blocked"            fire  no-secret-material.sh "$(cmd 'cat ~/.config/bws/token')" deny
check "bws secret blocked"           fire  no-secret-material.sh "$(cmd 'bws secret list')" deny
check "lic file blocked"             fire  no-secret-material.sh "$(cmd 'cat license.lic')" deny
check "benign read ignored"          quiet no-secret-material.sh "$(cmd 'cat README.md')"

echo "--- no-full-test-suite ---"
check "full suite blocked"           fire  no-full-test-suite.sh "$(cmd 'earth +test')" deny
check "single test ignored"          quiet no-full-test-suite.sh "$(cmd 'bash tests/env-check.sh')"

echo "--- orca-worktrees: raw worktree mutations denied ---"
check "worktree add denied"          fire  orca-worktrees.sh "$(cmd 'git worktree add ../wt TICKET-1')" deny
check "worktree add -b denied"       fire  orca-worktrees.sh "$(cmd 'git worktree add -b TICKET-1 /tmp/wt origin/TICKET-1')" deny
check "git -C worktree add denied"   fire  orca-worktrees.sh "$(cmd 'git -C ~/code/myrepo worktree add /tmp/wt main')" deny
check "worktree remove denied"       fire  orca-worktrees.sh "$(cmd 'git worktree remove /tmp/wt')" deny
check "worktree prune denied"        fire  orca-worktrees.sh "$(cmd 'git worktree prune')" deny
check "after cd && denied"           fire  orca-worktrees.sh "$(cmd 'cd ~/code/myrepo && git worktree add /tmp/wt x')" deny

echo "--- orca-worktrees: read-only and unrelated commands allowed ---"
check "worktree list allowed"        quiet orca-worktrees.sh "$(cmd 'git worktree list')"
check "worktree list | grep ok"      quiet orca-worktrees.sh "$(cmd 'git worktree list | grep add')"
check "orca-ide create allowed"      quiet orca-worktrees.sh "$(cmd 'orca-ide worktree create --name x')"
check "orca-ide rm allowed"          quiet orca-worktrees.sh "$(cmd 'orca-ide worktree rm --worktree x')"
check "plain git add allowed"        quiet orca-worktrees.sh "$(cmd 'git add worktree.md')"
check "git status allowed"           quiet orca-worktrees.sh "$(cmd 'git status -sb')"

echo "--- prettier (PostToolUse) ---"
check "missing path no-op"           quiet prettier.sh '{"tool_name":"Edit","tool_input":{}}'

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fake_prettier() { # <project-dir>: fake binary that records its args
  mkdir -p "$1/node_modules/.bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/called"\n' "$T" > "$1/node_modules/.bin/prettier"
  chmod +x "$1/node_modules/.bin/prettier"
}
pj() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# config + fake binary: called with the expected args
mkdir -p "$T/proj/src"; : > "$T/proj/.prettierrc"; fake_prettier "$T/proj"
: > "$T/proj/src/a.ts"; rm -f "$T/called"
out=$(pj "$T/proj/src/a.ts" | "$H/prettier.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$T/called" 2>/dev/null)" = "--write --ignore-unknown $T/proj/src/a.ts" ]; then
  echo "PASS: prettier runs repo-local binary with expected args"
else
  echo "FAIL: prettier did not call fake correctly (rc=$rc out=$out called=$(cat "$T/called" 2>/dev/null))"; fails=$((fails+1))
fi

# package.json with a prettier key counts as config
mkdir -p "$T/pkg"; printf '{"prettier":{}}' > "$T/pkg/package.json"; fake_prettier "$T/pkg"
: > "$T/pkg/b.ts"; rm -f "$T/called"
pj "$T/pkg/b.ts" | "$H/prettier.sh" >/dev/null 2>&1
if [ "$(cat "$T/called" 2>/dev/null)" = "--write --ignore-unknown $T/pkg/b.ts" ]; then
  echo "PASS: prettier key in package.json detected"
else
  echo "FAIL: prettier key in package.json not detected"; fails=$((fails+1))
fi

# no prettier config anywhere up the tree: fake not called
mkdir -p "$T/bare/dir"; : > "$T/bare/dir/c.ts"; rm -f "$T/called"
out=$(pj "$T/bare/dir/c.ts" | "$H/prettier.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$T/called" ]; then
  echo "PASS: no prettier config is a no-op"
else
  echo "FAIL: no-config case (rc=$rc called=$(cat "$T/called" 2>/dev/null))"; fails=$((fails+1))
fi

# config present but no binary: silent exit 0
mkdir -p "$T/nobin"; : > "$T/nobin/.prettierrc.json"; : > "$T/nobin/d.ts"
out=$(pj "$T/nobin/d.ts" | "$H/prettier.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: config without binary is silent"
else
  echo "FAIL: config without binary (rc=$rc out=$out)"; fails=$((fails+1))
fi

# relative path must not hang the walk-up
out=$(printf '%s' '{"tool_input":{"file_path":"rel/x.ts"}}' | timeout 5 "$H/prettier.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  echo "PASS: relative path exits promptly"
else
  echo "FAIL: relative path (rc=$rc out=$out)"; fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL HOOK TESTS PASSED"; else echo "$fails FAILURE(S)"; fi
exit "$fails"
