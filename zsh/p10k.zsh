# powerlevel10k configuration.
#
# Hand-written, NOT produced by `p10k configure`. That wizard writes a ~1700
# line ~/.p10k.zsh into $HOME, which would drift from this repo. This covers
# the same ground in a fiftieth of the size.
#
# Sourced by ~/.zshrc (the snippets/zshrc block) after the theme itself, which
# is the order p10k expects: the theme defines the machinery, this sets the
# parameters it reads when it builds each prompt.

# Which icon set the segments draw from. Unset, p10k falls back to its
# "powerline-patched font" set, which is not a Nerd Font set at all: it reaches
# for bare Unicode like U+2388 (⎈, kubernetes) and U+2601 (☁, azure), and spells
# the node icon as the literal word "Node". Nothing renders those three from
# CodeNewRoman, so the terminal substitutes another font per glyph -- which is
# the mismatched, wrong-width rendering this produced in editor built-in terminals.
#
# nerdfont-v3 moves every icon into the private use area that CodeNewRoman
# actually carries (installed by install.sh), so no fallback font is consulted. v3 rather than v2 because the packaged font is
# nerd-fonts 3.x, and the two releases moved the codepoints.
typeset -g POWERLEVEL9K_MODE=nerdfont-v3

# Strip the padding baked into the icon set. Several nerdfont-v3 icons ship with
# a hardcoded trailing space -- OK, node, azure and time do, kubernetes does not
# -- because p10k's right prompt normally trails the icon after its content,
# where that space separates it from the next segment. With the icons moved in
# front (see ICON_BEFORE_CONTENT below) the same space lands between an icon and
# its own content instead, on top of the separator p10k already inserts there.
# That put two spaces inside a segment and one between segments, which reads as
# each icon belonging to the segment on its left.
#
# `none` trims every icon uniformly, which also settles the kubernetes/azure
# inconsistency. The spacing that remains is set deliberately below.
typeset -g POWERLEVEL9K_ICON_PADDING=none

# Lean look: no segment backgrounds, so no powerline pills. Colour lives in the
# text instead, and the separators are plain spaces rather than glyph wedges.
typeset -g POWERLEVEL9K_BACKGROUND=
typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=
# A pipe closing each segment off. Grouping used to be carried by spacing alone
# -- two spaces between segments against the one p10k puts between an icon and
# its content -- which left it to the eye to judge which side a glyph belonged
# to. An explicit delimiter states it, so the icon keeps p10k's default single
# space and the pipe does the separating. Tightening the icon gap on top of this
# was tried and reverted: it read as cramped and bought nothing the delimiter
# had not already fixed.
#
# 244 is the grey the clock used to wear, and the two have swapped jobs below:
# structure should recede, and the time is content rather than furniture. p10k
# re-applies the segment style after any separator containing a `%`, so the
# colour cannot leak into the segment that follows.
typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' %244F| '
typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=''

# A rule across the full terminal width above every prompt. This is the bit that
# makes a command's start easy to find when scrolling back through output.
typeset -g POWERLEVEL9K_SHOW_RULER=true
typeset -g POWERLEVEL9K_RULER_CHAR='─'
typeset -g POWERLEVEL9K_RULER_FOREGROUND=240

# The ruler already separates prompts, so no extra blank line on top of it.
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=false

# `newline` is what puts the input on its own line: everything before it is the
# info line, everything after is the line you type on.
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs newline prompt_char)

# Right side of the info line. The toolchain segments are contextual -- p10k
# only shows them in a directory that actually uses that toolchain -- so they
# cost nothing in an unrelated directory.
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
  status
  command_execution_time
  background_jobs
  dotnet_version
  go_version
  node_version
  kubecontext
  azure
  time
)

# Full path. p10k truncates by default; 0 disables that, and $HOME still
# collapses to ~ regardless.
typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=0
typeset -g POWERLEVEL9K_DIR_FOREGROUND=39

# Fallback for anything the formatter below does not colour itself, and the
# colour of the whole segment while gitstatus is still working.
typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=76
typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=178
typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=178
typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=244

