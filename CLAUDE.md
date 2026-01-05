# CLAUDE.md

wsl-ubuntu-setup: One-click WSL2 development environment setup with shell, languages, and Windows integration.

## Commands

| Action | Command | Description |
|--------|---------|-------------|
| Full Install | `./wsl_ubuntu_setup.sh --full` | Complete non-interactive installation |
| Interactive | `./wsl_ubuntu_setup.sh` | Menu-based installation |
| Orchestrated | `./wsl_ubuntu_setup.sh --orchestrated` | PowerShell launcher mode |
| Check | `./wsl_ubuntu_setup.sh --check` | Verify WSL prerequisites |
| Test | `bats tests/` | Run BATS test suite |
| Lint | `shellcheck wsl_ubuntu_setup.sh` | Check shell script quality |

## Architecture

| Layer | Technology | Usage |
|-------|------------|-------|
| Main Script | Bash | `wsl_ubuntu_setup.sh` - checkpoint-based idempotent installer |
| Shell Config | Zsh + Oh My Posh | `dotfiles/zshrc`, `dotfiles/zshrc.d/*.zsh` |
| Prompt Theme | Oh My Posh | `dotfiles/ohmyposh/catppuccin_mocha.omp.json` |
| Terminal | tmux | `dotfiles/tmux.conf` with Windows clipboard |
| PowerShell | Profile | `dotfiles/Microsoft.PowerShell_profile.ps1` |
| Tests | BATS | `tests/*.bats` |

## Environment

| Variable | Purpose |
|----------|---------|
| `USER_FULLNAME` | Git author name |
| `USER_EMAIL` | Git/SSH email |
| `USER_GITHUB` | GitHub username |
| `USER_GITLAB` | GitLab username |
| `SUDO_PASSWORD` | Non-interactive sudo (cleared after use) |
| `REPO_LIST` | Custom repos to clone (format: `name:url:path,...`) |

## Key Components

| Component | What It Installs |
|-----------|-----------------|
| Shell | Zsh, Oh My Posh, zsh-autosuggestions, zsh-syntax-highlighting |
| CLI Tools | eza, bat, fd, ripgrep, fzf, zoxide, btop, lazygit, atuin |
| Languages | Python (pyenv), Node.js (nvm), Go, Rust, PowerShell 7 |
| Containers | Docker Desktop integration, kubectl, helm |
| Security | SSH keys (ed25519), GPG signing, nftables firewall |

## Rules

- **NEVER**: Modify script without running `shellcheck wsl_ubuntu_setup.sh`
- **ALWAYS**: Test changes with `bats tests/` before committing
- **ALWAYS**: Keep script idempotent (use checkpoint system)
- **BEFORE COMMIT**: Verify all functions have proper error handling
