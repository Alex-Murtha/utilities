#!/usr/bin/env bash
# Runs every tests/*.test.sh; exits non-zero if any fail.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
rc=0
for t in tests/*.test.sh; do
  printf '== %s\n' "$t"
  bash "$t" || rc=1
done
printf '== %s\n' claude/hooks/tests.sh
bash claude/hooks/tests.sh || rc=1
exit "$rc"