# The git segment, coloured per element rather than as one blob.
#
# p10k paints a segment a single colour chosen by state, which is why the
# settings above are all there is by default: clean is green, dirty is amber,
# and the branch, the upstream and every count share whichever won. Finer
# control has exactly one entry point -- a content expansion, a function that
# assembles the string itself -- so this is longer than the rest of the file
# put together and there is no shorter version of it.
#
# The icons and the layout are deliberately the same ones p10k's own renderer
# uses, taken from the nerdfont-v3 set; only the colour is new. Icon spacing is
# spelled out here because ICON_PADDING=none strips the icon set's trailing
# spaces and re-adds them for a handful of VCS icons, and the formatter bypasses
# that machinery entirely.
typeset -g POWERLEVEL9K_VCS_BRANCH_ICON=' '
typeset -g POWERLEVEL9K_VCS_REMOTE_BRANCH_ICON=' '
typeset -g POWERLEVEL9K_VCS_COMMIT_ICON=' '
typeset -g POWERLEVEL9K_VCS_TAG_ICON=' '
typeset -g POWERLEVEL9K_VCS_STASH_ICON=''
typeset -g POWERLEVEL9K_VCS_INCOMING_CHANGES_ICON=''
typeset -g POWERLEVEL9K_VCS_OUTGOING_CHANGES_ICON=''
typeset -g POWERLEVEL9K_VCS_STAGED_ICON=''
typeset -g POWERLEVEL9K_VCS_UNSTAGED_ICON=''
typeset -g POWERLEVEL9K_VCS_UNTRACKED_ICON=''

function amurtha_git_formatter() {
  emulate -L zsh

  # $1 is 0 while gitstatus is still resolving the repository. Everything goes
  # grey in that window, so a slow repo settles into colour once rather than
  # flashing a wrong one first.
  if (( $1 )); then
    local meta=%244F branch=%76F remote=%111F sync=%178F
    local staged=%76F unstaged=%178F untracked=%39F
    local conflict=%196F stash=%134F action=%196F
  else
    local meta=%244F branch=%244F remote=%244F sync=%244F
    local staged=%244F unstaged=%244F untracked=%244F
    local conflict=%244F stash=%244F action=%244F
  fi

  local out

  # What HEAD is: a branch, else a tag, else the bare commit when detached.
  # `%` doubled throughout -- a branch name may legitimately contain one, and
  # this string is about to be prompt-expanded.
  if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
    out+="${branch}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${${(V)VCS_STATUS_LOCAL_BRANCH}//\%/%%}"
  elif [[ -n $VCS_STATUS_TAG ]]; then
    out+="${meta}${(g::)POWERLEVEL9K_VCS_TAG_ICON}${${(V)VCS_STATUS_TAG}//\%/%%}"
  else
    out+="${meta}${(g::)POWERLEVEL9K_VCS_COMMIT_ICON}${VCS_STATUS_COMMIT[1,8]}"
  fi

  # Upstream, but only when it is not just the local name echoed back.
  if [[ -n $VCS_STATUS_REMOTE_BRANCH && $VCS_STATUS_REMOTE_BRANCH != $VCS_STATUS_LOCAL_BRANCH ]]; then
    out+=" ${remote}${(g::)POWERLEVEL9K_VCS_REMOTE_BRANCH_ICON}${${(V)VCS_STATUS_REMOTE_BRANCH}//\%/%%}"
  fi

  # Divergence: from the upstream first, then from the push remote when it is
  # tracked separately.
  (( VCS_STATUS_COMMITS_BEHIND ))      && out+=" ${sync}${(g::)POWERLEVEL9K_VCS_INCOMING_CHANGES_ICON}${VCS_STATUS_COMMITS_BEHIND}"
  (( VCS_STATUS_COMMITS_AHEAD ))       && out+=" ${sync}${(g::)POWERLEVEL9K_VCS_OUTGOING_CHANGES_ICON}${VCS_STATUS_COMMITS_AHEAD}"
  (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && out+=" ${sync}${(g::)POWERLEVEL9K_VCS_INCOMING_CHANGES_ICON}${VCS_STATUS_PUSH_COMMITS_BEHIND}"
  (( VCS_STATUS_PUSH_COMMITS_AHEAD ))  && out+=" ${sync}${(g::)POWERLEVEL9K_VCS_OUTGOING_CHANGES_ICON}${VCS_STATUS_PUSH_COMMITS_AHEAD}"

  # The working tree, ordered by how much it should worry you.
  (( VCS_STATUS_NUM_CONFLICTED )) && out+=" ${conflict}${VCS_STATUS_NUM_CONFLICTED}"
  (( VCS_STATUS_NUM_STAGED ))     && out+=" ${staged}${(g::)POWERLEVEL9K_VCS_STAGED_ICON}${VCS_STATUS_NUM_STAGED}"
  (( VCS_STATUS_NUM_UNSTAGED ))   && out+=" ${unstaged}${(g::)POWERLEVEL9K_VCS_UNSTAGED_ICON}${VCS_STATUS_NUM_UNSTAGED}"
  (( VCS_STATUS_NUM_UNTRACKED ))  && out+=" ${untracked}${(g::)POWERLEVEL9K_VCS_UNTRACKED_ICON}${VCS_STATUS_NUM_UNTRACKED}"
  (( VCS_STATUS_STASHES ))        && out+=" ${stash}${(g::)POWERLEVEL9K_VCS_STASH_ICON}${VCS_STATUS_STASHES}"

  # A half-finished merge or rebase outranks everything else on the line.
  [[ -n $VCS_STATUS_ACTION ]] && out+=" ${action}${${(V)VCS_STATUS_ACTION}//\%/%%}"

  typeset -g amurtha_git_format=$out
}

# Registers the function for the arithmetic call below, which is how p10k wants
# a formatter invoked: the expansion evaluates it for the side effect and then
# reads the global it set.
functions -M amurtha_git_formatter 2>/dev/null
typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((amurtha_git_formatter(1)))+${amurtha_git_format}}'
typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((amurtha_git_formatter(0)))+${amurtha_git_format}}'

