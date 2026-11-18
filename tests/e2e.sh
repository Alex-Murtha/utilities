#!/usr/bin/env bash
# End-to-end test: runs install.sh twice in a throwaway fedora:45 container
# as a non-root user with passwordless sudo, then checks the result.
#
# Tests what is on disk, including uncommitted changes: the working tree
# (tracked + untracked, non-ignored files) is snapshotted into a temporary git
# repo, mounted read-only at /src, and install.sh clones it from there.
#
# Run 1 pipes the script into bash (as the one-line install does); run 2 runs
# it from the file. Takes several minutes (Homebrew's first install is slow).
# Set E2E_KEEP=1 to keep the container afterwards for debugging.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
source "$ROOT/tests/lib.sh"

IMAGE=utilities-e2e:fedora45
NAME="utilities-e2e-$$"
REF=e2e
WORK=$(mktemp -d)
LOGS="$WORK/logs"
SNAP="$WORK/src"
mkdir -p "$LOGS" "$SNAP"

cleanup() {
  if [[ -n "${E2E_KEEP:-}" ]]; then
    printf 'kept container %s; logs in %s\n' "$NAME" "$LOGS"
    return
  fi
  docker rm -f "$NAME" > /dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

command -v docker > /dev/null || {
  echo "docker is required" >&2
  exit 1
}

# --- snapshot the working tree --------------------------------------------
(
  cd "$ROOT" || exit 1
  git ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' f; do
      [[ -e "$f" || -L "$f" ]] || continue # tracked but deleted
      mkdir -p "$SNAP/$(dirname -- "$f")"
      cp -a -- "$f" "$SNAP/$f"
    done
) || exit 1
if ! { git -C "$SNAP" init -q -b "$REF" &&
  git -C "$SNAP" add -A &&
  git -C "$SNAP" -c user.name=e2e -c user.email=e2e@example.invalid \
    commit -q -m snapshot; }; then
  echo "failed to snapshot working tree" >&2
  exit 1
fi

# --- container -------------------------------------------------------------
docker build -q -t "$IMAGE" - > /dev/null << 'EOF' || exit 1
FROM fedora:45
RUN dnf -y install sudo && dnf clean all \
 && useradd -m tester \
 && echo 'tester ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tester \
 && chmod 440 /etc/sudoers.d/tester
EOF
docker run -d --name "$NAME" -v "$SNAP:/src:ro" "$IMAGE" sleep infinity > /dev/null || exit 1

# Run a command as tester. The mounted snapshot is owned by the host user, so
# mark every directory safe for git via the environment (not a config file).
as_tester() {
  docker exec -u tester -w /home/tester \
    -e HOME=/home/tester -e USER=tester \
    -e UTILITIES_REPO_URL=/src -e UTILITIES_REF="$REF" \
    -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    "$NAME" "$@"
}

# zsh -c as tester, non-interactive, with a clean environment (Fedora's base
# PATH only) so the dotfiles install.sh wrote decide the rest.
in_zsh() {
  docker exec -u tester -w /home/tester \
    -e HOME=/home/tester -e USER=tester \
    "$NAME" env -i HOME=/home/tester USER=tester PATH=/usr/local/bin:/usr/bin:/bin zsh -c "$1"
}

summary_count() { # <log> <Installed|Skipped|Failed>
  sed -n "s/^$2: \([0-9]*\)\$/\1/p" "$1" | tail -n1
}

show_tail() {
  printf '      --- last lines of %s ---\n' "$1"
  tail -n 40 "$1" | sed 's/^/      /'
}

# --- run 1: piped, as the one-line install --------------------------------
echo "run 1 (curl | bash style) ..."
as_tester bash -c 'cat /src/install.sh | bash' > "$LOGS/run1.log" 2>&1
rc1=$?
assert_eq "run 1 exits 0" 0 "$rc1"
[[ "$rc1" -eq 0 ]] || show_tail "$LOGS/run1.log"

# --- run 2: from the file; everything must be skipped ---------------------
echo "run 2 (re-run) ..."
as_tester bash /src/install.sh > "$LOGS/run2.log" 2>&1
rc2=$?
assert_eq "run 2 exits 0" 0 "$rc2"
assert_eq "run 2: nothing failed" 0 "$(summary_count "$LOGS/run2.log" Failed)"
assert_eq "run 2: nothing installed (all skipped)" 0 "$(summary_count "$LOGS/run2.log" Installed)"
skipped=$(summary_count "$LOGS/run2.log" Skipped)
if [[ "${skipped:-0}" -gt 0 ]]; then _ok "run 2: items skipped ($skipped)"; else _bad "run 2: items skipped"; fi
if [[ "$rc2" -eq 0 ]]; then
  sed -n '/^Installed: /,$p' "$LOGS/run2.log" | sed 's/^/      /'
else
  show_tail "$LOGS/run2.log"
fi

# --- resulting environment ------------------------------------------------
for cmd in git gh az kubectl helm k9s yq lazygit go node npm corepack dotnet bws claude k3d devspace earth; do
  if in_zsh "command -v $cmd" > /dev/null 2>&1; then
    _ok "zsh: command -v $cmd"
  else
    _bad "zsh: command -v $cmd"
  fi
done

sdks=$(in_zsh 'dotnet --list-sdks' 2>&1)
for major in 10 11; do
  if grep -q "^$major\\." <<< "$sdks"; then
    _ok "dotnet SDK $major.x"
  else
    _bad "dotnet SDK $major.x"
    printf '      dotnet --list-sdks: %s\n' "$sdks"
  fi
done

node_v=$(in_zsh 'node --version' 2>&1)
if [[ "$node_v" == v26* ]]; then _ok "node is v26 ($node_v)"; else _bad "node is v26 (got: $node_v)"; fi

if as_tester test -x /home/tester/.azure/bin/bicep; then _ok "bicep installed"; else _bad "bicep installed"; fi
if in_zsh '/home/tester/.azure/bin/bicep --version' > /dev/null 2>&1; then _ok "bicep runs"; else _bad "bicep runs"; fi

assert_eq "one marker block in ~/.zshenv" 1 "$(as_tester grep -c '# >>> utilities >>>' /home/tester/.zshenv)"
assert_eq "one marker block in ~/.zshrc" 1 "$(as_tester grep -c '# >>> utilities >>>' /home/tester/.zshrc)"

if as_tester test -L /home/tester/.claude/hooks; then _ok "claude hooks dir is a symlink"; else _bad "claude hooks dir is a symlink"; fi

shell=$(as_tester getent passwd tester | cut -d: -f7)
assert_eq "login shell is zsh" zsh "$(basename -- "${shell:-none}")"

finish
