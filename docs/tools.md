# Installed tools

Everything `install.sh` and `setup-interactive.sh` install, and where each
comes from.

| Tool | Source | Script |
|---|---|---|
| `zsh` | dnf; set as login shell | install.sh |
| `git` | dnf | install.sh |
| `git-lfs` | dnf; `git lfs install` | install.sh |
| `gh` | dnf | install.sh |
| `curl` | dnf | install.sh |
| `wget` | dnf | install.sh |
| `unzip` | dnf | install.sh |
| `gcc` | dnf | install.sh |
| `fontconfig` | dnf | install.sh |
| `nano` | dnf (`KUBE_EDITOR=nano`) | install.sh |
| `which` | dnf (nvm needs it on minimal images) | install.sh |
| `zsh-autosuggestions` | dnf; sourced by the `~/.zshrc` block | install.sh |
| `zsh-syntax-highlighting` | dnf; sourced last by the `~/.zshrc` block | install.sh |
| `libatomic` | dnf (runtime dependency of node) | install.sh |
| `python3` | dnf | install.sh |
| `python3-pip` | dnf | install.sh |
| `fzf` | dnf | install.sh |
| `jq` | dnf | install.sh |
| `zoxide` | dnf | install.sh |
| `fastfetch` | dnf | install.sh |
| `tree` | dnf | install.sh |
| `libicu` | dnf (runtime dependency of .NET and bicep) | install.sh |
| `azure-cli` | dnf | install.sh |
| `kubernetes-client` | dnf (provides `kubectl`; newest `kubernetes1.XX-client`) | install.sh |
| `helm` | dnf | install.sh |
| `k9s` | dnf | install.sh |
| `yq` | dnf | install.sh |
| `lazygit` | dnf | install.sh |
| `golang` | dnf | install.sh |
| `k3d` | brew (not in Fedora) | install.sh |
| `devspace` | brew (not in Fedora) | install.sh |
| `earthbuild/tap/earth` | brew tap, [EarthBuild](https://github.com/earthbuild/earthbuild) (binary is `earth`) | install.sh |
| `homebrew` | [official installer](https://brew.sh), non-interactive | install.sh |
| `nvm` | [official installer](https://github.com/nvm-sh/nvm), pinned v0.41.0, does not edit rc files | install.sh |
| `node` | `nvm install 26`, set as nvm default | install.sh |
| `corepack` | `npm install -g corepack && corepack enable` | install.sh |
| `dotnet` | [dotnet-install.sh](https://dot.net/v1/dotnet-install.sh), SDK channels 11.0 and 10.0 into `~/.dotnet` (11.0 owns the `dotnet` muxer) | install.sh |
| `bicep` | `az bicep install` (`az bicep upgrade` if present), in `~/.azure/bin` | install.sh |
| `bws` | [Bitwarden's official installer](https://bws.bitwarden.com/install) | install.sh |
| `claude` | [official installer](https://claude.ai/install.sh) (Claude Code) | install.sh |
| `code-new-roman-nerd-font` | [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) release v3.5.1 `CodeNewRoman.zip`, into `~/.local/share/fonts/NerdFonts` | install.sh |
| `oh-my-zsh` | [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh) git checkout at a pinned commit, into `~/.oh-my-zsh`; auto-update off; plugins `git sudo extract colored-man-pages docker docker-compose kubectl helm` | install.sh |
| `powerlevel10k` | [powerlevel10k](https://github.com/romkatv/powerlevel10k) git checkout at tag v1.20.0, into `~/.oh-my-zsh/custom/themes/powerlevel10k`; config is `zsh/p10k.zsh` in this repo | install.sh |
| GitHub login, git identity | `gh auth login`, `gh api user` | setup-interactive.sh |
| Bitwarden token, secrets, repo clones | `bws` via `bin/secrets-refresh` | setup-interactive.sh |

Version pins (`NVM_VERSION`, `NERD_FONTS_VERSION`, `NODE_MAJOR`,
`DOTNET_CHANNELS`, `OMZ_REF`, `P10K_REF`) are variables at the top of
`install.sh`. `OMZ_REF` is currently
`c0140703a53eb0d22be44f7bac318d0baacc927c`; Oh My Zsh has no release tags,
so to update it, replace the value with a newer commit from its `master`
branch and re-run `install.sh`.
