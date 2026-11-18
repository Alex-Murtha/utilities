#!/usr/bin/env bash
# Script 2: everything that needs a human. Run after install.sh.
# Source with SETUP_SOURCE_ONLY=1 to use the helpers without running main.
set -uo pipefail

SETUP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UTILITIES_SOURCE_ONLY=1
# shellcheck source=install.sh
source "$SETUP_DIR/install.sh"

BWS_TOKEN_FILE="${BWS_TOKEN_FILE:-$HOME/.config/bws/token}"
CODE_DIR="${CODE_DIR:-$HOME/code}"

# parse_repo_list: stdin -> one clean owner/repo per line (CRs, blanks, # comments dropped).
parse_repo_list() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line//$'\r'/}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done
}

# clone_repos <dest_root>: stdin list of owner/repo; clone each unless the dir exists.
clone_repos() {
  local dest=$1 repo name rc=0
  while IFS= read -r repo; do
    name=${repo##*/}
    if [[ -d "$dest/$name" ]]; then
      SKIPPED+=("clone $repo")
      continue
    fi
    log "clone $repo"
    if gh repo clone "$repo" "$dest/$name"; then
      INSTALLED+=("clone $repo")
    else
      FAILED+=("clone $repo")
      rc=1
    fi
  done < <(parse_repo_list)
  return "$rc"
}

# set_git_identity: set global user.name/user.email from `gh api user`, only if unset.
set_git_identity() {
  local have_name have_email json login id name email
  have_name=$(git config --global user.name 2> /dev/null || true)
  have_email=$(git config --global user.email 2> /dev/null || true)
  if [[ -n "$have_name" && -n "$have_email" ]]; then
    SKIPPED+=("git identity")
    return 0
  fi
  json=$(gh api user) || {
    warn "gh api user failed; git identity not set"
    return 1
  }
  login=$(jq -r '.login // empty' <<< "$json")
  id=$(jq -r '.id // empty' <<< "$json")
  name=$(jq -r '.name // empty' <<< "$json")
  email=$(jq -r '.email // empty' <<< "$json")
  [[ -n "$name" ]] || name=$login
  [[ -n "$email" ]] || email="$id+$login@users.noreply.github.com"
  if [[ -z "$have_name" ]]; then
    git config --global user.name "$name" || return 1
    log "git user.name set to $name"
  fi
  if [[ -z "$have_email" ]]; then
    git config --global user.email "$email" || return 1
    log "git user.email set to $email"
  fi
  INSTALLED+=("git identity")
}

# save_bws_token <token_file>: read the token from stdin; skip if the file exists.
save_bws_token() {
  local file=$1 dir tok tmp
  if [[ -e "$file" ]]; then
    SKIPPED+=("bws token")
    return 0
  fi
  IFS= read -r tok || [[ -n "$tok" ]] || true
  [[ -n "$tok" ]] || {
    warn "empty token; not saved"
    return 1
  }
  dir=$(dirname -- "$file")
  mkdir -p -- "$dir" && chmod 700 "$dir" || return 1
  tmp=$(umask 077 && mktemp "$dir/.token.XXXXXX") || return 1
  if ! { printf '%s\n' "$tok" > "$tmp" && chmod 600 "$tmp" && mv -f -- "$tmp" "$file"; }; then
    rm -f -- "$tmp"
    return 1
  fi
  INSTALLED+=("bws token")
}

# fetch_clone_list: print the CLONE_REPOS secret; empty (with a warning) if absent.
fetch_clone_list() {
  local json
  [[ -r "$BWS_TOKEN_FILE" ]] || {
    warn "no bws token at $BWS_TOKEN_FILE"
    return 0
  }
  json=$(BWS_ACCESS_TOKEN="$(cat "$BWS_TOKEN_FILE")" bws secret list --output json) || {
    warn "bws failed; no repo list"
    return 0
  }
  jq -r '[.[] | select(.key == "CLONE_REPOS") | .value][0] // empty' <<< "$json" || return 0
}

step_gh_login() {
  log "github login"
  if gh auth status > /dev/null 2>&1; then
    SKIPPED+=("gh auth")
  else
    try "gh auth login" gh auth login < /dev/tty && INSTALLED+=("gh auth")
  fi
}

step_token() {
  log "bitwarden token"
  if [[ -e "$BWS_TOKEN_FILE" ]]; then
    SKIPPED+=("bws token")
    return 0
  fi
  local tok
  printf 'Bitwarden machine-account access token (input hidden): ' > /dev/tty
  IFS= read -rs tok < /dev/tty
  printf '\n' > /dev/tty
  try "bws token" save_bws_token "$BWS_TOKEN_FILE" <<< "$tok"
}

step_clone() {
  log "clone repos"
  local list
  list=$(fetch_clone_list)
  if [[ -z "$list" ]]; then
    warn "CLONE_REPOS not found; skipping clones"
    SKIPPED+=("clone repos")
    return 0
  fi
  mkdir -p -- "$CODE_DIR"
  try "clone repos" clone_repos "$CODE_DIR" <<< "$list"
}

summary() {
  printf '\n'
  print_list Installed "${INSTALLED[@]}"
  print_list Skipped "${SKIPPED[@]}"
  print_list Failed "${FAILED[@]}"
  printf '\n'
}

main() {
  step_gh_login
  try "git identity" set_git_identity
  step_token
  log "secrets"
  try "secrets-refresh" "$SETUP_DIR/bin/secrets-refresh"
  step_clone
  summary
  cat "$UTILITIES_DIR/docs/post-setup.md"
  ((${#FAILED[@]} == 0))
}

[[ -n "${SETUP_SOURCE_ONLY:-}" ]] || main "$@"
