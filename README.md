# WSL Ubuntu Development Environment Setup

[![CI](https://github.com/nmarxer/wsl-ubuntu-setup/actions/workflows/test.yml/badge.svg)](https://github.com/nmarxer/wsl-ubuntu-setup/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![WSL2](https://img.shields.io/badge/WSL2-Ubuntu%2022.04%2F24.04-orange)](https://docs.microsoft.com/en-us/windows/wsl/)

One-click WSL2 development environment with modern shell, language runtimes, and Windows integration.

## Quick Start

### Option 1: Clone from GitHub (Recommended)

```bash
git clone https://github.com/nmarxer/wsl-ubuntu-setup.git
cd wsl-ubuntu-setup
./wsl_ubuntu_setup.sh --full
```

### Option 2: One-liner with curl

```bash
curl -fsSL https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main/wsl_ubuntu_setup.sh -o wsl_ubuntu_setup.sh && chmod +x wsl_ubuntu_setup.sh && ./wsl_ubuntu_setup.sh --full
```

### Option 3: With Custom Configuration

```bash
git clone https://github.com/nmarxer/wsl-ubuntu-setup.git
cd wsl-ubuntu-setup
USER_FULLNAME="Your Name" USER_EMAIL="you@example.com" ./wsl_ubuntu_setup.sh --full
```

## Features

| Category | Tools Installed |
|----------|-----------------|
| **Shell** | Zsh, Oh My Posh (Catppuccin theme), zsh-autosuggestions, zsh-syntax-highlighting |
| **CLI Tools** | eza, bat, fd, ripgrep, fzf, zoxide, btop, ncdu, tldr, lazygit, lazydocker, atuin, delta |
| **Languages** | Python (pyenv + Poetry + uv), Node.js (nvm + pnpm + Bun), Go, Rust, PowerShell 7 |
| **Containers** | Docker Desktop integration, kubectl, helm, k9s |
| **Dev Tools** | Git (GPG signing), GitHub CLI, GitLab CLI, Claude Code, tmux (TPM) |
| **Security** | SSH keys (ed25519), GPG keys, nftables firewall |
| **Testing** | SIPp, k6, vegeta |

## Prerequisites

- Windows 10 (19041+) or Windows 11
- WSL2 with Ubuntu 22.04 or 24.04
- Internet connection
- ~25GB free disk space

### Quick WSL2 Setup (Windows)

```powershell
# Run in PowerShell as Administrator
wsl --install -d Ubuntu-24.04
```

## Usage

| Command | Description |
|---------|-------------|
| `./wsl_ubuntu_setup.sh --full` | Complete non-interactive installation |
| `./wsl_ubuntu_setup.sh` | Interactive menu with options |
| `./wsl_ubuntu_setup.sh --check` | Verify WSL prerequisites only |
| `./wsl_ubuntu_setup.sh --verify` | Verify installation health |
| `./wsl_ubuntu_setup.sh --help` | Show all options |

### Interactive Menu Options

```
1)  Full installation (recommended)
2)  Check WSL prerequisites only
3)  Enable systemd (requires restart)
4)  Interactive installation (by section)
5)  Resume interrupted installation
6)  Windows integration guide
7)  View installation log
8)  Reset checkpoints
q)  Quit
```

## Configuration

### Environment Variables

Set before running the script:

```bash
# Required for Git/SSH configuration
export USER_FULLNAME="Your Full Name"
export USER_EMAIL="your.email@example.com"
export USER_GITHUB="your-github-username"
export USER_GITLAB="your-gitlab-username"

# Optional: Non-interactive mode
export SUDO_PASSWORD="yourpassword"

# Optional: Corporate GitLab
export COMPANY_GITLAB="gitlab.company.com"

# Optional: Jumphost for SSH
export COMPANY_JUMPHOST="user@jumphost.company.com"

# Optional: Custom repos to clone
export REPO_LIST="project1:git@github.com:user/repo.git:~/projects/repo"

# Optional: Skip specific steps
export SKIP_SSH_VALIDATE=1    # Skip SSH key validation
export SKIP_GPG_SETUP=1       # Skip GPG key setup
export DOCKER_CHOICE=1        # 1=Docker Desktop, 2=Docker CE, 3=Skip
```

## Post-Install Checklist

After installation completes:

- [ ] **Restart WSL**: Run `wsl --shutdown` from PowerShell, then reopen Ubuntu
- [ ] **Set terminal font**: Windows Terminal → Settings → Ubuntu → Font face → JetBrainsMono Nerd Font
- [ ] **Authenticate GitHub CLI**: Run `gh auth login`
- [ ] **Authenticate GitLab CLI**: Run `glab auth login`
- [ ] **Install tmux plugins**: Start tmux, press `Ctrl+B` then `I`
- [ ] **VS Code**: Install "Remote - WSL" extension
- [ ] **Docker Desktop**: Enable WSL integration in Docker Desktop settings

## Directory Structure

```
wsl-ubuntu-setup/
├── wsl_ubuntu_setup.sh              # Main setup script (2700+ lines)
├── dotfiles/                        # Configuration files
│   ├── zshrc                        # Main Zsh config
│   ├── zshrc.d/                     # Modular Zsh configs
│   │   ├── aliases.zsh              # Modern CLI aliases
│   │   ├── functions.zsh            # Utility functions
│   │   ├── personal.zsh             # Personal shortcuts
│   │   └── tmux.zsh                 # Tmux auto-start
│   ├── ohmyposh/
│   │   └── catppuccin_mocha.omp.json  # Oh My Posh theme
│   ├── tmux.conf                    # Tmux configuration
│   └── Microsoft.PowerShell_profile.ps1  # PowerShell profile
├── tests/                           # BATS test suite
│   ├── test_helpers.bats
│   ├── test_dotfiles.bats
│   └── test_security.bats
├── .github/workflows/
│   └── test.yml                     # CI pipeline
├── README.md                        # This file
├── CLAUDE.md                        # AI assistant context
└── FRESH_INSTALL_GUIDE.md           # Detailed installation guide
```

## Customization

### Adding Custom Aliases

Edit `dotfiles/zshrc.d/personal.zsh`:

```bash
# Add your custom aliases
alias myproject='cd ~/projects/myproject'
alias deploy='./scripts/deploy.sh'
```

### Modifying Shell Prompt

Edit `dotfiles/ohmyposh/catppuccin_mocha.omp.json` to customize the theme.

### Adding Custom Functions

Edit `dotfiles/zshrc.d/functions.zsh`:

```bash
myfunction() {
    # Your function here
}
```

## Troubleshooting

### "systemd not enabled" Warning

Run the script to configure `/etc/wsl.conf`, then restart WSL:

```powershell
# From PowerShell
wsl --shutdown
# Then reopen Ubuntu
```

### SSH Key Not Working

1. Verify key was added to GitHub/GitLab
2. Test connection: `ssh -T git@github.com`
3. Check SSH agent: `ssh-add -l`

### Fonts Not Displaying Correctly

1. Download [JetBrainsMono Nerd Font](https://www.nerdfonts.com/font-downloads)
2. Install on Windows (right-click → Install for all users)
3. Configure Windows Terminal:
   - Settings → Profiles → Ubuntu → Appearance → Font face → JetBrainsMono Nerd Font

### Permission Denied Errors

```bash
# Reset checkpoints and retry
./wsl_ubuntu_setup.sh
# Select option 8 (Reset checkpoints)
# Then option 1 (Full installation)
```

### View Installation Logs

```bash
./wsl_ubuntu_setup.sh
# Select option 7 (View installation log)

# Or directly:
cat ~/.wsl_ubuntu_setup_logs/setup_*.log | tail -100
```

### Verify Installation

```bash
./wsl_ubuntu_setup.sh --verify
```

## Idempotency

The script uses a checkpoint system. Running it multiple times is safe:

- Completed steps are skipped automatically
- Failed steps can be retried
- Checkpoints stored in `~/.wsl_ubuntu_setup_logs/.checkpoint`

### Force Reinstall of a Component

```bash
# View completed checkpoints
cat ~/.wsl_ubuntu_setup_logs/.checkpoint

# Remove specific checkpoint
sed -i '/python_env/d' ~/.wsl_ubuntu_setup_logs/.checkpoint

# Re-run script
./wsl_ubuntu_setup.sh --full
```

### Available Checkpoints

| Checkpoint | Description |
|------------|-------------|
| `wsl_environment` | WSL2 prerequisites verified |
| `systemd_enable` | systemd configured in wsl.conf |
| `backup` | Existing configs backed up |
| `system_update` | apt update/upgrade completed |
| `apt_repos` | GitHub CLI repo added |
| `packages` | Base packages installed |
| `fzf` | fzf installed from GitHub |
| `shell` | Zsh, Oh My Posh, eza configured |
| `zsh_files` | Dotfiles copied |
| `optimizations` | System limits configured |
| `nftables` | Firewall configured |
| `sshd` | SSH server (openssh-server) configured |
| `python_env` | pyenv, Python, Poetry, uv |
| `nodejs_env` | nvm, Node.js, pnpm, Bun |
| `go_env` | Go installed and configured |
| `powershell` | PowerShell 7 installed |
| `containers` | Docker configured |
| `k8s_tools` | kubectl, Helm installed |
| `claude_code` | Claude Code CLI installed |
| `modern_cli_tools` | lazygit, atuin, etc. |
| `tmux` | tmux and TPM configured |
| `ssh_validate` | SSH keys validated |
| `ssh_gpg` | SSH/GPG keys generated |
| `clone_repos` | Repositories cloned |
| `final` | Project directories created |

## Security Features

- **HTTPS Validation**: External scripts downloaded only via HTTPS with TLS 1.2+
- **Retry with Backoff**: Network operations retry with exponential backoff
- **Credential Hygiene**: `SUDO_PASSWORD` cleared from environment after use
- **SSH Keys**: Ed25519 with optional passphrase (interactive mode)
- **GPG Signing**: Automatic Git commit signing
- **Firewall**: nftables configured for development ports (RFC1918 only)
- **No Hardcoded Secrets**: All credentials via environment variables

## Testing

```bash
# Install BATS (if not installed)
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local
cd ..

# Run tests
bats tests/

# Run shellcheck
shellcheck wsl_ubuntu_setup.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes
4. Run shellcheck: `shellcheck wsl_ubuntu_setup.sh`
5. Run tests: `bats tests/`
6. Commit: `git commit -m "feat: add my feature"`
7. Push: `git push origin feature/my-feature`
8. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Oh My Posh](https://ohmyposh.dev/) - Prompt theme engine
- [Catppuccin](https://github.com/catppuccin) - Color palette
- [Nerd Fonts](https://www.nerdfonts.com/) - Icon fonts
- [BATS](https://github.com/bats-core/bats-core) - Bash testing framework