typeset -g POWERLEVEL9K_KUBECONTEXT_FOREGROUND=134
typeset -g POWERLEVEL9K_AZURE_FOREGROUND=32
# Off-white, and ANSI 7 rather than a 256-cube index like its neighbours: slot 7
# is #f7f1ff from ../theme/amurtha-dark.json, which is already off-white by design
# -- it is the editor foreground, not a pure #ffffff -- so the clock tracks the
# theme rather than pinning a second copy of the colour. It took 244 before the
# delimiter above claimed that grey.
typeset -g POWERLEVEL9K_TIME_FOREGROUND=7
# 12-hour with a meridiem, unpadded. The right prompt is laid out from the right
# edge, so a single-digit hour shifts every segment on the line a column left --
# accepted deliberately, as the leading zero was the worse of the two. `%l`
# would hold the width by padding with a space, but that reads as a gap after
# the delimiter, so it is no way out either.
#
# `%-I` is a glibc extension rather than POSIX, which is fine on both hosts and
# worth knowing only if this file is ever read somewhere musl-based.
typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%-I:%M %p}'
typeset -g POWERLEVEL9K_DOTNET_VERSION_FOREGROUND=140

# The Visual Studio mark instead of the icon set's default. nerdfont-v3 uses
# dev-dotnet (U+E77F) here, the old .NET swoosh wordmark, which collapses to
# something indistinguishable from a `~` once the Mono font squeezes it into a
# single cell. dev-visualstudio holds its shape at that size.
#
# The parameter is DOTNET_ICON rather than DOTNET_VERSION_ICON: p10k names icon
# overrides after the icon, not the segment, and prompt_dotnet_version asks for
# DOTNET_ICON. Confirmed present in CodeNewRomanNerdFontMono-Regular.otf before
# choosing it -- an absent glyph is how the prompt ended up full of tofu the
# first time. Others the font carries, if this one ever palls:
# md-language_csharp (U+F031B), dev-csharp (U+E7B2), seti-c_sharp (U+E648),
# md-dot_net (U+F0AAE), dev-dotnetcore (U+E7C6),
# md-microsoft_visual_studio (U+F0610).
typeset -g POWERLEVEL9K_DOTNET_ICON='\UE70C'
typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND=37
typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=70

# Every icon sits to the left of its content, on both sides of the prompt.
# p10k mirrors the right prompt by default, trailing each icon after the text it
# labels, so the same glyph lands on a different side depending on which half of
# the line the segment happens to sit in. One column for every icon is the
# easier thing to scan.
#
# Set without a segment name, which is the global fallback p10k consults when a
# segment has no setting of its own. The two sides read this with opposite
# defaults -- the left prompt asks "is it not false", the right asks "is it
# true" -- so `true` is already what the left prompt does and only the right
# prompt actually flips.
typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=true

# POWERLEVEL9K_{KUBECONTEXT,AZURE}_SHOW_ON_COMMAND is deliberately NOT set here.
#
# Those segments are always-on precisely when the variable does not exist: p10k
# gates on $+parameters[VAR], which tests existence rather than emptiness, so
# assigning an empty value registers a "show only for these commands" filter
# with an empty command list -- and the segment then never appears at all.

# Only mention a command's duration once it was slow enough to care about.
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=178

typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=76
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=196
typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'

# Instant prompt caches a snapshot of the prompt to draw before zshrc finishes.
# It also warns loudly about any console output during initialisation, so the
# quiet trade is to leave it off.
typeset -g POWERLEVEL9K_DISABLE_INSTANT_PROMPT=true
