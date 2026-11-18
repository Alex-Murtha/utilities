#!/usr/bin/env bash
# Minimal test helpers. Source this from a test file.

PASS=0
FAIL=0

_ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
_bad() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$1"; }

assert_eq() {
  local label=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    _ok "$label"
  else
    _bad "$label"
    printf '      expected: %q\n      actual:   %q\n' "$expected" "$actual"
  fi
}

assert_contains() {
  local label=$1 file=$2 string=$3
  if grep -qF -- "$string" "$file" 2>/dev/null; then
    _ok "$label"
  else
    _bad "$label"
    printf '      %s does not contain: %s\n' "$file" "$string"
  fi
}

assert_count() {
  local label=$1 file=$2 string=$3 n=$4 actual
  actual=$(grep -cF -- "$string" "$file" 2>/dev/null)
  if [[ "$actual" == "$n" ]]; then
    _ok "$label"
  else
    _bad "$label"
    printf '      expected %s occurrences of %s in %s, got %s\n' "$n" "$string" "$file" "$actual"
  fi
}

finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}
