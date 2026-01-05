# WSL Ubuntu Fresh Install Guide

Complete walkthrough of what happens during a fresh `./wsl_ubuntu_setup.sh --full` installation.

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

### Phase 5: System Optimization (1-2 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 5.1 | `optimizations` | Sets `fs.inotify.max_user_watches=524288`, increases nofile/nproc limits |
| 5.2 | `nftables` | Configures firewall: allows ports 22, 80, 443, 3000, 8000 from RFC1918 only |

### Phase 6: Language Runtimes (10-15 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 6.1 | `python_env` | Installs pyenv, Python 3.12.x, Poetry, uv (fast package manager) |
| 6.2 | `nodejs_env` | Installs NVM, Node.js LTS, pnpm, TypeScript, ts-node, Bun |
| 6.3 | `go_env` | Downloads latest Go, configures GOPATH/GOROOT |
| 6.4 | `powershell` | Installs PowerShell 7, MicrosoftTeams/AzureAD modules, Oh My Posh profile |

### Phase 7: Containers & Kubernetes (2-5 min)

| Step | Checkpoint | What Happens |
|------|------------|--------------|
| 7.1 | `containers` | Prompts for Docker Desktop (recommended) or Docker CE native |
| 7.2 | `k8s_tools` | Installs kubectl, Helm, adds bitnami repo |

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

---

## Total Fresh Install Time: ~40-60 minutes

(Varies by network speed and choices made)

---

## What's NOT Automated (Manual Steps Required)

### Before Running Script

| Task | Instructions |
|------|--------------|
| Install WSL2 | PowerShell: `wsl --install -d Ubuntu-24.04` |
| Windows Terminal | Microsoft Store → Windows Terminal |
| Docker Desktop | Download from docker.com, enable WSL2 integration |

### During Script (Interactive Prompts)

| Prompt | When | Options |
|--------|------|---------|
| Sudo password | Start | Required for apt/system changes |
| WSL restart | After systemd enable | Script exits, run `wsl --shutdown`, restart |
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

## What Was Missing in Your Install (Fixed Today)

| Issue | Root Cause | Fix Applied |
|-------|------------|-------------|
| Skill hooks failing | `node_modules` not installed + hardcoded Node v20 path | `npm install` + dynamic Node detection |
| Statusline failing | Bun not installed + relative path | Installed Bun + full path in settings.json |
| Bun missing | Script doesn't install Bun in `nodejs_env` | Installed manually (should add to script) |
| atuin missing | Installation failed silently | Not fixed yet |

---

## Recommended Script Improvements

### Should Add to Script

```bash
# 1. In install_nodejs_env() - Bun is installed but PATH may not persist
# Add: Verify bun is in PATH after install

# 2. In install_modern_cli_tools() - atuin install may fail
# Add: Verify atuin installed, retry if needed

# 3. In configure_shell() - Oh My Posh theme path
# Add: Verify theme file exists at expected location

# 4. Post-install validation
# Add: Run verification of all installed tools with versions
```

### Should Add to README

```markdown
## Post-Install Checklist

- [ ] Restart WSL: `wsl --shutdown`
- [ ] Set terminal font to JetBrainsMono Nerd Font
- [ ] Run `gh auth login`
- [ ] Run `glab auth login`
- [ ] Start tmux and press Ctrl+B, I to install plugins
- [ ] Install VS Code Remote-WSL extension
- [ ] Enable Docker Desktop WSL integration
```

---

## Environment Variables Reference

| Variable | Purpose | Default |
|----------|---------|---------|
| `USER_FULLNAME` | Git author name | "Your Name" |
| `USER_EMAIL` | Git/SSH email | "your.email@example.com" |
| `USER_GITHUB` | GitHub username | "yourusername" |
| `USER_GITLAB` | GitLab username | "yourusername" |
| `SUDO_PASSWORD` | Non-interactive sudo | (none) |
| `REPO_LIST` | Repos to clone | .claude,.config,thoughts |
| `SKIP_SSH_VALIDATE` | Skip SSH validation | 0 |
| `SKIP_GPG_SETUP` | Skip GPG setup | 0 |
| `DOCKER_CHOICE` | Docker option (1/2/3) | (interactive) |

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
# Full install (non-interactive with password)
SUDO_PASSWORD="pass" USER_FULLNAME="Name" USER_EMAIL="email" ./wsl_ubuntu_setup.sh --full

# Check prerequisites only
./wsl_ubuntu_setup.sh --check

# Interactive menu
./wsl_ubuntu_setup.sh

# View logs
cat ~/.wsl_ubuntu_setup_logs/setup_*.log | tail -100

# Verify installation
zsh --version && oh-my-posh --version && node --version && python3 --version && go version
```
