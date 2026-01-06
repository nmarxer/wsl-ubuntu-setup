# WSL Ubuntu Fresh Install Guide

Complete walkthrough of what happens during a fresh `./wsl_ubuntu_setup.sh --full` installation.

## Before You Begin

### Windows Prerequisites

| Requirement | How to Get It |
|-------------|---------------|
| Windows 10 (19041+) or 11 | Windows Update |
| WSL2 enabled | `wsl --install` in PowerShell (Admin) |
| Ubuntu 22.04 or 24.04 | `wsl --install -d Ubuntu-24.04` |
| Windows Terminal | Microsoft Store |
| Docker Desktop (optional) | [docker.com](https://www.docker.com/products/docker-desktop/) |

### Verify WSL2 is Ready

```powershell
# In PowerShell
wsl --list --verbose
# Should show Ubuntu with VERSION 2
```

---

## Installation Phases (Chronological Order)

### Phase 1: Prerequisites & Environment (2-3 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 1.1 | `wsl_environment` | Verifies WSL2, Ubuntu 22.04/24.04, x86_64/ARM64, 25GB+ disk, internet, sudo |
| 1.2 | `systemd_enable` | Creates `/etc/wsl.conf` with systemd=true (**requires WSL restart**) |
| 1.3 | `backup` | Backs up `~/.bashrc`, `~/.zshrc`, `~/.gitconfig`, `~/.ssh/` to `~/backup_preinstall_YYYYMMDD/` |

### Phase 2: System Updates (5-10 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 2.1 | `system_update` | `apt update && apt upgrade && apt dist-upgrade && apt autoremove` |
| 2.2 | `apt_repos` | Adds GitHub CLI repository with GPG key |

### Phase 3: Package Installation (5-8 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 3.1 | `packages` | Installs 25+ packages: git, zsh, bat, fd-find, ripgrep, btop, ncdu, tldr, zoxide, nmap, tcpdump, python3-pip, tmux, gh, glab, build-essential, libssl-dev, etc. |
| 3.2 | `fzf` | Clones fzf from GitHub (apt version is outdated), installs to `~/.fzf` |

### Phase 4: Shell Configuration (3-5 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 4.1 | `shell` | Sets Zsh as default, installs zsh-autosuggestions, zsh-syntax-highlighting, Oh My Posh, Rust/Cargo, eza, creates fd symlink |
| 4.2 | `zsh_files` | Copies dotfiles: `~/.zshrc`, `~/.zshrc.d/*.zsh`, `~/.tmux.conf` from repo |

### Phase 5: System Optimization & SSH (1-2 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 5.1 | `optimizations` | Sets `fs.inotify.max_user_watches=524288`, increases nofile/nproc limits |
| 5.2 | `nftables` | Configures firewall: allows ports 222, 80, 443, 3000, 8000 from RFC1918 only |
| 5.3 | `sshd` | Installs openssh-server on port 222 with security-hardened config (no root login, strong ciphers) |
| 5.4 | `tailscale` | Installs Tailscale VPN client and daemon |

### Phase 6: Language Runtimes (10-15 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 6.1 | `python_env` | Installs pyenv, Python 3.12.x, Poetry, uv (fast package manager) |
| 6.2 | `nodejs_env` | Installs NVM, Node.js LTS, pnpm, TypeScript, ts-node, Bun |
| 6.3 | `go_env` | Downloads latest Go to temp dir, configures GOPATH/GOROOT |
| 6.4 | `powershell` | Installs PowerShell 7, MicrosoftTeams/AzureAD modules, Oh My Posh profile |

### Phase 7: Containers & Kubernetes (2-5 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 7.1 | `containers` | Prompts for Docker Desktop (recommended) or Docker CE native |
| 7.2 | `k8s_tools` | Installs kubectl (architecture-aware), Helm, adds bitnami repo |

### Phase 8: Development Tools (5-8 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 8.1 | `claude_code` | Installs `@anthropic-ai/claude-code` and `ccusage` via npm |
| 8.2 | `modern_cli_tools` | Installs lazygit, lazydocker, atuin, delta (git-delta), SIPp, k6, vegeta |
| 8.3 | `tmux` | Clones TPM (tmux plugin manager), copies tmux.conf |

### Phase 9: Security & Git (3-5 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 9.1 | `ssh_validate` | Generates SSH keys if missing, prompts to add to GitHub/GitLab, validates connection |
| 9.2 | `ssh_gpg` | Generates ed25519 keys for github/gitlab/work, GPG key, configures git signing |
| 9.3 | `clone_repos` | Clones configured repos (default: .claude, .config, thoughts) |

### Phase 10: Final Setup (1 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 10.1 | `final` | Creates `~/projects/{personal,work,experiments}`, `~/thoughts`, `~/scripts/`, global gitignore |

### Phase 11: Verification

| Step | What Happens |
|------|--------------|
| 11.1 | Runs `verify_installation()` to check all tools, configs, and directories |
| 11.2 | Displays summary of passed/failed/warning checks |
| 11.3 | Shows completion message with next steps |

---

## Total Fresh Install Time: ~40-60 minutes

(Varies by network speed and choices made)

---

## What's NOT Automated (Manual Steps Required)

### Before Running Script

| Task | Instructions |
|------|--------------|
| Install WSL2 | PowerShell (Admin): `wsl --install -d Ubuntu-24.04` |
| Windows Terminal | Microsoft Store → Windows Terminal |
| Docker Desktop | Download from docker.com, enable WSL2 integration |

### During Script (Interactive Prompts)

| Prompt | When | Options |
|--------|------|---------|
| Sudo password | Start | Required for apt/system changes |
| WSL restart | After systemd enable | Script pauses, run `wsl --shutdown`, restart |
| Docker choice | Phase 7 | 1=Docker Desktop, 2=Docker CE, 3=Skip |
| SSH key registration | Phase 9 | Must manually add to GitHub/GitLab web UI |

### After Script Completes

| Task | Command/Action | Why |
|------|----------------|-----|
| **Restart WSL** | `wsl --shutdown` from PowerShell | Apply systemd, shell changes |
| **Set terminal font** | Windows Terminal → Settings → Ubuntu → JetBrainsMono Nerd Font | Icons display correctly |
| **GitHub CLI auth** | `gh auth login` | Enables `gh` commands |
| **GitLab CLI auth** | `glab auth login` | Enables `glab` commands |
| **Install tmux plugins** | Start tmux, press `Ctrl+B` then `I` | Installs TPM plugins |
| **VS Code extension** | Install "Remote - WSL" extension | Open WSL projects in VS Code |
| **Docker Desktop** | Enable WSL integration in Docker Desktop settings | Docker commands work in WSL |

---

## Environment Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `USER_FULLNAME` | Git author name | "Your Name" |
| `USER_EMAIL` | Git/SSH email | "your.email@example.com" |
| `USER_GITHUB` | GitHub username | "yourusername" |
| `USER_GITLAB` | GitLab username | "yourusername" |
| `SUDO_PASSWORD` | Non-interactive sudo | (interactive prompt) |
| `REPO_LIST` | Repos to clone | .claude,.config,thoughts |
| `SKIP_SSH_VALIDATE` | Skip SSH validation | 0 |
| `SKIP_GPG_SETUP` | Skip GPG setup | 0 |
| `DOCKER_CHOICE` | Docker option (1/2/3) | (interactive prompt) |
| `COMPANY_GITLAB` | Corporate GitLab URL | - |
| `COMPANY_JUMPHOST` | SSH jumphost config | - |

---

## Checkpoint System

Checkpoints stored in: `~/.wsl_ubuntu_setup_logs/.checkpoint`

```bash
# View completed steps
cat ~/.wsl_ubuntu_setup_logs/.checkpoint

# Reset specific step (force reinstall)
sed -i '/python_env/d' ~/.wsl_ubuntu_setup_logs/.checkpoint

# Reset all (full reinstall)
rm ~/.wsl_ubuntu_setup_logs/.checkpoint
```

---

## Quick Reference Commands

```bash
# Full install (non-interactive with env vars)
USER_FULLNAME="Name" USER_EMAIL="email" SUDO_PASSWORD="pass" ./wsl_ubuntu_setup.sh --full

# Check prerequisites only
./wsl_ubuntu_setup.sh --check

# Interactive menu
./wsl_ubuntu_setup.sh

# Verify installation health
./wsl_ubuntu_setup.sh --verify

# View logs
cat ~/.wsl_ubuntu_setup_logs/setup_*.log | tail -100

# Manual verification
zsh --version && oh-my-posh --version && node --version && python3 --version && go version
```

---

## Troubleshooting Fresh Install Issues

### Script Fails Early

```bash
# Check prerequisites
./wsl_ubuntu_setup.sh --check

# Common issues:
# - Not running as regular user (not root)
# - No internet connection
# - Insufficient disk space (<25GB)
```

### WSL Restart Required

The script will pause after enabling systemd. In PowerShell:

```powershell
wsl --shutdown
# Wait 5 seconds, then reopen Ubuntu
```

### Tool Not Found After Install

```bash
# Reload shell
source ~/.zshrc

# Or restart terminal
exec zsh
```

### Verification Shows Failures

```bash
# Run verification
./wsl_ubuntu_setup.sh --verify

# For failed items, reset that checkpoint and re-run
sed -i '/failed_checkpoint/d' ~/.wsl_ubuntu_setup_logs/.checkpoint
./wsl_ubuntu_setup.sh --full
```

---

## What Gets Installed Where

| Item | Location |
|------|----------|
| Zsh config | `~/.zshrc` |
| Zsh modules | `~/.zshrc.d/*.zsh` |
| Zsh plugins | `~/.zsh/` |
| Oh My Posh theme | `~/.config/ohmyposh/catppuccin_mocha.omp.json` |
| tmux config | `~/.tmux.conf` |
| tmux plugins | `~/.tmux/plugins/` |
| SSH keys | `~/.ssh/id_ed25519_*` |
| GPG keys | `~/.gnupg/` |
| Installation logs | `~/.wsl_ubuntu_setup_logs/` |
| Checkpoints | `~/.wsl_ubuntu_setup_logs/.checkpoint` |
| Backups | `~/backup_preinstall_YYYYMMDD/` |
| Projects | `~/projects/{personal,work,experiments}` |
| pyenv | `~/.pyenv/` |
| nvm | `~/.nvm/` |
| Rust/Cargo | `~/.cargo/` |
| Go workspace | `~/go/` |
| fzf | `~/.fzf/` |
| Bun | `~/.bun/` |
| Atuin | `~/.atuin/` |
