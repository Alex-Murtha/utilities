#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

SNIPPET="$ROOT/snippets/zshrc"
P10K="$ROOT/zsh/p10k.zsh"

command -v zsh > /dev/null || {
  echo "zsh is required" >&2
  exit 1
}

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

zsh -n "$SNIPPET" 2> /dev/null
assert_eq "snippet parses" 0 "$?"
zsh -n "$P10K" 2> /dev/null
assert_eq "p10k config parses" 0 "$?"

# Nothing installed (empty HOME): the snippet must still load cleanly.
err=$(env -i HOME="$SANDBOX" PATH=/usr/bin:/bin zsh -f -c 'source "$1"' zsh "$SNIPPET" 2>&1 > /dev/null)
assert_eq "loads with nothing installed: exit 0" 0 "$?"
assert_eq "loads with nothing installed: no output on stderr" "" "$err"

assert_count "plugin list" "$SNIPPET" \
  'plugins=(git sudo extract colored-man-pages docker docker-compose kubectl helm)' 1
assert_count "no you-should-use" "$SNIPPET" 'you-should-use' 0
assert_eq "no aliases" 0 "$(grep -cE '^[[:space:]]*alias ' "$SNIPPET")"
assert_contains "omz auto-update disabled" "$SNIPPET" "zstyle ':omz:update' mode disabled"
assert_contains "sources the repo's p10k config" "$SNIPPET" 'code/utilities/zsh/p10k.zsh'
assert_count "no chezmoi references in p10k config" "$P10K" chezmoi 0

# Syntax highlighting wraps every widget defined before it: it must be last.
last_source=$(grep -nE '(^|[[:space:]])(source|\.)[[:space:]]' "$SNIPPET" | grep -v '^[0-9]*:[[:space:]]*#' | tail -n1)
case "$last_source" in
  *zsh-syntax-highlighting.zsh*) _ok "syntax highlighting is sourced last" ;;
  *) _bad "syntax highlighting is sourced last (got: $last_source)" ;;
esac

# Order: oh-my-zsh, then the p10k theme, then its config.
line_of() { grep -nF -- "source \"$1" "$SNIPPET" | head -n1 | cut -d: -f1; }
omz=$(line_of '$ZSH/oh-my-zsh.sh')
theme=$(line_of '$ZSH/custom/themes/powerlevel10k/powerlevel10k.zsh-theme')
conf=$(line_of '$HOME/code/utilities/zsh/p10k.zsh')
if [[ -n "$omz" && -n "$theme" && -n "$conf" && "$omz" -lt "$theme" && "$theme" -lt "$conf" ]]; then
  _ok "order: oh-my-zsh, theme, config"
else
  _bad "order: oh-my-zsh, theme, config (lines: '$omz' '$theme' '$conf')"
fi

# Without this, a missing config file makes p10k open its configuration wizard
# on every shell start. It has to be set before the theme is sourced.
wizard=$(grep -nF 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' "$SNIPPET" | head -n1 | cut -d: -f1)
if [[ -n "$wizard" && -n "$theme" && "$wizard" -lt "$theme" ]]; then
  _ok "p10k configuration wizard disabled before the theme loads"
else
  _bad "p10k configuration wizard disabled before the theme loads (lines: '$wizard' '$theme')"
fi

finish
