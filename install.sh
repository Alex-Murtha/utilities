#!/usr/bin/env bash
# Fedora workstation bootstrap. Idempotent; safe to re-run.
# Source with UTILITIES_SOURCE_ONLY=1 to use the helpers without running main.
set -uo pipefail

UTILITIES_DIR="${UTILITIES_DIR:-$HOME/code/utilities}"
# Overridable for the end-to-end test only.
UTILITIES_REPO_URL="${UTILITIES_REPO_URL:-https://github.com/Alex-Murtha/utilities.git}"
UTILITIES_REF="${UTILITIES_REF:-main}"

# Pinned versions.
NVM_VERSION=v0.41.0
NERD_FONTS_VERSION=v3.5.1
NODE_MAJOR=26
DOTNET_CHANNELS=(11.0 10.0) # first one owns the dotnet muxer

DNF_PACKAGES=(
  zsh git git-lfs gh curl wget unzip gcc fontconfig nano which
  libatomic
  python3 python3-pip
  fzf jq zoxide fastfetch tree
  libicu # needed by the .NET SDK and bicep (not on minimal images)
  azure-cli
  kubernetes-client helm k9s yq # kubernetes-client: provided by every kubernetes1.XX-client; dnf picks the newest
  lazygit
  golang
)

BREW_FORMULAE=(k3d devspace earthbuild/tap/earth)

BREW=/home/linuxbrew/.linuxbrew/bin/brew
NVM_DIR="$HOME/.nvm"
FONT_DIR="$HOME/.local/share/fonts/NerdFonts"

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

