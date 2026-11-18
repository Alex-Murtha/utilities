#!/usr/bin/env bash
# PostToolUse hook: run a project's own prettier over a file it just wrote.
#
# Walks up from the file to the nearest directory with a prettier config
# (.prettierrc*, prettier.config.*, or a "prettier" key in package.json) and
# runs that directory's node_modules/.bin/prettier, so the version and config
# match what the project itself uses. Silent no-op otherwise.
set -uo pipefail

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -n "$f" ] || exit 0

has_config() { # <dir>
  local d=$1 p
  for p in "$d"/.prettierrc* "$d"/prettier.config.*; do
    [ -e "$p" ] && return 0
  done
  [ -f "$d/package.json" ] && jq -e 'has("prettier")' "$d/package.json" >/dev/null 2>&1
}

case "$f" in /*) ;; *) f="$PWD/$f" ;; esac
d=$(dirname "$f")
while :; do
  if has_config "$d"; then
    if [ -x "$d/node_modules/.bin/prettier" ]; then
      "$d/node_modules/.bin/prettier" --write --ignore-unknown "$f" 2>/dev/null || true
    fi
    exit 0
  fi
  p=$(dirname "$d")
  [ "$p" = "$d" ] && exit 0
  d=$p
done
