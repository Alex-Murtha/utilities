#!/usr/bin/env bash
# Fedora workstation bootstrap. Idempotent; safe to re-run.
# Source with UTILITIES_SOURCE_ONLY=1 to use the helpers without running main.
set -uo pipefail

UTILITIES_DIR="${UTILITIES_DIR:-$HOME/code/utilities}"

MARK_START='# >>> utilities >>>'
MARK_END='# <<< utilities <<<'

INSTALLED=()
SKIPPED=()
FAILED=()

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# try <label> <cmd...>: run cmd; record label in FAILED on non-zero.
try() {
  local label=$1
  shift
  if "$@"; then
    return 0
  fi
  FAILED+=("$label")
  return 1
}

# apply_snippet <snippet_file> <target_file>
# Replace (or append) the marker block in target with the snippet contents.
# Lines outside the markers are never modified.
apply_snippet() {
  local snippet=$1 target=$2 real dir tmp
  [[ -r "$snippet" ]] || {
    warn "snippet not readable: $snippet"
    return 1
  }

  # Write through symlinks: operate on the resolved path.
  mkdir -p -- "$(dirname -- "$target")" || return 1
  real=$(readlink -f -- "$target") || return 1
  dir=$(dirname -- "$real")
  mkdir -p -- "$dir" || return 1
  tmp=$(mktemp "$dir/.$(basename -- "$real").utilities.XXXXXX") || return 1

  if [[ -e "$real" ]]; then
    if grep -qxF -- "$MARK_START" "$real" && ! grep -qxF -- "$MARK_END" "$real"; then
      warn "$target has a start marker without an end marker; not touching it"
      rm -f -- "$tmp"
      return 1
    fi
    awk -v s="$MARK_START" -v e="$MARK_END" '
      $0 == s { skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }
    ' "$real" > "$tmp" || {
      rm -f -- "$tmp"
      return 1
    }
    # Ensure the last line is newline-terminated before appending.
    if [[ -s "$tmp" && -n "$(tail -c1 "$tmp")" ]]; then
      printf '\n' >> "$tmp"
    fi
  fi

  {
    printf '%s\n' "$MARK_START"
    cat -- "$snippet"
    printf '%s\n' "$MARK_END"
  } >> "$tmp" || {
    rm -f -- "$tmp"
    return 1
  }

  if [[ -e "$real" ]] && cmp -s -- "$tmp" "$real"; then
    rm -f -- "$tmp"
    SKIPPED+=("$target")
    return 0
  fi

  if [[ -e "$real" ]]; then
    chmod --reference="$real" -- "$tmp" || {
      rm -f -- "$tmp"
      return 1
    }
  else
    chmod 644 -- "$tmp" || {
      rm -f -- "$tmp"
      return 1
    }
  fi
  mv -f -- "$tmp" "$real" || {
    rm -f -- "$tmp"
    return 1
  }
  INSTALLED+=("$target")
  return 0
}

main() {
  log "not implemented yet"
}

[[ -n "${UTILITIES_SOURCE_ONLY:-}" ]] || main "$@"