# same_content <a> <b>: true if both files have identical bytes. Uses
# coreutils only (cmp/diff are not on minimal Fedora images).
same_content() {
  local a b
  a=$(sha256sum < "$1") || return 1
  b=$(sha256sum < "$2") || return 1
  [[ "$a" == "$b" ]]
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

  if [[ -e "$real" ]] && same_content "$tmp" "$real"; then
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

# link_claude_hooks <repo_hooks_dir> <claude_dir>
# Make <claude_dir>/hooks a symlink to the repo's hooks directory. A real
# directory is moved aside to hooks.bak.<timestamp> first.
link_claude_hooks() {
  local src=$1 cdir=$2 dest="$2/hooks" bak
  mkdir -p -- "$cdir" || return 1
  if [[ -L "$dest" ]]; then
    if [[ "$(readlink -- "$dest")" == "$src" ]]; then
      SKIPPED+=("$dest")
      return 0
    fi
    rm -f -- "$dest" || return 1
  elif [[ -e "$dest" ]]; then
    bak="$dest.bak.$(date +%Y%m%d%H%M%S)"
    mv -- "$dest" "$bak" || return 1
    log "moved existing $dest to $bak"
  fi
  ln -s -- "$src" "$dest" || return 1
  INSTALLED+=("$dest")
}

# merge_claude_settings <hooks_json> <settings_file> <hooks_dir>
# Replace .hooks in the settings file with the template's .hooks (placeholder
# __HOOKS_DIR__ -> hooks_dir); every other key is kept. Missing file is created.
merge_claude_settings() {
  local tpl=$1 settings=$2 hdir=$3 real tmp
  real=$settings
  [[ -L "$settings" ]] && real=$(readlink -f -- "$settings")
  mkdir -p -- "$(dirname -- "$real")" || return 1
  if [[ -e "$real" ]] && ! jq -e . "$real" > /dev/null 2>&1; then
    warn "$settings is not valid JSON; leaving it untouched"
    return 1
  fi
  tmp=$(mktemp "$(dirname -- "$real")/.settings.XXXXXX") || return 1
  if [[ -e "$real" ]]; then
    jq --arg d "$hdir" --slurpfile t "$tpl" \
      '.hooks = ($t[0].hooks | walk(if type == "string" then gsub("__HOOKS_DIR__"; $d) else . end))' \
      "$real" > "$tmp"
  else
    jq -n --arg d "$hdir" --slurpfile t "$tpl" \
      '{} | .hooks = ($t[0].hooks | walk(if type == "string" then gsub("__HOOKS_DIR__"; $d) else . end))' > "$tmp"
  fi || {
    rm -f -- "$tmp"
    return 1
  }
  if [[ -e "$real" ]]; then
    chmod --reference="$real" -- "$tmp" || {
      rm -f -- "$tmp"
      return 1
    }
  else
    chmod 644 -- "$tmp"
  fi
  if [[ -e "$real" ]] && same_content "$tmp" "$real"; then
    rm -f -- "$tmp"
    SKIPPED+=("$settings")
    return 0
  fi
  mv -f -- "$tmp" "$real" || {
    rm -f -- "$tmp"
    return 1
  }
  INSTALLED+=("$settings")
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

prelude() {
  [[ "$(id -u)" -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
  [[ -r /etc/os-release ]] || die "/etc/os-release not found; this script supports Fedora only"
  # shellcheck disable=SC1091
  [[ "$(. /etc/os-release && printf '%s' "${ID:-}")" == fedora ]] ||
    die "this script supports Fedora only"
  USER="${USER:-$(id -un)}"

  log "sudo is needed for dnf and the login shell"
  sudo -v || die "sudo authentication failed"
  while sleep 60; do sudo -n true; done 2> /dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2> /dev/null' EXIT

  export PATH="$HOME/.local/bin:$PATH"
}

step_dnf() {
  log "dnf packages"
  local p missing=()
  for p in "${DNF_PACKAGES[@]}"; do
    rpm -q --quiet --whatprovides "$p" || missing+=("$p")
  done
  if ((${#missing[@]})); then
    sudo dnf install -y "${missing[@]}" || die "dnf install failed: ${missing[*]}"
    INSTALLED+=("dnf: ${missing[*]}")
  else
    SKIPPED+=("dnf packages")
  fi

  local zsh_path shell
  zsh_path=$(command -v zsh) || die "zsh not found after dnf install"
  shell=$(getent passwd "$USER" | cut -d: -f7)
  if [[ "$shell" == "$zsh_path" ]]; then
    SKIPPED+=("login shell zsh")
  else
    sudo usermod -s "$zsh_path" "$USER" || die "could not set zsh as the login shell"
    INSTALLED+=("login shell zsh")
  fi

  if [[ "$(git config --global --get filter.lfs.required)" == true ]]; then
    SKIPPED+=("git lfs")
  else
    git lfs install > /dev/null || die "git lfs install failed"
    INSTALLED+=("git lfs")
  fi

  if [[ "$(git config --global --get pull.rebase)" == true ]]; then
    SKIPPED+=("git pull.rebase")
  else
    git config --global pull.rebase true || die "could not set git pull.rebase"
    INSTALLED+=("git pull.rebase")
  fi
}

step_clone() {
  log "clone $UTILITIES_REPO_URL to $UTILITIES_DIR"
  local parent tmp before after
  if [[ -d "$UTILITIES_DIR/.git" ]]; then
    before=$(git -C "$UTILITIES_DIR" rev-parse HEAD 2> /dev/null)
    if ! git -C "$UTILITIES_DIR" pull --ff-only -q; then
      warn "could not fast-forward $UTILITIES_DIR; continuing with the existing checkout"
    fi
    after=$(git -C "$UTILITIES_DIR" rev-parse HEAD 2> /dev/null)
    if [[ "$before" == "$after" ]]; then
      SKIPPED+=("utilities repo")
    else
      INSTALLED+=("utilities repo (updated)")
    fi
    return 0
  fi
  [[ -e "$UTILITIES_DIR" ]] && die "$UTILITIES_DIR exists but is not a git checkout"
  # Clone next to the target, then move into place: a failed clone leaves nothing behind.
  parent=$(dirname -- "$UTILITIES_DIR")
  mkdir -p -- "$parent" || die "could not create $parent"
  tmp=$(mktemp -d "$parent/.utilities.XXXXXX") || die "could not create a temp dir in $parent"
  if ! git clone -q --branch "$UTILITIES_REF" "$UTILITIES_REPO_URL" "$tmp/repo"; then
    rm -rf -- "$tmp"
    die "git clone failed"
  fi
  mv -- "$tmp/repo" "$UTILITIES_DIR" || {
    rm -rf -- "$tmp"
    die "could not move the clone into $UTILITIES_DIR"
  }
  rmdir -- "$tmp"
  INSTALLED+=("utilities repo")
}

install_brew() {
  if [[ -x "$BREW" ]]; then
    SKIPPED+=("homebrew")
    return 0
  fi
  local script
  script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return 1
  NONINTERACTIVE=1 bash -c "$script" || return 1
  INSTALLED+=("homebrew")
}

install_formula() {
  local f=$1
  if "$BREW" list --formula --versions "$f" > /dev/null 2>&1; then
    SKIPPED+=("brew: $f")
    return 0
  fi
  "$BREW" install "$f" || return 1
  INSTALLED+=("brew: $f")
}

step_brew() {
  log "homebrew"
  try homebrew install_brew || return 0
  eval "$("$BREW" shellenv)"
  local f
  for f in "${BREW_FORMULAE[@]}"; do
    try "brew: $f" install_formula "$f"
  done
}

install_nvm() {
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    SKIPPED+=("nvm")
    return 0
  fi
  local script
  script=$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh") || return 1
  PROFILE=/dev/null NVM_DIR="$NVM_DIR" bash -c "$script" || return 1
  INSTALLED+=("nvm $NVM_VERSION")
}

# Newest installed node directory for NODE_MAJOR, or nothing.
node_dir() {
  compgen -G "$NVM_DIR/versions/node/v$NODE_MAJOR.*" | sort -V | tail -n1
}

install_node() {
  if [[ -n "$(node_dir)" && "$(cat "$NVM_DIR/alias/default" 2> /dev/null)" == "$NODE_MAJOR" ]]; then
    SKIPPED+=("node $NODE_MAJOR")
    return 0
  fi
  # nvm.sh is not written for set -u; run it in a subshell without it.
  (
    set +u
    export NVM_DIR
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" || exit 1
    nvm install "$NODE_MAJOR" && nvm alias default "$NODE_MAJOR"
  ) || return 1
  INSTALLED+=("node $NODE_MAJOR")
}

install_corepack() {
  if command -v corepack > /dev/null; then
    SKIPPED+=("corepack")
    return 0
  fi
  npm install -g corepack || return 1
  corepack enable || return 1
  INSTALLED+=("corepack")
}

# install_dotnet <channel> [extra dotnet-install.sh args...]
install_dotnet() {
  local channel=$1 script
  shift
  if "$HOME/.dotnet/dotnet" --list-sdks 2> /dev/null | grep -q "^${channel%%.*}\."; then
    SKIPPED+=(".NET SDK $channel")
    return 0
  fi
  script=$(curl -fsSL https://dot.net/v1/dotnet-install.sh) || return 1
  bash -c "$script" dotnet-install.sh --channel "$channel" \
    --install-dir "$HOME/.dotnet" --no-path "$@" || return 1
  INSTALLED+=(".NET SDK $channel")
}

install_bicep() {
  local bicep="$HOME/.azure/bin/bicep" before after
  if [[ ! -x "$bicep" ]]; then
    az bicep install || return 1
    INSTALLED+=("bicep")
    return 0
  fi
  before=$("$bicep" --version 2> /dev/null)
  az bicep upgrade || return 1
  after=$("$bicep" --version 2> /dev/null)
  if [[ "$before" == "$after" ]]; then
    SKIPPED+=("bicep")
  else
    INSTALLED+=("bicep (upgraded)")
  fi
}

install_bws() {
  if command -v bws > /dev/null; then
    SKIPPED+=("bws")
    return 0
  fi
  local script
  script=$(curl -fsSL https://bws.bitwarden.com/install) || return 1
  sh -c "$script" || return 1
  INSTALLED+=("bws")
}

install_claude() {
  if [[ -x "$HOME/.local/bin/claude" ]]; then
    SKIPPED+=("claude code")
    return 0
  fi
  local script
  script=$(curl -fsSL https://claude.ai/install.sh) || return 1
  bash -c "$script" || return 1
  INSTALLED+=("claude code")
}

step_installers() {
  log "official installers"
  if try nvm install_nvm && try "node $NODE_MAJOR" install_node; then
    local d
    d=$(node_dir)
    [[ -n "$d" ]] && export PATH="$d/bin:$PATH"
    try corepack install_corepack
  fi

  local i ch
  for i in "${!DOTNET_CHANNELS[@]}"; do
    ch=${DOTNET_CHANNELS[$i]}
    if ((i == 0)); then
      try ".NET SDK $ch" install_dotnet "$ch"
    else
      try ".NET SDK $ch" install_dotnet "$ch" --skip-non-versioned-files
    fi
  done

  try bicep install_bicep
  try bws install_bws
  try "claude code" install_claude
}

install_font() {
  local name="CodeNewRoman Nerd Font $NERD_FONTS_VERSION" parent tmp
  if [[ "$(cat "$FONT_DIR/.version" 2> /dev/null)" == "$NERD_FONTS_VERSION" ]]; then
    SKIPPED+=("$name")
    return 0
  fi
  parent=$(dirname -- "$FONT_DIR")
  mkdir -p -- "$parent" || return 1
  tmp=$(mktemp -d "$parent/.NerdFonts.XXXXXX") || return 1
  if curl -fsSL -o "$tmp/font.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_VERSION/CodeNewRoman.zip" &&
    mkdir "$tmp/dir" &&
    unzip -q "$tmp/font.zip" -d "$tmp/dir" &&
    printf '%s\n' "$NERD_FONTS_VERSION" > "$tmp/dir/.version" &&
    rm -rf -- "$FONT_DIR" &&
    mv -- "$tmp/dir" "$FONT_DIR"; then
    rm -rf -- "$tmp"
  else
    rm -rf -- "$tmp"
    return 1
  fi
  fc-cache -f > /dev/null || return 1
  INSTALLED+=("$name")
}

step_font() {
  log "nerd font"
  try "nerd font" install_font
}

step_snippets() {
  log "shell snippets"
  try "zshenv snippet" apply_snippet "$UTILITIES_DIR/snippets/zshenv" "$HOME/.zshenv"
  try "zshrc snippet" apply_snippet "$UTILITIES_DIR/snippets/zshrc" "$HOME/.zshrc"
  try "lazygit snippet" apply_snippet "$UTILITIES_DIR/snippets/lazygit.yml" "$HOME/.config/lazygit/config.yml"
}

step_claude() {
  log "claude code hooks"
  try "claude hooks" link_claude_hooks "$UTILITIES_DIR/claude/hooks" "$HOME/.claude"
  try "claude settings" merge_claude_settings "$UTILITIES_DIR/claude/settings-hooks.json" \
    "$HOME/.claude/settings.json" "$HOME/.claude/hooks"
}

print_list() { # <title> <items...>
  local title=$1 item
  shift
  printf '%s: %d\n' "$title" "$#"
  for item in "$@"; do
    printf '  - %s\n' "$item"
  done
}

summary() {
  printf '\n'
  print_list Installed "${INSTALLED[@]}"
  print_list Skipped "${SKIPPED[@]}"
  print_list Failed "${FAILED[@]}"
  printf '\n'
  if ((${#FAILED[@]})); then
    printf 'Some steps failed; fix them and re-run install.sh.\n'
    exit 1
  fi
  printf 'Next: open a new zsh and run ~/code/utilities/setup-interactive.sh\n'
}

main() {
  prelude
  step_dnf
  step_clone
  step_brew
  step_installers
  step_font
  step_snippets
  step_claude
  summary
}

[[ -n "${UTILITIES_SOURCE_ONLY:-}" ]] || main "$@"
