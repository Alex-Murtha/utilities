#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"
export UTILITIES_SOURCE_ONLY=1
# shellcheck source=install.sh
source "$ROOT/install.sh"

README="$ROOT/README.md"
TOOLS="$ROOT/docs/tools.md"
[[ -r "$README" ]] || { _bad "README.md readable"; finish; exit 1; }
[[ -r "$TOOLS" ]] || { _bad "docs/tools.md readable"; finish; exit 1; }

# check <label> <cmd...>: pass when cmd succeeds.
check() {
  local label=$1
  shift
  if "$@" > /dev/null; then _ok "$label"; else _bad "$label"; fi
}

# Table rows look like: | `tool` | source | script |
row_for() { grep -E "^\| \`$1\` \|" "$TOOLS"; }

for p in "${DNF_PACKAGES[@]}"; do
  row=$(row_for "$p")
  check "dnf row: $p" grep -q "| dnf" <<< "$row"
done

for f in "${BREW_FORMULAE[@]}"; do
  row=$(row_for "$f")
  check "brew row: $f" grep -q brew <<< "$row"
done

# Official installers (names as they appear in the table).
for t in nvm node corepack dotnet bicep bws claude homebrew code-new-roman-nerd-font oh-my-zsh powerlevel10k; do
  check "installer row: $t" row_for "$t"
done

# Reverse: every dnf/brew row names a tool that is in the arrays.
while IFS= read -r name; do
  found=0
  for p in "${DNF_PACKAGES[@]}" "${BREW_FORMULAE[@]}"; do
    [[ "$p" == "$name" ]] && found=1
  done
  check "table row in install.sh: $name" test "$found" -eq 1
done < <(grep -E '^[|] .[^ ]+. [|] (dnf|brew)' "$TOOLS" | sed -E 's/^[|] .([^ ]+).[ ].*/\1/')

# Pins documented.
for v in "$NVM_VERSION" "$NERD_FONTS_VERSION" "$NODE_MAJOR" "${DOTNET_CHANNELS[@]}" "$OMZ_REF" "$P10K_REF"; do
  assert_contains "pin in tools.md: $v" "$TOOLS" "$v"
done

assert_contains "one-liner" "$README" "curl -fsSL https://raw.githubusercontent.com/Alex-Murtha/utilities/main/install.sh | bash"
assert_contains "links post-setup" "$README" "docs/post-setup.md"
assert_contains "links tools" "$README" "docs/tools.md"

# post-setup: terminal-readable, lines <= 80 chars.
PS="$ROOT/docs/post-setup.md"
check "post-setup exists" test -r "$PS"
long=$(awk 'length > 80' "$PS" 2>/dev/null | wc -l)
assert_eq "post-setup lines <= 80" 0 "$long"
assert_contains "post-setup az login" "$PS" "az login"
assert_contains "post-setup acr" "$PS" "az acr login --name <registry>"

finish
