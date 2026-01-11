# CLAUDE.md

WSL Ubuntu Setup: One-click WSL2 development environment with modern shell, language runtimes, and Windows integration.

## Quick Reference

| Action | Command |
|--------|---------|
| Full Install | `./wsl_ubuntu_setup.sh --full` |
| Interactive | `./wsl_ubuntu_setup.sh` |
| Orchestrated | `./wsl_ubuntu_setup.sh --orchestrated` |
| Check Prerequisites | `./wsl_ubuntu_setup.sh --check` |
| Verify Installation | `./wsl_ubuntu_setup.sh --verify` |
| Run Tests | `./wsl_ubuntu_setup.sh --test` or `bats tests/` |
| Lint Script | `shellcheck wsl_ubuntu_setup.sh` |

## Architecture

| Layer | Technology | Files |
|-------|------------|-------|
| Main Script | Bash | `wsl_ubuntu_setup.sh` (3370+ lines, checkpoint-based) |
| Shell Config | Zsh + Oh My Posh | `dotfiles/zshrc`, `dotfiles/zshrc.d/*.zsh` |
| Prompt Theme | Oh My Posh | `dotfiles/ohmyposh/catppuccin_mocha.omp.json` |
| Terminal | tmux | `dotfiles/tmux.conf` with Windows clipboard |
| PowerShell | Profile | `dotfiles/Microsoft.PowerShell_profile.ps1` |
| Tests | BATS | `tests/*.bats` |
| CI/CD | GitHub Actions | `.github/workflows/test.yml` |

## Environment Variables

| Variable | Purpose | Required | Default |
|----------|---------|----------|---------|
| `USER_FULLNAME` | Git author name | Yes* | "Your Name" |
| `USER_EMAIL` | Git/SSH email | Yes* | "your.email@example.com" |
| `USER_GITHUB` | GitHub username | Yes* | "yourusername" |
| `USER_GITLAB` | GitLab username | No | "yourusername" |
| `SUDO_PASSWORD` | Non-interactive sudo | No | (interactive) |
| `REPO_LIST` | Repos to clone | No | .claude,.config,thoughts |
| `COMPANY_GITLAB` | Corporate GitLab URL | No | - |
| `COMPANY_JUMPHOST` | SSH jumphost | No | - |
| `SKIP_SSH_VALIDATE` | Skip SSH validation | No | 0 |
| `SKIP_GPG_SETUP` | Skip GPG setup | No | 0 |
| `SKIP_KEY_DISPLAY` | Skip SSH/GPG key display | No | 0 |
| `DOCKER_CHOICE` | Docker option (1/2/3) | No | (interactive) |

*Required for Git/SSH configuration; prompts interactively if not set.

## Components Installed

| Component | Tools |
|-----------|-------|
| Shell | Zsh, Oh My Posh, zsh-autosuggestions, zsh-syntax-highlighting |
| CLI Tools | eza, bat, fd, ripgrep, fzf, zoxide, btop, ncdu, tldr |
| Modern CLI | lazygit, lazydocker, atuin, delta (git-delta) |
| Languages | Python (pyenv + Poetry + uv), Node.js (nvm + pnpm + Bun), Go, Rust |
| PowerShell | PowerShell 7, MicrosoftTeams, AzureAD modules |
| Containers | Docker Desktop/CE, kubectl, helm |
| Dev Tools | Claude Code, tmux (TPM), SIPp, k6, vegeta |
| Security | SSH ed25519 keys, GPG signing, nftables firewall |

## Checkpoints

The script uses these checkpoints for idempotency:

```
wsl_environment → systemd_enable → backup → system_update → apt_repos →
packages → fzf → bats_helpers → shell → zsh_files → optimizations → nftables →
python_env → nodejs_env → go_env → powershell → containers →
k8s_tools → claude_code → modern_cli_tools → tmux → ssh_validate →
ssh_gpg → clone_repos → final
```

View: `cat ~/.wsl_ubuntu_setup_logs/.checkpoint`
Reset one: `sed -i '/checkpoint_name/d' ~/.wsl_ubuntu_setup_logs/.checkpoint`
Reset all: `rm ~/.wsl_ubuntu_setup_logs/.checkpoint`

## Key Functions

| Function | Checkpoint | Description |
|----------|------------|-------------|
| `check_wsl_environment()` | `wsl_environment` | Verify WSL2, Ubuntu, disk space, internet |
| `enable_systemd()` | `systemd_enable` | Configure /etc/wsl.conf |
| `install_python_env()` | `python_env` | pyenv, Python 3.12, Poetry, uv |
| `install_nodejs_env()` | `nodejs_env` | nvm, Node.js LTS, pnpm, Bun |
| `install_go_env()` | `go_env` | Latest Go, GOPATH setup |
| `install_bats_helpers()` | `bats_helpers` | BATS testing helpers (bats-support, bats-assert, bats-file) |
| `configure_shell()` | `shell` | Zsh, Oh My Posh, eza, Rust/Cargo |
| `verify_installation()` | - | Post-install health check |

## Development Rules

- **NEVER**: Modify script without running `shellcheck wsl_ubuntu_setup.sh`
- **ALWAYS**: Test changes with `bats tests/` before committing
- **ALWAYS**: Keep script idempotent (use checkpoint system)
- **ALWAYS**: Use `retry_download()` for network operations
- **ALWAYS**: Use temp directories for downloads (mktemp -d)
- **BEFORE COMMIT**: Verify all functions have proper error handling
- **STYLE**: Use `print_success`, `print_error`, `print_warning`, `print_info` for output

## Helper Functions

```bash
command_exists "cmd"           # Check if command exists
is_completed "checkpoint"      # Check if checkpoint completed
mark_completed "checkpoint"    # Mark checkpoint as done
print_success "message"        # Green ✅ output
print_error "message"          # Red ❌ output
print_warning "message"        # Yellow ⚠️ output
print_info "message"           # Blue ℹ️ output
print_header "title"           # Section header
do_sudo "command"              # Run with sudo
secure_download_run "url"      # Download and execute HTTPS script
retry_download "url" "dest"    # Download with retry and backoff
```

## Testing

```bash
# Run all tests (after installation)
./wsl_ubuntu_setup.sh --test

# Or run directly with bats
bats tests/

# Run specific test file
bats tests/test_helpers.bats
bats tests/test_dotfiles.bats
bats tests/test_security.bats
bats tests/test_integration.bats

# Lint
shellcheck wsl_ubuntu_setup.sh

# Syntax check
bash -n wsl_ubuntu_setup.sh
zsh -n dotfiles/zshrc
```

## File Locations After Install

| Item | Location |
|------|----------|
| Zsh config | `~/.zshrc`, `~/.zshrc.d/` |
| Oh My Posh theme | `~/.config/ohmyposh/catppuccin_mocha.omp.json` |
| tmux config | `~/.tmux.conf` |
| SSH keys | `~/.ssh/id_ed25519_*` |
| BATS helpers | `~/.bats/{bats-support,bats-assert,bats-file}` |
| Logs | `~/.wsl_ubuntu_setup_logs/` |
| Checkpoints | `~/.wsl_ubuntu_setup_logs/.checkpoint` |
| Projects | `~/projects/{personal,work,experiments}` |
| Backups | `~/backup_preinstall_YYYYMMDD/` |
