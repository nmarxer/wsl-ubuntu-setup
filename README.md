# WSL Ubuntu Development Environment Setup

One-click WSL2 development environment with modern shell, language runtimes, and Windows integration.

## Quick Start

```bash
# Clone and run
git clone https://github.com/nmarxer/devops-infrastructure.git
cd devops-infrastructure
./wsl_ubuntu_setup.sh --full
```

Or with custom configuration:

```bash
USER_FULLNAME="Your Name" USER_EMAIL="you@example.com" ./wsl_ubuntu_setup.sh --full
```

## Features

| Category | Tools Installed |
|----------|-----------------|
| **Shell** | Zsh, Oh My Posh (Catppuccin theme), zsh-autosuggestions, zsh-syntax-highlighting |
| **CLI Tools** | eza, bat, fd, ripgrep, fzf, zoxide, btop, ncdu, tldr |
| **Languages** | Python (pyenv), Node.js (nvm), Go, Rust, PowerShell 7 |
| **Containers** | Docker Desktop integration, kubectl, helm, k9s |
| **Dev Tools** | Git (with GPG signing), GitHub CLI, GitLab CLI, Claude Code |
| **Security** | SSH keys (ed25519), GPG keys, nftables firewall |

## Prerequisites

- Windows 10 (19041+) or Windows 11
- WSL2 with Ubuntu 22.04 or 24.04
- Internet connection
- ~25GB free disk space

## Configuration Options

Set environment variables before running:

```bash
# Required for Git/SSH configuration
export USER_FULLNAME="Your Full Name"
export USER_EMAIL="your.email@example.com"
export USER_GITHUB="your-github-username"
export USER_GITLAB="your-gitlab-username"

# Optional: Corporate GitLab
export COMPANY_GITLAB="gitlab.company.com"

# Optional: Jumphost
export COMPANY_JUMPHOST="user@jumphost.company.com"

# Optional: Custom repos to clone (format: name:url:path,...)
export REPO_LIST="project1:git@github.com:user/repo.git:~/projects/repo"
```

## Usage Modes

### Full Installation (Recommended)

```bash
./wsl_ubuntu_setup.sh --full
```

Installs everything with sensible defaults.

### Interactive Mode

```bash
./wsl_ubuntu_setup.sh
# Then select option 4
```

Choose which components to install.

### Resume Interrupted Installation

```bash
./wsl_ubuntu_setup.sh
# Then select option 5
```

Continues from where it left off (uses checkpoint system).

### Non-Interactive / CI Mode

```bash
SUDO_PASSWORD="yourpass" ./wsl_ubuntu_setup.sh --full
```

For automated deployments.

### Verify Installation

```bash
./wsl_ubuntu_setup.sh --verify
```

Checks all installed tools, configs, and directories after installation.

## Directory Structure

```
devops-infrastructure/
├── wsl_ubuntu_setup.sh          # Main setup script
├── wsl-bootstrap.ps1            # PowerShell launcher (Windows side)
├── wsl-setup-main.ps1           # PowerShell orchestrator
├── catppuccin_mocha.omp.json    # Oh My Posh theme
├── dotfiles/                    # Configuration files
│   ├── zshrc                    # Main Zsh config
│   ├── zshrc.d/                 # Modular Zsh configs
│   │   ├── aliases.zsh          # Modern CLI aliases
│   │   ├── functions.zsh        # Utility functions
│   │   ├── personal.zsh         # Personal shortcuts
│   │   └── tmux.zsh             # Tmux auto-start
│   ├── tmux.conf                # Tmux configuration
│   └── Microsoft.PowerShell_profile.ps1  # PowerShell profile
└── tests/                       # BATS test suite
```

## Customization

### Adding Custom Aliases

Edit `dotfiles/zshrc.d/personal.zsh`:

```bash
# Add your custom aliases
alias myproject='cd ~/projects/myproject'
```

### Modifying Shell Prompt

Edit `catppuccin_mocha.omp.json` to customize the Oh My Posh theme.

### Adding Custom Functions

Edit `dotfiles/zshrc.d/functions.zsh`:

```bash
myfunction() {
    # Your function here
}
```

## Troubleshooting

### "systemd not enabled" Warning

Run the script, let it configure `/etc/wsl.conf`, then restart WSL:

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

1. Ensure JetBrainsMono Nerd Font is installed
2. Configure Windows Terminal to use it:
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

## Idempotency

The script uses a checkpoint system. Running it multiple times is safe:

- Completed steps are skipped automatically
- Failed steps can be retried
- Checkpoints stored in `~/.wsl_ubuntu_setup_logs/.checkpoint`

To force reinstall of a component:

```bash
# Remove specific checkpoint
sed -i '/shell/d' ~/.wsl_ubuntu_setup_logs/.checkpoint
# Re-run script
./wsl_ubuntu_setup.sh --full
```

## Security Features

- **HTTPS Validation**: External scripts downloaded only via HTTPS with TLS 1.2+
- **Credential Hygiene**: `SUDO_PASSWORD` cleared from environment after use
- **SSH Keys**: Ed25519 with optional passphrase (interactive mode)
- **GPG Signing**: Automatic Git commit signing
- **Firewall**: nftables configured for development ports (RFC1918 only)

## Testing

```bash
# Install BATS
git clone https://github.com/bats-core/bats-core.git
./bats-core/install.sh ~/.local

# Run tests
bats tests/
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run shellcheck: `shellcheck wsl_ubuntu_setup.sh`
5. Run tests: `bats tests/`
6. Submit a pull request

## License

MIT License - See LICENSE file for details.
