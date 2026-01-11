#!/bin/bash

################################################################################
# WSL Ubuntu Development Environment Setup Script
# Version: 1.1.0
# Last Updated: 2026-01-05
# Compatibility: Ubuntu on WSL2 (Windows 10 19041+, Windows 11)
# Architecture: x86_64 (amd64), ARM64
#
# Changelog:
#   1.1.0 - Shellcheck fixes, SSH passphrase option, BATS tests, README
#   1.0.0 - Initial release with full WSL setup
################################################################################

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

################################################################################
# CONFIGURATION VARIABLES
################################################################################

# User Configuration (CUSTOMIZE THESE)
export USER_FULLNAME="${USER_FULLNAME:-Your Name}"
export USER_EMAIL="${USER_EMAIL:-your.email@example.com}"
export USER_GITHUB="${USER_GITHUB:-yourusername}"
export USER_GITHUB_EMAIL="${USER_GITHUB_EMAIL:-$USER_EMAIL}"
export USER_GITLAB="${USER_GITLAB:-yourusername}"
export USER_GITLAB_EMAIL="${USER_GITLAB_EMAIL:-$USER_EMAIL}"

# Optional Corporate Configuration
export COMPANY_GITLAB="${COMPANY_GITLAB:-}"
export COMPANY_JUMPHOST="${COMPANY_JUMPHOST:-}"

# Sudo Password (for non-interactive mode)
# Can be set via: SUDO_PASSWORD="yourpass" ./wsl_ubuntu_setup.sh --full
export SUDO_PASSWORD="${SUDO_PASSWORD:-}"

# Repository Configuration (for orchestrated mode)
# Format: "name:url:path,name2:url2:path2"
# Default: .claude, .config, thoughts repos
# Can be overridden: REPO_LIST="..." ./wsl_ubuntu_setup.sh --orchestrated
export REPO_LIST="${REPO_LIST:-}"

# Orchestrated Mode Options (PowerShell launcher integration)
# SKIP_SSH_VALIDATE: Set to "1" to skip SSH validation in orchestrated mode
# SKIP_GPG_SETUP: Set to "1" to skip GPG setup in orchestrated mode
export SKIP_SSH_VALIDATE="${SKIP_SSH_VALIDATE:-0}"
export SKIP_GPG_SETUP="${SKIP_GPG_SETUP:-0}"

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.wsl_ubuntu_setup_logs"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
CHECKPOINT_FILE="$LOG_DIR/.checkpoint"
BACKUP_DIR="$HOME/backup_preinstall_$(date +%Y%m%d)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

################################################################################
# HELPER FUNCTIONS
################################################################################

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print colored message
print_msg() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Print section header
print_header() {
    local title="$1"
    print_msg "$CYAN" "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_msg "$CYAN" "  $title"
    print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "INFO" "Starting: $title"
}

# Print success message
print_success() {
    print_msg "$GREEN" "✅ $1"
    log "SUCCESS" "$1"
}

# Print error message
print_error() {
    print_msg "$RED" "❌ $1"
    log "ERROR" "$1"
}

# Print warning message
print_warning() {
    print_msg "$YELLOW" "⚠️  $1"
    log "WARNING" "$1"
}

# Print info message
print_info() {
    print_msg "$BLUE" "ℹ️  $1"
    log "INFO" "$1"
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if section already completed
is_completed() {
    local section=$1
    [ -f "$CHECKPOINT_FILE" ] && grep -q "^$section$" "$CHECKPOINT_FILE"
}

# Mark section as completed
mark_completed() {
    local section=$1
    echo "$section" >> "$CHECKPOINT_FILE"
    log "INFO" "Section completed: $section"
}

# Ask yes/no question
ask_yes_no() {
    local question=$1
    local default=${2:-n}

    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -p "$question $prompt " -n 1 -r
    echo ""

    if [ "$default" = "y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Run command with error handling (direct execution, no eval)
run_cmd() {
    log "CMD" "Executing: $*"

    if "$@" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        print_error "Command failed: $*"
        log "ERROR" "Command failed with exit code $exit_code: $*"
        return $exit_code
    fi
}

# Verify command success (direct execution, no eval)
verify_cmd() {
    local description="$1"
    shift

    if "$@" &> /dev/null; then
        print_success "$description"
        return 0
    else
        print_error "$description (verification failed)"
        return 1
    fi
}

# Secure download and execute - validates HTTPS and optionally checksums
secure_download_run() {
    local url="$1"
    local interpreter="${2:-sh}"
    local args="${3:-}"

    # Validate HTTPS
    if [[ ! "$url" =~ ^https:// ]]; then
        print_error "Security: Only HTTPS URLs allowed: $url"
        return 1
    fi

    local tmp_file=$(mktemp)
    trap "rm -f '$tmp_file'" RETURN

    # Download with strict TLS
    if ! curl --proto '=https' --tlsv1.2 -sSf "$url" -o "$tmp_file" 2>/dev/null; then
        print_error "Download failed: $url"
        return 1
    fi

    # Execute
    if [ -n "$args" ]; then
        $interpreter "$tmp_file" $args
    else
        $interpreter "$tmp_file"
    fi
}

# Retry download with exponential backoff
retry_download() {
    local url="$1"
    local dest="$2"
    local max_retries="${3:-3}"
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$dest" 2>/dev/null; then
            return 0
        fi
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            local wait_time=$((2 ** retry))
            print_warning "Download failed, retry $retry/$max_retries in ${wait_time}s..."
            sleep $wait_time
        fi
    done

    print_error "Download failed after $max_retries attempts: $url"
    return 1
}

# Sudo wrapper - uses cached credentials
do_sudo() {
    sudo "$@"
}

# Write content to file with sudo (avoids pipe issues with password)
sudo_write() {
    local dest="$1"
    local content="$2"
    local tmp=$(mktemp)
    echo "$content" > "$tmp"
    do_sudo cp "$tmp" "$dest"
    rm -f "$tmp"
}

# Append content to file with sudo
sudo_append() {
    local dest="$1"
    local content="$2"
    local tmp=$(mktemp)
    do_sudo cat "$dest" > "$tmp" 2>/dev/null || true
    echo "$content" >> "$tmp"
    do_sudo cp "$tmp" "$dest"
    rm -f "$tmp"
}

# Initialize sudo credentials using caching (no password stored in env)
ask_sudo_password() {
    # Check if already have passwordless sudo
    if sudo -n true 2>/dev/null; then
        print_success "Passwordless sudo available"
        return 0
    fi

    # Orchestrated mode with password from PowerShell
    if [ -n "${SUDO_PASSWORD:-}" ]; then
        print_info "Validating provided sudo password..."
        if echo "$SUDO_PASSWORD" | sudo -S -v 2>/dev/null; then
            print_success "Sudo credentials cached"
            # SECURITY: Clear password from environment immediately
            unset SUDO_PASSWORD
        else
            print_error "Invalid sudo password"
            unset SUDO_PASSWORD
            exit 1
        fi
    elif [ -t 0 ]; then
        # Interactive mode: use sudo's built-in prompting
        print_info "Sudo authentication required for installation"
        if ! sudo -v; then
            print_error "Sudo authentication failed"
            exit 1
        fi
        print_success "Sudo credentials cached"
    else
        print_error "Non-interactive mode requires sudo access"
        print_info "Run with: sudo $0 --full"
        print_info "Or configure NOPASSWD in sudoers for this user"
        exit 1
    fi

    # Keep sudo credentials alive in background
    (while true; do
        sudo -n true 2>/dev/null
        sleep 50
        # Exit if parent process is gone
        kill -0 $$ 2>/dev/null || exit 0
    done) &
    SUDO_KEEPER_PID=$!

    # Cleanup on script exit, interrupt, or termination
    trap "kill $SUDO_KEEPER_PID 2>/dev/null" EXIT INT TERM
}

################################################################################
# WSL-SPECIFIC CHECKS
################################################################################

check_wsl_environment() {
    print_header "WSL Environment Verification"

    local has_error=0

    # Check if running in WSL
    if ! grep -qi microsoft /proc/version; then
        print_error "This script must be run in WSL (Windows Subsystem for Linux)"
        print_info "Detected: $(uname -a)"
        has_error=1
    else
        print_success "WSL environment detected"
    fi

    # Check Ubuntu version
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "$VERSION_ID" == "22.04" || "$VERSION_ID" == "24.04" ]]; then
            print_success "Ubuntu $VERSION_ID LTS detected"
            export UBUNTU_VERSION="$VERSION_ID"
        else
            print_warning "Ubuntu $VERSION_ID detected (recommended: 22.04 or 24.04)"
            export UBUNTU_VERSION="$VERSION_ID"
        fi
    else
        print_error "Unable to detect Ubuntu version"
        has_error=1
    fi

    # Check WSL version (non-critical, don't exit on failure)
    if command_exists wsl.exe; then
        WSL_VERSION=$(wsl.exe -l -v 2>/dev/null | grep -i "ubuntu" | awk '{print $NF}' | tr -d '\r\0' | grep -o '[0-9]' | head -1) || true
        if [[ "$WSL_VERSION" == "2" ]]; then
            print_success "WSL2 detected (recommended)"
        elif [[ "$WSL_VERSION" == "1" ]]; then
            print_warning "WSL1 detected (WSL2 recommended for better performance)"
        else
            print_info "WSL version not detected (probably WSL2)"
        fi
    else
        print_warning "wsl.exe not accessible (normal in some configurations)"
    fi

    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]]; then
        print_success "Supported architecture: $arch"
    else
        print_warning "Untested architecture: $arch"
    fi

    # Check disk space (25GB minimum)
    # WSL2's ext4.vhdx grows dynamically, so df / shows misleading values
    # Check Windows host C: drive via /mnt/c for actual available space
    local win_available=$(df -BG /mnt/c 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    local win_total=$(df -BG /mnt/c 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$2); print $2}')
    local win_used=$(df -BG /mnt/c 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$3); print $3}')

    # Also get WSL disk usage for reference
    local wsl_used=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$3); print $3}')

    # Validate the value is numeric
    if [[ "$win_available" =~ ^[0-9]+$ ]]; then
        if [ "$win_available" -ge 25 ]; then
            print_success "Disk space sufficient: ${win_available}GB available on Windows (${win_used}GB used of ${win_total}GB total, WSL using ${wsl_used}GB)"
        else
            print_error "Insufficient disk space: ${win_available}GB available on Windows (25GB minimum required)"
            has_error=1
        fi
    else
        print_error "Could not determine Windows disk space via /mnt/c"
        has_error=1
    fi

    # Check internet connectivity
    if ping -c 1 google.com &> /dev/null; then
        print_success "Internet connection active"
    else
        print_error "No internet connection"
        has_error=1
    fi

    # Check sudo privileges
    if sudo -n true 2>/dev/null; then
        print_success "Sudo privileges available (passwordless)"
    elif [ -t 0 ]; then
        # Interactive mode: prompt for password
        print_warning "Sudo privileges required (password will be asked)"
        sudo -v || { print_error "Sudo authentication failed"; has_error=1; }
    else
        # Non-interactive mode: trust sudo will work when needed
        print_warning "Sudo privileges required (will be asked during installation)"
    fi

    # Check systemd
    if systemctl --version &>/dev/null; then
        print_success "systemd enabled"
        export HAS_SYSTEMD=true
    else
        print_warning "systemd not enabled (will be configured)"
        export HAS_SYSTEMD=false
    fi

    if [ "$has_error" -eq 1 ]; then
        print_error "Prerequisites not met. Please fix the errors above."
        exit 1
    fi

    mark_completed "wsl_environment"
}

################################################################################
# SYSTEMD ENABLEMENT
################################################################################

enable_systemd() {
    if is_completed "systemd_enable"; then
        print_info "systemd already configured, skipping"
        return 0
    fi

    if [ "$HAS_SYSTEMD" = "true" ]; then
        print_info "systemd already enabled, skipping"
        mark_completed "systemd_enable"
        return 0
    fi

    print_header "Enabling systemd in WSL"

    # Check if wsl.conf exists and already has systemd enabled (e.g., from PowerShell setup)
    if [ -f /etc/wsl.conf ] && grep -qE "systemd\s*=\s*true" /etc/wsl.conf 2>/dev/null; then
        print_success "systemd already enabled in existing wsl.conf"
        print_info "Checking for missing sections..."

        # Only append missing sections, don't overwrite existing config
        local additions=""

        # Check for [boot] section
        if ! grep -q "\[boot\]" /etc/wsl.conf 2>/dev/null; then
            additions+="
[boot]
systemd=true
"
        fi

        # Check for [automount] section
        if ! grep -q "\[automount\]" /etc/wsl.conf 2>/dev/null; then
            additions+="
[automount]
enabled = true
options = \"metadata,umask=22,fmask=11\"
mountFsTab = true
"
        fi

        # Check for [network] section
        if ! grep -q "\[network\]" /etc/wsl.conf 2>/dev/null; then
            additions+="
[network]
generateHosts = true
generateResolvConf = true
"
        fi

        if [ -n "$additions" ]; then
            print_info "Appending missing sections to wsl.conf..."
            sudo_append /etc/wsl.conf "$additions"
            print_success "Added missing wsl.conf sections"
        else
            print_success "wsl.conf already has all required sections"
        fi

        mark_completed "systemd_enable"
        return 0
    fi

    # No existing wsl.conf or systemd not configured - create full config
    print_info "Creating /etc/wsl.conf with full configuration..."
    cat > /tmp/wsl.conf << 'EOF'
[boot]
systemd=true

[automount]
enabled = true
options = "metadata,umask=22,fmask=11"
mountFsTab = true

[network]
generateHosts = true
generateResolvConf = true

[interop]
enabled = true
appendWindowsPath = true
EOF
    do_sudo cp /tmp/wsl.conf /etc/wsl.conf
    rm -f /tmp/wsl.conf

    print_success "systemd configured in /etc/wsl.conf"
    print_warning "WSL RESTART REQUIRED to enable systemd"
    print_info "From PowerShell/CMD: wsl --shutdown"
    print_info "Then run this script again"

    mark_completed "systemd_enable"

    # Skip interactive prompt in non-interactive mode
    if [ ! -t 0 ]; then
        print_warning "Non-interactive mode: restart WSL manually with 'wsl --shutdown'"
        return 0
    fi

    if ask_yes_no "Restart WSL now? (terminal will close)"; then
        print_info "Shutting down WSL..."
        /mnt/c/Windows/System32/wsl.exe --shutdown
        exit 0
    fi
}

################################################################################
# BACKUP FUNCTION
################################################################################

create_backup() {
    if is_completed "backup"; then
        print_info "Backup already created, skipping"
        return 0
    fi

    print_header "Creating preventive backup"

    mkdir -p "$BACKUP_DIR"

    # Backup existing configurations
    [ -f ~/.bashrc ] && cp ~/.bashrc "$BACKUP_DIR/"
    [ -f ~/.zshrc ] && cp ~/.zshrc "$BACKUP_DIR/"
    [ -f ~/.gitconfig ] && cp ~/.gitconfig "$BACKUP_DIR/"
    [ -d ~/.ssh ] && cp -r ~/.ssh "$BACKUP_DIR/"

    print_success "Backup created in: $BACKUP_DIR"
    mark_completed "backup"
}

################################################################################
# SYSTEM UPDATE
################################################################################

update_system() {
    if is_completed "system_update"; then
        print_info "System already up to date, skipping"
        return 0
    fi

    print_header "System update"

    do_sudo apt update
    do_sudo apt upgrade -y
    do_sudo apt dist-upgrade -y
    do_sudo apt autoremove -y
    do_sudo apt autoclean

    verify_cmd "System updated" "true"

    print_success "System updated"
    mark_completed "system_update"
}

################################################################################
# APT REPOSITORIES
################################################################################

configure_apt_repos() {
    if is_completed "apt_repos"; then
        print_info "APT repositories already configured, skipping"
        return 0
    fi

    print_header "Configuring third-party APT repositories"

    # GitHub CLI - download first, then copy with sudo
    local tmp_key=$(mktemp)
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$tmp_key"
    do_sudo cp "$tmp_key" /usr/share/keyrings/githubcli-archive-keyring.gpg
    do_sudo chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg
    rm -f "$tmp_key"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /tmp/github-cli.list
    do_sudo cp /tmp/github-cli.list /etc/apt/sources.list.d/github-cli.list
    rm -f /tmp/github-cli.list
    print_success "GitHub CLI repository configured"

    mark_completed "apt_repos"
}

################################################################################
# INSTALL PACKAGES
################################################################################

install_packages() {
    if is_completed "packages"; then
        print_info "Packages already installed, skipping"
        return 0
    fi

    print_header "Installing packages"

    # Define all packages to install
    # Note: fzf installed separately from GitHub for latest version (apt is outdated)
    local packages=(
        git zsh bat fd-find ripgrep btop ncdu tldr zoxide unzip
        nmap tcpdump netcat-openbsd openssh-server
        python3-pip tmux gh glab
        make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev
        libsqlite3-dev wget curl llvm libncursesw5-dev xz-utils tk-dev
        libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
    )

    # Check which packages are missing (idempotent)
    local missing=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        print_success "All ${#packages[@]} packages already installed"
    else
        print_info "Installing ${#missing[@]} of ${#packages[@]} packages..."
        do_sudo apt update
        do_sudo apt install -y "${missing[@]}"
        print_success "Packages installed"
    fi

    verify_cmd "Packages installed" command -v git
    mark_completed "packages"
}

################################################################################
# FZF INSTALLATION (From GitHub for latest version)
################################################################################

install_fzf() {
    if is_completed "fzf"; then
        print_info "fzf already installed, skipping"
        return 0
    fi

    # Check if fzf already exists and is recent enough (0.48+ for --zsh support)
    if command_exists fzf; then
        local current_version=$(fzf --version 2>/dev/null | cut -d' ' -f1)
        local major=$(echo "$current_version" | cut -d'.' -f1)
        local minor=$(echo "$current_version" | cut -d'.' -f2)
        if [ "$major" -gt 0 ] || [ "$minor" -ge 48 ]; then
            print_success "fzf $current_version already installed (>= 0.48)"
            mark_completed "fzf"
            return 0
        fi
        print_info "fzf $current_version found but outdated, upgrading..."
    fi

    print_header "Installing fzf (from GitHub)"

    # Remove apt version if exists
    if dpkg -l fzf 2>/dev/null | grep -q "^ii"; then
        print_info "Removing outdated apt fzf..."
        do_sudo apt remove -y fzf 2>/dev/null || true
    fi

    # Install from GitHub (official method)
    if [ -d ~/.fzf ]; then
        print_info "Updating existing fzf installation..."
        cd ~/.fzf && git pull
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    fi

    # Run install script (--all enables key bindings and completion, --no-* skips other shells)
    ~/.fzf/install --all --no-bash --no-fish --no-update-rc

    print_success "fzf installed: $(~/.fzf/bin/fzf --version)"
    mark_completed "fzf"
}

################################################################################
# NERD FONT INSTALLATION
################################################################################

install_nerd_font() {
    local font_dir="$HOME/.local/share/fonts"
    local font_name="JetBrainsMono"

    if [ -d "$font_dir/$font_name" ] || ls "$font_dir"/*JetBrains* &>/dev/null; then
        print_info "Nerd Font already installed"
        return 0
    fi

    print_info "Installing JetBrainsMono Nerd Font..."

    mkdir -p "$font_dir"
    local tmp_dir=$(mktemp -d)
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"

    if curl -sL "$font_url" -o "$tmp_dir/font.zip"; then
        unzip -q "$tmp_dir/font.zip" -d "$tmp_dir/fonts"
        # Install only the regular variants (not all weights)
        cp "$tmp_dir/fonts"/*.ttf "$font_dir/" 2>/dev/null || true

        # Update font cache
        if command_exists fc-cache; then
            fc-cache -f "$font_dir"
        fi

        rm -rf "$tmp_dir"
        print_success "JetBrainsMono Nerd Font installed"
        print_info "Configure your terminal to use 'JetBrainsMono Nerd Font'"
    else
        print_warning "Could not download Nerd Font - icons may not display correctly"
        rm -rf "$tmp_dir"
    fi
}

################################################################################
# OH MY POSH THEME
################################################################################

install_ohmyposh_theme() {
    # Install Oh My Posh theme - try local first, then download from GitHub
    local theme_dst="$HOME/.config/ohmyposh/catppuccin_mocha.omp.json"
    local theme_url="https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main/dotfiles/ohmyposh/catppuccin_mocha.omp.json"

    mkdir -p "$HOME/.config/ohmyposh"

    # Skip if theme already exists
    if [ -f "$theme_dst" ]; then
        print_success "Oh My Posh theme already installed"
        return 0
    fi

    # Try local file first (using global SCRIPT_DIR)
    local theme_src="$SCRIPT_DIR/dotfiles/ohmyposh/catppuccin_mocha.omp.json"
    if [ -f "$theme_src" ]; then
        cp "$theme_src" "$theme_dst"
        print_success "Oh My Posh theme installed from local repo"
        return 0
    fi

    # Download from GitHub as fallback
    print_info "Downloading Oh My Posh theme from GitHub..."
    if curl -fsSL "$theme_url" -o "$theme_dst"; then
        print_success "Oh My Posh theme downloaded from GitHub"
        return 0
    else
        print_error "Failed to download Oh My Posh theme"
        return 1
    fi
}

################################################################################
# DOTFILES INSTALLATION
################################################################################

install_dotfiles() {
    # Install dotfiles from repo or download from GitHub
    local dotfiles_dir="$SCRIPT_DIR/dotfiles"
    local github_base="https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main/dotfiles"

    # Create directories
    mkdir -p ~/.zshrc.d

    # Helper to install a dotfile (local or download)
    install_dotfile() {
        local src_name="$1"
        local dst_path="$2"
        local local_src="$dotfiles_dir/$src_name"
        local github_url="$github_base/$src_name"

        # Skip if destination already exists
        if [ -f "$dst_path" ]; then
            print_info "$dst_path already exists, skipping"
            return 0
        fi

        if [ -f "$local_src" ]; then
            cp "$local_src" "$dst_path"
            print_success "$dst_path installed from local repo"
        elif curl -fsSL "$github_url" -o "$dst_path" 2>/dev/null; then
            print_success "$dst_path downloaded from GitHub"
        else
            print_warning "Could not install $dst_path"
            return 1
        fi
    }

    # Install main dotfiles
    install_dotfile "zshrc" "$HOME/.zshrc"
    install_dotfile "tmux.conf" "$HOME/.tmux.conf"
    [ -f "$HOME/.tmux.conf" ] && chmod 644 "$HOME/.tmux.conf"

    # Install zshrc.d files
    local zshrc_d_files=("aliases.zsh" "functions.zsh" "path.zsh" "prompt.zsh")
    for zsh_file in "${zshrc_d_files[@]}"; do
        install_dotfile "zshrc.d/$zsh_file" "$HOME/.zshrc.d/$zsh_file"
    done
}

################################################################################
# SHELL CONFIGURATION
################################################################################

configure_shell() {
    if is_completed "shell"; then
        print_info "Shell already configured, skipping"
        return 0
    fi

    print_header "Modern shell configuration (Zsh + Oh My Posh)"

    # Install Zsh - use usermod with sudo instead of chsh (works non-interactively)
    do_sudo usermod -s "$(which zsh)" "$USER"
    print_success "Zsh set as default shell"

    # Create plugins directory (standalone, no Oh My Zsh)
    mkdir -p ~/.zsh

    # Install zsh-autosuggestions (standalone)
    if [ ! -d ~/.zsh/zsh-autosuggestions ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
        print_success "zsh-autosuggestions installed"
    fi

    # Install zsh-syntax-highlighting (standalone)
    if [ ! -d ~/.zsh/zsh-syntax-highlighting ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
        print_success "zsh-syntax-highlighting installed"
    fi

    # Install Oh My Posh (cross-platform prompt theme engine)
    if ! command_exists oh-my-posh; then
        print_info "Installing Oh My Posh..."
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
        # Add .local/bin to PATH for current session
        export PATH="$HOME/.local/bin:$PATH"
        print_success "Oh My Posh installed"
    fi

    # Ensure .local/bin is in PATH for current session
    [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

    # Install Nerd Font (required for Oh My Posh icons)
    install_nerd_font

    # Create Oh My Posh config directory and custom 2-line Catppuccin theme
    mkdir -p ~/.config/ohmyposh
    install_ohmyposh_theme

    # Install Rust (secure download)
    if ! command_exists cargo; then
        secure_download_run "https://sh.rustup.rs" "sh" "-s -- -y"
        source $HOME/.cargo/env
        print_success "Rust installed"
    fi

    # Install eza
    if ! command_exists eza; then
        source $HOME/.cargo/env
        cargo install eza
        print_success "eza installed"
    fi

    # Configure fd symlink
    mkdir -p ~/.local/bin
    ln -sf $(which fdfind) ~/.local/bin/fd 2>/dev/null || true

    # Update tldr
    tldr --update || true

    print_success "Shell and CLI tools configured"
    mark_completed "shell"
}

################################################################################
# ZSH CONFIGURATION FILES
################################################################################

configure_zsh_files() {
    if is_completed "zsh_files"; then
        print_info "Zsh files already configured, skipping"
        return 0
    fi

    print_header "Configuring Zsh files"

    # Install dotfiles from repo (zshrc, zshrc.d/*)
    install_dotfiles

    print_success "Zsh configuration files installed from repo"
    mark_completed "zsh_files"
}

################################################################################
# SYSTEM OPTIMIZATIONS
################################################################################

optimize_system() {
    if is_completed "optimizations"; then
        print_info "System already optimized, skipping"
        return 0
    fi

    print_header "System optimizations"

    # Inotify watches (CRITICAL for VS Code, Node.js)
    echo 'fs.inotify.max_user_watches=524288' > /tmp/inotify.conf
    do_sudo cp /tmp/inotify.conf /etc/sysctl.d/40-max-user-watches.conf
    rm -f /tmp/inotify.conf
    do_sudo sysctl --system > /dev/null

    # System limits - append if not already present
    if ! grep -q "Development limits" /etc/security/limits.conf 2>/dev/null; then
        cat > /tmp/limits-append.conf << EOF

# Development limits
$USER soft nofile 65536
$USER hard nofile 65536
$USER soft nproc 32768
$USER hard nproc 32768
EOF
        do_sudo sh -c "cat /tmp/limits-append.conf >> /etc/security/limits.conf"
        rm -f /tmp/limits-append.conf
    fi

    print_success "System optimizations applied"
    mark_completed "optimizations"
}

################################################################################
# NFTABLES FIREWALL CONFIGURATION
################################################################################

configure_nftables() {
    if is_completed "nftables"; then
        print_info "nftables already configured, skipping"
        return 0
    fi

    print_header "Configuring nftables firewall for development"

    # Install nftables if not present
    if ! command_exists nft; then
        do_sudo apt-get install -y nftables
    fi

    # Create nftables configuration for development ports
    # Allow SSH (22), HTTP (80), HTTPS (443), Dev servers (3000, 8000) from RFC1918
    cat > /tmp/nftables-wsl.conf << 'EOF'
#!/usr/sbin/nft -f

# Flush existing rules
flush ruleset

table inet filter {
    # RFC1918 private address ranges
    set rfc1918 {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
    }

    chain input {
        type filter hook input priority 0; policy accept;

        # Accept established/related connections
        ct state established,related accept

        # Accept loopback
        iif lo accept

        # Accept ICMP (ping)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Development ports from RFC1918 only
        ip saddr @rfc1918 tcp dport 222 accept comment "SSH (WSL)"
        ip saddr @rfc1918 tcp dport 80 accept comment "HTTP"
        ip saddr @rfc1918 tcp dport 443 accept comment "HTTPS"
        ip saddr @rfc1918 tcp dport 3000 accept comment "Node.js/React dev"
        ip saddr @rfc1918 tcp dport 8000 accept comment "Python/FastAPI dev"

        # Log and drop other incoming (optional - commented for WSL)
        # counter log prefix "nft-drop: " drop
    }

    chain forward {
        type filter hook forward priority 0; policy accept;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    do_sudo cp /tmp/nftables-wsl.conf /etc/nftables.conf
    rm -f /tmp/nftables-wsl.conf

    # Enable and start nftables service
    do_sudo systemctl enable nftables 2>/dev/null || true
    do_sudo systemctl start nftables 2>/dev/null || true

    # Load the rules
    do_sudo nft -f /etc/nftables.conf 2>/dev/null || {
        print_warning "nftables rules created but not loaded (may need WSL restart)"
    }

    print_success "nftables configured for development ports (22, 80, 443, 3000, 8000)"
    print_info "Access restricted to RFC1918 private networks"
    mark_completed "nftables"
}

################################################################################
# SSH SERVER CONFIGURATION
################################################################################

configure_sshd() {
    if is_completed "sshd"; then
        print_info "SSH server already configured, skipping"
        return 0
    fi

    print_header "Configuring SSH Server"

    # Check if openssh-server is installed
    if ! dpkg -l openssh-server 2>/dev/null | grep -q "^ii"; then
        print_info "Installing openssh-server..."
        do_sudo apt update
        do_sudo apt install -y openssh-server
    fi

    # Configure sshd for security
    local sshd_config="/etc/ssh/sshd_config.d/99-wsl-secure.conf"

    do_sudo tee "$sshd_config" > /dev/null << 'EOF'
# WSL2 SSH Server Configuration
# Security hardened settings

# Use port 222 to avoid conflict with Windows SSH (port 22)
Port 222

# Disable root login
PermitRootLogin no

# Use key-based authentication (recommended)
PubkeyAuthentication yes

# Allow password authentication (for initial setup)
PasswordAuthentication yes

# Disable empty passwords
PermitEmptyPasswords no

# Use strong ciphers only
Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr

# Use strong MACs
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Use strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# Limit authentication attempts
MaxAuthTries 3

# Client alive settings (prevent zombie connections)
ClientAliveInterval 300
ClientAliveCountMax 2

# Logging
LogLevel VERBOSE
EOF

    # Generate host keys if they don't exist
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        print_info "Generating SSH host keys..."
        do_sudo ssh-keygen -A
    fi

    # Enable and start SSH service (requires systemd)
    if command -v systemctl &> /dev/null; then
        do_sudo systemctl enable ssh 2>/dev/null || true
        do_sudo systemctl start ssh 2>/dev/null || {
            print_warning "SSH service not started (may need WSL restart with systemd)"
        }

        # Check if service is running
        if systemctl is-active --quiet ssh 2>/dev/null; then
            print_success "SSH server running on port 222"

            # Get WSL IP address
            local wsl_ip=$(hostname -I | awk '{print $1}')
            print_info "Connect from Windows: ssh -p 222 ${USER}@${wsl_ip}"
        else
            print_warning "SSH service configured but not running (restart WSL)"
        fi
    else
        print_warning "systemd not available, SSH server will start after WSL restart"
    fi

    mark_completed "sshd"
}

################################################################################
# TAILSCALE VPN
################################################################################

install_tailscale() {
    if is_completed "tailscale"; then
        print_info "Tailscale already installed, skipping"
        return 0
    fi

    print_header "Installing Tailscale"

    # Add Tailscale repository
    if [ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]; then
        print_info "Adding Tailscale repository..."
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | \
            do_sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | \
            do_sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    fi

    # Install Tailscale
    do_sudo apt update
    do_sudo apt install -y tailscale

    # Start Tailscale daemon (requires systemd)
    if command -v systemctl &> /dev/null; then
        do_sudo systemctl enable tailscaled 2>/dev/null || true
        do_sudo systemctl start tailscaled 2>/dev/null || {
            print_warning "Tailscale daemon not started (may need WSL restart with systemd)"
        }

        if systemctl is-active --quiet tailscaled 2>/dev/null; then
            print_success "Tailscale daemon running"
            print_info "Run 'sudo tailscale up' to authenticate"
        else
            print_warning "Tailscale installed but daemon not running (restart WSL)"
        fi
    else
        print_warning "systemd not available, Tailscale will start after WSL restart"
    fi

    print_info "After WSL restart, run: sudo tailscale up"

    mark_completed "tailscale"
}

################################################################################
# DEVELOPMENT ENVIRONMENTS
################################################################################

install_python_env() {
    if is_completed "python_env"; then
        print_info "Python environment already installed, skipping"
        return 0
    fi

    print_header "Installing Python environment"

    # Install pyenv (secure download)
    if [ ! -d ~/.pyenv ]; then
        secure_download_run "https://pyenv.run" "bash"

        if ! grep -q "PYENV_ROOT" ~/.zshrc; then
            cat >> ~/.zshrc << 'EOF'

# Pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"
EOF
        fi

        export PYENV_ROOT="$HOME/.pyenv"
        [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"

        print_success "pyenv installed"
    fi

    # Install Python 3.12
    LATEST_312=$(pyenv install --list | grep "^\s*3\.12" | grep -v "[a-zA-Z]" | tail -1 | xargs)
    if [ -n "$LATEST_312" ]; then
        pyenv install $LATEST_312
        pyenv global $LATEST_312
        print_success "Python $LATEST_312 installed"
    fi

    # Install Poetry
    if ! command_exists poetry; then
        curl -sSL https://install.python-poetry.org | python3 -

        if ! grep -q "poetry" ~/.zshrc; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        fi

        export PATH="$HOME/.local/bin:$PATH"
        poetry config virtualenvs.in-project true

        print_success "Poetry installed"
    fi

    # Install uv (extremely fast Python package manager - 10-100x faster than pip)
    if ! command_exists uv; then
        print_info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh

        # Add uv to path for current session (uv installs to ~/.local/bin)
        export PATH="$HOME/.local/bin:$PATH"

        # Ensure uv is in .zshrc
        if ! grep -q "# uv" ~/.zshrc 2>/dev/null; then
            cat >> ~/.zshrc << 'EOF'

# uv (fast Python package manager)
export PATH="$HOME/.local/bin:$PATH"
EOF
        fi
        print_success "uv installed (10-100x faster than pip)"
    else
        print_success "uv already installed"
    fi

    mark_completed "python_env"
}

install_nodejs_env() {
    if is_completed "nodejs_env"; then
        print_info "Node.js environment already installed, skipping"
        return 0
    fi

    print_header "Installing Node.js environment"

    # Install NVM (secure download)
    if [ ! -d ~/.nvm ]; then
        NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        secure_download_run "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" "bash"

        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        print_success "NVM installed"
    fi

    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install Node.js LTS
    nvm install --lts
    nvm alias default lts/*
    print_success "Node.js installed"

    # Install pnpm
    npm install -g pnpm
    print_success "pnpm installed"

    # Install TypeScript
    npm install -g typescript ts-node
    print_success "TypeScript installed"

    # Install Bun (fast JavaScript runtime and package manager)
    # Note: bun installs to ~/.bun/bin, check both PATH and direct location
    if ! command_exists bun && [ ! -f "$HOME/.bun/bin/bun" ]; then
        print_info "Installing Bun..."
        curl -fsSL https://bun.sh/install | bash

        # Add Bun to path for current session
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"

        # Ensure Bun is in .zshrc (installer may add to .bashrc only)
        if ! grep -q "BUN_INSTALL" ~/.zshrc 2>/dev/null; then
            cat >> ~/.zshrc << 'EOF'

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
EOF
        fi
        print_success "Bun installed"
    else
        # Ensure PATH is set even if already installed
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        print_success "Bun already installed"
    fi

    mark_completed "nodejs_env"
}

install_go_env() {
    if is_completed "go_env"; then
        print_info "Go environment already installed, skipping"
        return 0
    fi

    print_header "Installing Go environment"

    # Detect latest Go version
    GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
    ARCH=$(dpkg --print-architecture)

    # Download and install (using temp directory for safety)
    local tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    wget -O "$tmp_dir/go.tar.gz" "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz"
    do_sudo rm -rf /usr/local/go
    do_sudo tar -C /usr/local -xzf "$tmp_dir/go.tar.gz"

    # Configure environment
    if ! grep -q "GOROOT" ~/.zshrc; then
        cat >> ~/.zshrc << 'EOF'

# Go configuration
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
export GO111MODULE=on
EOF
    fi

    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

    mkdir -p $GOPATH/{bin,src,pkg}

    print_success "Go installed: $GO_VERSION"
    mark_completed "go_env"
}

################################################################################
# POWERSHELL 7
################################################################################

install_powershell() {
    if is_completed "powershell"; then
        print_info "PowerShell already configured, skipping"
        return 0
    fi

    print_header "Installing PowerShell 7"

    # Check if already installed - if not, install it
    if ! command_exists pwsh; then
        # Get Ubuntu version
        source /etc/os-release
        local ubuntu_version=$VERSION_ID

        # Download and install Microsoft repository
        print_info "Adding Microsoft repository..."
        wget -q "https://packages.microsoft.com/config/ubuntu/${ubuntu_version}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
        do_sudo dpkg -i /tmp/packages-microsoft-prod.deb
        rm /tmp/packages-microsoft-prod.deb

        # Update and install PowerShell
        do_sudo apt-get update
        do_sudo apt-get install -y powershell

        # Verify installation
        if ! command_exists pwsh; then
            print_error "PowerShell installation failed"
            return 1
        fi
        print_success "PowerShell installed: $(pwsh --version)"

        # Install Microsoft Teams and AzureAD modules
        print_info "Installing PowerShell modules (MicrosoftTeams, AzureAD)..."
        pwsh -NoProfile -Command '
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            Install-Module -Name MicrosoftTeams -Scope CurrentUser -Force -AllowClobber 2>$null
            Install-Module -Name AzureAD -Scope CurrentUser -Force -AllowClobber 2>$null
        ' 2>/dev/null || print_warning "Some PowerShell modules may not have installed"
        print_success "PowerShell modules installed"
    else
        print_success "PowerShell already installed: $(pwsh --version)"
    fi

    # Configure Oh My Posh for PowerShell (always run - even if PowerShell was already installed)
    print_info "Configuring Oh My Posh for PowerShell..."

    # Create PowerShell profile directory if it doesn't exist
    local pwsh_profile_dir="$HOME/.config/powershell"
    mkdir -p "$pwsh_profile_dir"

    # Copy PowerShell profile from dotfiles
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dotfiles_dir="$script_dir/dotfiles"
    local ps_profile_src="$dotfiles_dir/Microsoft.PowerShell_profile.ps1"
    local pwsh_profile="$pwsh_profile_dir/Microsoft.PowerShell_profile.ps1"

    if [ -f "$ps_profile_src" ]; then
        cp "$ps_profile_src" "$pwsh_profile"
        print_success "PowerShell profile installed from repo"
    else
        print_error "PowerShell profile not found: $ps_profile_src"
        return 1
    fi

    print_info "Oh My Posh will use same Catppuccin Mocha theme as Zsh"

    # Configure Windows PowerShell with Oh My Posh
    configure_windows_powershell

    mark_completed "powershell"
}

configure_windows_powershell() {
    print_info "Configuring Windows PowerShell with Oh My Posh..."

    # Detect Windows username from environment or path
    local win_user=""
    if [ -n "$LOGNAME" ] && [ -d "/mnt/c/Users/$LOGNAME" ]; then
        win_user="$LOGNAME"
    elif [ -n "$USER" ] && [ -d "/mnt/c/Users/$USER" ]; then
        win_user="$USER"
    else
        # Try to detect from wslpath or common paths
        for user_dir in /mnt/c/Users/*/; do
            local dirname=$(basename "$user_dir")
            # Skip system directories
            if [[ "$dirname" != "Public" && "$dirname" != "Default" && "$dirname" != "Default User" && "$dirname" != "All Users" ]]; then
                win_user="$dirname"
                break
            fi
        done
    fi

    if [ -z "$win_user" ]; then
        print_warning "Could not detect Windows username, skipping Windows PowerShell configuration"
        return 0
    fi

    local win_home="/mnt/c/Users/$win_user"
    print_info "Windows user detected: $win_user"

    # Create Oh My Posh theme directory on Windows
    local win_omp_dir="$win_home/.config/ohmyposh"
    mkdir -p "$win_omp_dir"

    # Copy theme to Windows
    local win_theme="$win_omp_dir/catppuccin_mocha.omp.json"
    cp ~/.config/ohmyposh/catppuccin_mocha.omp.json "$win_theme"
    print_success "Theme copied to Windows: $win_theme"

    # Install Oh My Posh on Windows using winget (if available)
    print_info "Checking Oh My Posh installation on Windows..."
    if command -v winget.exe &>/dev/null; then
        # Check if already installed
        if ! winget.exe list --id JanDeDobbeleer.OhMyPosh &>/dev/null 2>&1; then
            print_info "Installing Oh My Posh on Windows via winget..."
            winget.exe install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements 2>/dev/null || \
                print_warning "winget installation failed, Oh My Posh may need manual installation on Windows"
        else
            print_success "Oh My Posh already installed on Windows"
        fi
    else
        print_warning "winget not available, please install Oh My Posh manually on Windows:"
        print_info "  winget install JanDeDobbeleer.OhMyPosh"
    fi

    # Detect Windows Documents folder (may be redirected to OneDrive)
    local win_docs_dir="$win_home/Documents"
    if [ -d "$win_home/OneDrive/Documents" ]; then
        win_docs_dir="$win_home/OneDrive/Documents"
        print_info "OneDrive Documents folder detected"
    fi

    # Create Windows PowerShell profile directories
    local win_ps7_dir="$win_docs_dir/PowerShell"
    local win_ps5_dir="$win_docs_dir/WindowsPowerShell"
    mkdir -p "$win_ps7_dir" "$win_ps5_dir"

    # Copy PowerShell profile from dotfiles
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dotfiles_dir="$script_dir/dotfiles"
    local ps_profile="$dotfiles_dir/Microsoft.PowerShell_profile.ps1"

    if [ -f "$ps_profile" ]; then
        # Write PowerShell 7 profile
        cp "$ps_profile" "$win_ps7_dir/Microsoft.PowerShell_profile.ps1"
        print_success "Windows PowerShell 7 profile installed from repo"

        # Write Windows PowerShell 5.1 profile
        cp "$ps_profile" "$win_ps5_dir/Microsoft.PowerShell_profile.ps1"
        print_success "Windows PowerShell 5.1 profile installed from repo"
    else
        print_error "PowerShell profile not found: $ps_profile"
        return 1
    fi

    # Install Nerd Font on Windows (copy and register)
    local win_fonts_dir="$win_home/AppData/Local/Microsoft/Windows/Fonts"
    if [ -d ~/.local/share/fonts ] && [ -f ~/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf ]; then
        mkdir -p "$win_fonts_dir"
        cp ~/.local/share/fonts/JetBrainsMonoNerdFont-*.ttf "$win_fonts_dir/" 2>/dev/null || true
        print_info "Registering fonts with Windows..."

        # Register fonts via PowerShell Shell.Application
        powershell.exe -Command '
            $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
            $fonts = Get-ChildItem "$fontDir\JetBrainsMonoNerdFont-*.ttf" -ErrorAction SilentlyContinue
            if ($fonts) {
                $shell = New-Object -ComObject Shell.Application
                $fontsFolder = $shell.Namespace(0x14)
                foreach ($font in $fonts) {
                    $fontsFolder.CopyHere($font.FullName, 0x10)
                }
            }
        ' 2>/dev/null || print_warning "Font registration may require manual installation"

        print_success "JetBrainsMono Nerd Font installed on Windows"
        print_info "Restart Windows Terminal and set font to 'JetBrainsMono Nerd Font'"
    fi

    print_success "Windows PowerShell Oh My Posh configuration complete"
}

################################################################################
# CONTAINER ENGINES
################################################################################

configure_containers() {
    if is_completed "containers"; then
        print_info "Containers already configured, skipping"
        return 0
    fi

    # Check if Docker is already available (Docker Desktop integration)
    if command_exists docker; then
        print_success "Docker already available (Docker Desktop detected)"
        docker --version 2>/dev/null || true
        mark_completed "containers"
        return 0
    fi

    print_header "Container Engines Configuration"

    # Support non-interactive mode via DOCKER_CHOICE env var
    # Default to 1 (Docker Desktop) if not set and non-interactive
    local docker_choice="${DOCKER_CHOICE:-}"

    if [ -z "$docker_choice" ]; then
        echo ""
        echo "Docker configuration options:"
        echo ""
        echo "1) Docker Desktop for Windows (RECOMMENDED)"
        echo "   - Graphical interface"
        echo "   - Automatic WSL2 integration"
        echo "   - Simplified management"
        echo ""
        echo "2) Docker CE native in WSL"
        echo "   - Command line only"
        echo "   - Requires systemd enabled"
        echo "   - More control"
        echo ""
        echo "3) Skip (install manually later)"
        echo ""

        # Check if running non-interactively
        if [ ! -t 0 ]; then
            docker_choice="1"
            print_info "Non-interactive mode: Docker Desktop selected by default"
        else
            read -p "Choice [1/2/3]: " docker_choice
        fi
    fi

    case $docker_choice in
        1)
            print_info "Docker Desktop must be installed on Windows"
            print_info "Download: https://www.docker.com/products/docker-desktop/"
            print_info "Enable WSL2 integration in Docker Desktop Settings"
            ;;
        2)
            if [ "$HAS_SYSTEMD" != "true" ]; then
                print_error "Docker CE requires systemd enabled"
                print_info "Enable systemd first, then re-run the script"
                # Do NOT mark as completed - allow retry after enabling systemd
                return 1
            fi

            # Add Docker repository
            do_sudo apt-get update
            do_sudo apt-get install -y ca-certificates curl gnupg lsb-release
            do_sudo install -m 0755 -d /etc/apt/keyrings

            # Download GPG key to temp, then copy with sudo
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
            do_sudo cp /tmp/docker.asc /etc/apt/keyrings/docker.asc
            do_sudo chmod a+r /etc/apt/keyrings/docker.asc
            rm -f /tmp/docker.asc

            # Create repo file and copy with sudo
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /tmp/docker.list
            do_sudo cp /tmp/docker.list /etc/apt/sources.list.d/docker.list
            rm -f /tmp/docker.list

            do_sudo apt update
            do_sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            do_sudo systemctl enable docker.service
            do_sudo systemctl start docker.service

            do_sudo groupadd docker 2>/dev/null || true
            do_sudo usermod -aG docker $USER

            print_success "Docker CE installed"
            print_warning "Session restart required for docker group"
            ;;
        3)
            print_info "Docker installation skipped"
            ;;
    esac

    mark_completed "containers"
}

################################################################################
# KUBERNETES TOOLS
################################################################################

################################################################################
# MODERN CLI TOOLS (lazygit, lazydocker, atuin, delta, sipp, k6, vegeta)
################################################################################

install_modern_cli_tools() {
    if is_completed "modern_cli_tools"; then
        # Verify essential tools are actually installed before skipping
        local tools_missing=0

        # Check lazygit/lazydocker in go bin
        [ ! -f "$HOME/go/bin/lazygit" ] && tools_missing=1
        [ ! -f "$HOME/go/bin/lazydocker" ] && tools_missing=1

        # Check atuin
        [ ! -f "$HOME/.atuin/bin/atuin" ] && tools_missing=1

        if [ $tools_missing -eq 1 ]; then
            print_warning "Checkpoint set but tools missing, re-running installation..."
            sed -i '/modern_cli_tools/d' "$CHECKPOINT_FILE" 2>/dev/null || true
        else
            print_info "Modern CLI tools already installed, skipping"
            return 0
        fi
    fi

    print_header "Installing Modern CLI Tools"

    # Ensure Go is available for lazygit/lazydocker
    export GOROOT=/usr/local/go
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

    # Ensure Cargo is available for delta
    source $HOME/.cargo/env 2>/dev/null || true

    # lazygit - Terminal UI for git
    if ! command -v lazygit &>/dev/null && [ ! -f "$HOME/go/bin/lazygit" ]; then
        print_info "Installing lazygit..."
        go install github.com/jesseduffield/lazygit@latest
        print_success "lazygit installed to ~/go/bin/"
    else
        print_success "lazygit already installed"
    fi

    # lazydocker - Terminal UI for Docker
    if ! command -v lazydocker &>/dev/null && [ ! -f "$HOME/go/bin/lazydocker" ]; then
        print_info "Installing lazydocker..."
        go install github.com/jesseduffield/lazydocker@latest
        print_success "lazydocker installed to ~/go/bin/"
    else
        print_success "lazydocker already installed"
    fi

    # atuin - Enhanced shell history with sync
    # Note: atuin installs to ~/.atuin/bin, check both PATH and direct location
    if ! command -v atuin &>/dev/null && [ ! -f "$HOME/.atuin/bin/atuin" ]; then
        print_info "Installing atuin..."
        bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)

        # Add atuin to PATH for current session
        export PATH="$HOME/.atuin/bin:$PATH"

        # Add atuin to .zshrc (PATH and init)
        if ! grep -q "atuin init zsh" ~/.zshrc 2>/dev/null; then
            cat >> ~/.zshrc << 'EOF'

# Atuin - Enhanced shell history
export PATH="$HOME/.atuin/bin:$PATH"
eval "$(atuin init zsh)"
EOF
        fi
        print_success "atuin installed (Ctrl+R for enhanced history)"
    else
        print_success "atuin already installed"
    fi

    # delta - Beautiful git diffs
    if ! command_exists delta; then
        print_info "Installing delta..."
        cargo install git-delta
        print_success "delta installed"
    else
        print_success "delta already installed"
    fi

    # SIPp - VoIP/SIP protocol testing tool
    if ! command_exists sipp; then
        print_info "Installing SIPp..."
        # Install dependencies (including libgsl-dev for GSL support)
        sudo apt-get install -y libssl-dev libpcap-dev libncurses5-dev libsctp-dev libgsl-dev cmake

        # Clone and build SIPp
        local sipp_dir="/tmp/sipp-build"
        rm -rf "$sipp_dir"
        git clone https://github.com/SIPp/sipp.git "$sipp_dir"
        cd "$sipp_dir"
        cmake . -DUSE_SSL=1 -DUSE_SCTP=1 -DUSE_PCAP=1 -DUSE_GSL=1
        make -j$(nproc)
        sudo make install
        cd -
        rm -rf "$sipp_dir"
        print_success "SIPp installed with SSL, SCTP, and PCAP support"
    else
        print_success "SIPp already installed ($(sipp -v 2>&1 | head -1))"
    fi

    # k6 - Modern load testing tool (Grafana)
    if ! command_exists k6; then
        print_info "Installing k6..."
        # Use official k6 installation method (download GPG key directly)
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/k6-archive-keyring.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
            sudo tee /etc/apt/sources.list.d/k6.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install -y k6
        print_success "k6 installed (TypeScript/JS load testing)"
    else
        print_success "k6 already installed ($(k6 version 2>&1 | head -1))"
    fi

    # vegeta - HTTP load testing tool (constant-rate)
    if ! command_exists vegeta; then
        print_info "Installing vegeta..."
        go install github.com/tsenart/vegeta@latest
        print_success "vegeta installed (constant-rate load testing)"
    else
        print_success "vegeta already installed"
    fi

    # Configure git to use delta for diffs
    if ! git config --global core.pager | grep -q delta 2>/dev/null; then
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.light false
        git config --global delta.side-by-side true
        git config --global delta.line-numbers true
        print_success "Git configured to use delta for diffs"
    fi

    # Add aliases for lazygit/lazydocker
    if ! grep -q "alias lg=" ~/.zshrc.d/aliases.zsh 2>/dev/null; then
        cat >> ~/.zshrc.d/aliases.zsh << 'EOF'

# Modern CLI tool aliases
alias lg='lazygit'
alias lzd='lazydocker'
EOF
        print_success "Added lg/lzd aliases"
    fi

    mark_completed "modern_cli_tools"
}

install_k8s_tools() {
    if is_completed "k8s_tools"; then
        print_info "Kubernetes tools already installed, skipping"
        return 0
    fi

    print_header "Installing Kubernetes tools"

    # kubectl (with architecture detection)
    local K8S_ARCH=$(dpkg --print-architecture)
    local K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    local tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    retry_download "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${K8S_ARCH}/kubectl" "$tmp_dir/kubectl"
    do_sudo install -o root -g root -m 0755 "$tmp_dir/kubectl" /usr/local/bin/kubectl

    if ! grep -q "kubectl completion zsh" ~/.zshrc; then
        cat >> ~/.zshrc << 'EOF'

# kubectl autocompletion
source <(kubectl completion zsh)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF
    fi
    print_success "kubectl installed"

    # Helm (manual installation to work with sudo password)
    if ! command_exists helm; then
        local helm_tmp=$(mktemp -d)
        local helm_version=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        curl -sL "https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz" | tar xzf - -C "$helm_tmp"
        do_sudo install -m 755 "$helm_tmp/linux-amd64/helm" /usr/local/bin/helm
        rm -rf "$helm_tmp"
    fi
    helm repo add bitnami https://charts.bitnami.com/bitnami > /dev/null 2>&1 || true
    helm repo update > /dev/null 2>&1 || true
    print_success "Helm installed"

    mark_completed "k8s_tools"
}

################################################################################
# CLAUDE CODE CLI
################################################################################

install_claude_code() {
    # Source nvm to ensure PATH includes npm binaries
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null

    # Check if claude command is available
    if command -v claude &>/dev/null; then
        print_success "Claude Code already installed"
        mark_completed "claude_code"
        return 0
    fi

    print_header "Installing Claude Code CLI"

    # Official installer
    curl -fsSL https://claude.ai/install.sh | bash

    mark_completed "claude_code"
}

################################################################################
# TMUX CONFIGURATION
################################################################################

install_tmux_config() {
    if is_completed "tmux"; then
        print_info "tmux already configured, skipping"
        return 0
    fi

    print_header "Configuring tmux"

    # Install TPM
    if [ ! -d ~/.tmux/plugins/tpm ]; then
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        print_success "TPM (tmux Plugin Manager) installed"
    fi

    # Copy tmux.conf from dotfiles
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dotfiles_dir="$script_dir/dotfiles"

    if [ -f "$dotfiles_dir/tmux.conf" ]; then
        cp "$dotfiles_dir/tmux.conf" ~/.tmux.conf
        chmod 644 ~/.tmux.conf
        print_success "tmux.conf installed from repo"
    else
        print_error "tmux.conf not found in dotfiles: $dotfiles_dir/tmux.conf"
        return 1
    fi

    print_success "tmux configured with Windows clipboard integration"
    print_info "Install plugins: start tmux then press Ctrl+B followed by I"

    mark_completed "tmux"
}

################################################################################
# SSH VALIDATION
################################################################################

ssh_validate() {
    if is_completed "ssh_validate"; then
        print_info "SSH keys already validated, skipping"
        return 0
    fi

    print_header "SSH Key Validation"

    # Check if SSH keys exist, if not generate them
    if [ ! -f ~/.ssh/id_ed25519 ] && [ ! -f ~/.ssh/id_ed25519_github ]; then
        print_warning "SSH keys not found. Generating keys..."

        mkdir -p ~/.ssh
        chmod 700 ~/.ssh

        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "${USER_EMAIL}" -N ""
        chmod 600 ~/.ssh/id_ed25519
        chmod 644 ~/.ssh/id_ed25519.pub

        print_success "Default SSH key generated"
    fi

    # Show GitLab prerequisites
    echo ""
    print_info "PREREQUISITES for GitLab SSH authentication:"
    echo "  1. Log in to GitLab: https://gitlab.com/users/sign_in"
    echo "  2. Navigate to: Settings → SSH Keys"
    echo "  3. Add a new key (instructions below)"
    echo ""
    print_info "PREREQUISITES for GitHub SSH authentication:"
    echo "  1. Log in to GitHub: https://github.com/login"
    echo "  2. Navigate to: Settings → SSH and GPG keys → New SSH key"
    echo ""

    # Don't display SSH key here - will be shown at end of setup (Issue 8)
    # Store key path for later display
    export SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"
    if [ ! -f "$SSH_KEY_PATH" ]; then
        export SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_github.pub"
    fi

    # Skip SSH key display here - moved to show_ssh_key_info() at end

    echo ""
    read -p "Press Enter after you have added your SSH key to GitHub/GitLab..."
    echo ""

    # Validate SSH connection
    local retry_count=0
    local max_retries=3

    while [ $retry_count -lt $max_retries ]; do
        print_info "Validating SSH connection (attempt $((retry_count + 1))/$max_retries)..."

        # Test GitHub
        local github_success=false
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "GitHub authentication successful"
            github_success=true
        else
            local github_output=$(ssh -T git@github.com 2>&1)
            if echo "$github_output" | grep -q "successfully authenticated\|Hi.*You've"; then
                print_success "GitHub authentication successful"
                github_success=true
            else
                print_warning "GitHub authentication not validated (may be normal for new key)"
                github_success=true  # Don't fail on this, it might just need setup
            fi
        fi

        # Test GitLab
        local gitlab_success=false
        if ssh -T git@gitlab.com 2>&1 | grep -q "Welcome to GitLab\|successfully authenticated"; then
            print_success "GitLab authentication successful"
            gitlab_success=true
        else
            local gitlab_output=$(ssh -T git@gitlab.com 2>&1)
            if echo "$gitlab_output" | grep -q "Welcome to GitLab\|successfully authenticated"; then
                print_success "GitLab authentication successful"
                gitlab_success=true
            else
                print_warning "GitLab authentication not validated (may be normal for new key)"
                gitlab_success=true
            fi
        fi

        # If both succeeded, we're done
        if [ "$github_success" = "true" ] || [ "$gitlab_success" = "true" ]; then
            print_success "SSH keys validated"
            mark_completed "ssh_validate"
            return 0
        fi

        retry_count=$((retry_count + 1))

        if [ $retry_count -lt $max_retries ]; then
            echo ""
            print_warning "Validation failed. Verify that the key was added correctly."
            read -p "Press Enter to retry (or Ctrl+C to cancel)..."
            echo ""
        fi
    done

    print_error "Could not validate SSH keys after $max_retries attempts"
    print_info "You can validate manually later with: ssh -T git@github.com"

    # Mark as completed anyway to avoid blocking setup
    mark_completed "ssh_validate"
    return 0
}

################################################################################
# REPOSITORY CLONING (IDEMPOTENT)
################################################################################

clone_repos() {
    if is_completed "clone_repos"; then
        print_info "Repositories already cloned, skipping"
        return 0
    fi

    print_header "Git repository cloning (idempotent mode)"

    # Define default repo list
    local default_repos=".claude:git@github.com:nmarxer/.claude.git:~/.claude,.config:git@github.com:nmarxer/.config.git:~/.config,thoughts:git@github.com:nmarxer/thoughts.git:~/thoughts"

    # Use REPO_LIST environment variable or default
    local repo_list="${REPO_LIST:-$default_repos}"

    # Verify SSH access before starting
    print_info "Verifying SSH access..."
    if ! ssh -T git@github.com &>/dev/null && ! ssh -T git@gitlab.com &>/dev/null; then
        print_warning "SSH access not available. Check your SSH keys with: ssh -T git@github.com"
        print_info "You can clone repositories manually later"
        print_info "Continuing with remaining installation..."
        mark_completed "clone_repos"
        return 0  # Continue installation even without SSH access
    fi
    print_success "SSH access validated"

    # Counter for statistics
    local cloned=0
    local updated=0
    local fixed=0
    local failed=0

    # Parse and process each repository
    IFS=',' read -ra repos <<< "$repo_list"

    for repo_entry in "${repos[@]}"; do
        # Parse "name:url:path" format
        IFS=':' read -r repo_name repo_url repo_path <<< "$repo_entry"

        # Expand ~ to home directory
        repo_path="${repo_path/#\~/$HOME}"

        # Skip empty entries
        [ -z "$repo_name" ] && continue

        print_info "Processing: $repo_name"

        # Case 1: Repository already cloned with .git directory
        if [ -d "$repo_path/.git" ]; then
            print_info "  → Existing repository detected, updating..."
            if cd "$repo_path" && git fetch --all --prune && git pull --rebase; then
                print_success "  → $repo_name updated"
                updated=$((updated + 1))
            else
                print_error "  → Failed to update $repo_name"
                failed=$((failed + 1))
            fi
        # Case 2: Directory exists but no .git (corrupted or incomplete clone)
        elif [ -d "$repo_path" ]; then
            print_warning "  → Existing folder without .git detected, removing and re-cloning..."
            if rm -rf "$repo_path" && git clone "$repo_url" "$repo_path" &>> "$LOG_FILE"; then
                print_success "  → $repo_name cloned (from corrupted state)"
                fixed=$((fixed + 1))
            else
                print_error "  → Failed to clone $repo_name"
                failed=$((failed + 1))
            fi
        # Case 3: Fresh clone
        else
            print_info "  → New clone..."
            if git clone "$repo_url" "$repo_path" &>> "$LOG_FILE"; then
                print_success "  → $repo_name cloned (new)"
                cloned=$((cloned + 1))
            else
                print_error "  → Failed to clone $repo_name"
                failed=$((failed + 1))
            fi
        fi
    done

    # Summary
    echo ""
    print_info "Cloning summary:"
    [ $cloned -gt 0 ] && print_success "  - Cloned (new): $cloned"
    [ $updated -gt 0 ] && print_success "  - Updated: $updated"
    [ $fixed -gt 0 ] && print_warning "  - Repaired: $fixed"
    [ $failed -gt 0 ] && print_error "  - Failed: $failed"

    if [ $failed -eq 0 ]; then
        mark_completed "clone_repos"
        return 0
    else
        print_warning "Some repositories failed. Check the errors above."
        print_info "Re-run the script to retry failed clones"
        # Do NOT mark as completed - allow retry on next run
        return 1
    fi
}

################################################################################
# SSH AND GPG
################################################################################

configure_ssh_gpg() {
    if is_completed "ssh_gpg"; then
        # Issue 9: Verify configuration instead of just skipping
        print_info "SSH/GPG configuration verification..."
        local git_name=$(git config --global user.name 2>/dev/null)
        local git_email=$(git config --global user.email 2>/dev/null)
        if [ -n "$git_name" ] && [ -n "$git_email" ]; then
            print_success "Git configured: $git_name <$git_email>"
        else
            print_warning "Git not properly configured"
        fi
        if [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_ed25519_github ]; then
            print_success "SSH keys present"
        else
            print_warning "SSH keys missing"
        fi
        return 0
    fi

    # Always configure Git with user-provided values
    local current_git_name=$(git config --global user.name 2>/dev/null)
    local current_git_email=$(git config --global user.email 2>/dev/null)

    if [ -n "$current_git_name" ] && [ -n "$current_git_email" ]; then
        if [ "$current_git_name" = "$USER_FULLNAME" ] && [ "$current_git_email" = "$USER_EMAIL" ]; then
            print_success "Git already configured correctly: $current_git_name <$current_git_email>"
        else
            print_info "Updating Git configuration from '$current_git_name <$current_git_email>' to '$USER_FULLNAME <$USER_EMAIL>'"
        fi
    fi

    # Always set git config with user-provided values
    git config --global user.name "$USER_FULLNAME"
    git config --global user.email "$USER_EMAIL"
    print_success "Git configured: $USER_FULLNAME <$USER_EMAIL>"

    # Check for existing SSH keys
    if [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_ed25519_github ] || [ -f ~/.ssh/id_rsa ]; then
        print_success "Existing SSH keys detected"
        ls -la ~/.ssh/id_* 2>/dev/null | head -5

        # Check for existing GPG keys
        if gpg --list-secret-keys "$USER_EMAIL" &>/dev/null; then
            print_success "Existing GPG key detected for $USER_EMAIL"
            # Configure GPG signing if key exists
            local gpg_key_id=$(gpg --list-secret-keys --keyid-format=long "$USER_EMAIL" 2>/dev/null | grep sec | awk '{print $2}' | cut -d'/' -f2 | head -1)
            if [ -n "$gpg_key_id" ]; then
                git config --global user.signingkey "$gpg_key_id"
                git config --global commit.gpgsign true
                git config --global tag.gpgsign true
                print_success "GPG signing configured with key $gpg_key_id"
            fi
        fi

        mark_completed "ssh_gpg"
        return 0
    fi

    print_header "SSH and GPG Configuration"

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    # Generate SSH keys with passphrase option
    # Interactive mode: prompt for passphrase (more secure)
    # Non-interactive mode: empty passphrase with warning
    generate_ssh_key() {
        local key_file="$1"
        local comment="$2"

        if [ -f "$key_file" ]; then
            return 0  # Key already exists
        fi

        if [ -t 0 ]; then
            # Interactive: prompt for passphrase (recommended)
            print_info "Generating SSH key: $key_file"
            print_info "You will be prompted for a passphrase (recommended for security)"
            ssh-keygen -t ed25519 -f "$key_file" -C "$comment"
        else
            # Non-interactive: empty passphrase with warning
            print_warning "Generating SSH key without passphrase (non-interactive mode)"
            ssh-keygen -t ed25519 -f "$key_file" -C "$comment" -N ""
        fi
    }

    generate_ssh_key ~/.ssh/id_ed25519_github "${USER_GITHUB_EMAIL}"
    generate_ssh_key ~/.ssh/id_ed25519_gitlab "${USER_GITLAB_EMAIL}"
    generate_ssh_key ~/.ssh/id_ed25519_work "${USER_EMAIL}-work"

    chmod 600 ~/.ssh/id_ed25519_*
    chmod 644 ~/.ssh/id_ed25519_*.pub

    # SSH config
    cat > ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes

Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_gitlab
    IdentitiesOnly yes

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
EOF

    chmod 600 ~/.ssh/config
    print_success "SSH keys generated"

    # Generate GPG key
    print_info "Generating GPG key (passphrase required)..."
    gpg --batch --generate-key << EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $USER_FULLNAME
Name-Email: $USER_EMAIL
Expire-Date: 2y
%commit
EOF

    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long "$USER_EMAIL" | grep sec | awk '{print $2}' | cut -d'/' -f2)

    # Configure Git
    git config --global user.name "$USER_FULLNAME"
    git config --global user.email "$USER_EMAIL"
    git config --global user.signingkey "$GPG_KEY_ID"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    print_success "GPG and Git configured"

    # Display keys
    echo ""
    echo "============================================================================"
    echo "Public keys to add to Git services:"
    echo "============================================================================"
    echo ""
    echo "GitHub SSH:"
    cat ~/.ssh/id_ed25519_github.pub
    echo ""
    echo "GitLab SSH:"
    cat ~/.ssh/id_ed25519_gitlab.pub
    echo ""
    echo "GPG Key:"
    gpg --armor --export $GPG_KEY_ID
    echo ""

    mark_completed "ssh_gpg"
}

################################################################################
# FINAL SETUP
################################################################################

final_setup() {
    if is_completed "final"; then
        # Issue 9: Verify configuration instead of just skipping
        print_info "Final configuration verification..."
        [ -d ~/projects ] && print_success "Project directories exist" || print_warning "Project directories missing"
        [ -f ~/.gitignore_global ] && print_success "Global gitignore configured" || print_warning "Global gitignore missing"
        return 0
    fi

    print_header "Final Configuration"

    # Create project directories IN WSL FILESYSTEM (NOT /mnt/c)
    mkdir -p ~/projects/{personal,work,experiments}
    mkdir -p ~/thoughts
    mkdir -p ~/scripts/{tampermonkey,powershell,ansible}

    print_success "Project structure created in WSL filesystem"
    print_warning "IMPORTANT: Keep projects in ~/ for best performance"
    print_warning "Avoid /mnt/c/ for code (5-10x slower)"

    # Global gitignore
    cat > ~/.gitignore_global << 'EOF'
# === OS Files ===
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini

# === IDEs ===
.vscode/
.idea/
*.swp
*.swo
*~
.project
.classpath
.settings/

# === Dependencies ===
node_modules/
bower_components/
vendor/
.pnp/
.pnp.js

# === Python ===
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
.venv/
pip-log.txt
pip-delete-this-directory.txt
.pytest_cache/
.coverage
htmlcov/
*.egg-info/
dist/
build/
*.egg

# === Secrets & Config ===
.env
.env.local
.env.*.local
*.key
*.pem
id_rsa
id_ed25519
credentials.json
secrets.yaml
*.p12
*.pfx

# === Build & Compiled ===
dist/
build/
out/
target/
*.o
*.a
*.dylib
*.dll
*.exe

# === Logs ===
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
lerna-debug.log*

# === Temporary ===
tmp/
temp/
*.tmp
*.bak
*.backup
*.cache
.sass-cache/

# === Package Managers ===
package-lock.json
yarn.lock
pnpm-lock.yaml
Gemfile.lock
composer.lock

# === Testing ===
coverage/
.nyc_output/
test-results/
*.test.js.snap

# === Misc ===
.Trash-*
nohup.out
.tern-port
.serverless/
.fusebox/
.dynamodb/
.terraform/
EOF

    git config --global core.excludesfile ~/.gitignore_global

    print_success "Final configuration complete"
    mark_completed "final"
}

################################################################################
# WINDOWS INTEGRATION GUIDE
################################################################################

show_windows_integration_guide() {
    # Skip in orchestrated mode (PowerShell bootstrap handles Windows setup)
    if [ "$ORCHESTRATED_MODE" = "1" ]; then
        return 0
    fi

    print_header "Windows-WSL Integration Guide"

    echo ""
    echo "RECOMMENDED WINDOWS INTEGRATION"
    echo "============================================================================"
    echo ""
    echo "1. Windows Terminal (ESSENTIAL)"
    echo "   - Download: Microsoft Store → Windows Terminal"
    echo "   - Configure: Hack Nerd Font (see guide)"
    echo "   - Catppuccin Mocha theme configured automatically"
    echo ""
    echo "2. VS Code Remote-WSL (RECOMMENDED)"
    echo "   - Install VS Code on Windows"
    echo "   - Extension: Remote - WSL"
    echo "   - From WSL: code . (opens project in VS Code Windows)"
    echo ""
    echo "3. File System Performance"
    echo "   - Projects in ~/projects (fast)"
    echo "   - Projects in /mnt/c/Users (5-10x slower)"
    echo "   - Windows access: \\\\wsl\$\\Ubuntu\\home\\$USER"
    echo ""
    echo "4. Clipboard Integration"
    echo "   - tmux configured for Windows clipboard"
    echo "   - xclip can be replaced by clip.exe"
    echo ""
    echo "5. Windows Executable Access"
    echo "   - explorer.exe . (opens Explorer on current folder)"
    echo "   - code.exe file.txt (opens in VS Code)"
    echo "   - All Windows .exe are accessible"
    echo ""
    echo "6. Networking"
    echo "   - localhost shared between Windows and WSL"
    echo "   - Server on WSL:3000 → accessible at Windows localhost:3000"
    echo "   - Windows Firewall manages external access"
    echo ""
    echo "============================================================================"
    echo ""

    [ -t 0 ] && read -p "Press Enter to continue..."
}

################################################################################
# SSH KEY INFO DISPLAY (AT END OF SETUP)
################################################################################

show_ssh_key_info() {
    print_header "SSH Key Information"

    local ssh_key_path="${HOME}/.ssh/id_ed25519.pub"
    if [ ! -f "$ssh_key_path" ]; then
        ssh_key_path="${HOME}/.ssh/id_ed25519_github.pub"
    fi

    if [ -f "$ssh_key_path" ]; then
        echo ""
        print_info "Your SSH public key (copy this to GitHub/GitLab):"
        echo ""
        print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        cat "$ssh_key_path"
        print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        print_info "Add your SSH key to:"
        echo "  - GitHub: https://github.com/settings/ssh/new"
        echo "  - GitLab: https://gitlab.com/-/profile/keys"
        echo ""

        # Copy to clipboard if possible
        if command_exists clip.exe; then
            cat "$ssh_key_path" | clip.exe
            print_success "SSH key copied to Windows clipboard (Ctrl+V to paste)"
        fi
    else
        print_warning "No SSH key found at ~/.ssh/id_ed25519.pub"
        print_info "Generate one with: ssh-keygen -t ed25519 -C 'your.email@example.com'"
    fi

    # Also show GPG key if it exists
    if command_exists gpg; then
        local gpg_key=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)
        if [ -n "$gpg_key" ]; then
            echo ""
            print_info "Your GPG public key (for signing commits):"
            echo ""
            gpg --armor --export "$gpg_key" 2>/dev/null | head -20
            echo "  ... (truncated, use 'gpg --armor --export $gpg_key' for full key)"
            echo ""
            print_info "Add your GPG key to:"
            echo "  - GitHub: https://github.com/settings/gpg/new"
            echo "  - GitLab: https://gitlab.com/-/profile/gpg_keys"
        fi
    fi
}

################################################################################
# INSTALLATION VERIFICATION
################################################################################

verify_installation() {
    print_header "Installation Verification"

    local passed=0
    local failed=0
    local warnings=0

    # Helper function to check command with fallback paths
    # Tools installed via version managers (nvm, pyenv, go) need special handling
    check_cmd_version() {
        local cmd="$1"
        local version=""

        # First try: direct command (in PATH)
        if command -v "$cmd" &>/dev/null; then
            version=$("$cmd" --version 2>&1 | head -1 | cut -c1-50)
            echo "$version"
            return 0
        fi

        # Second try: check known installation paths
        case "$cmd" in
            node|npm)
                if [ -d "$HOME/.nvm" ]; then
                    # Source nvm and get version
                    export NVM_DIR="$HOME/.nvm"
                    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null
                    if command -v "$cmd" &>/dev/null; then
                        version=$("$cmd" --version 2>&1 | head -1 | cut -c1-50)
                        [ -n "$version" ] && echo "$version" && return 0
                    fi
                fi
                ;;
            go)
                if [ -d "/usr/local/go" ]; then
                    version=$(/usr/local/go/bin/go version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            oh-my-posh)
                if [ -f "$HOME/.local/bin/oh-my-posh" ]; then
                    version=$("$HOME/.local/bin/oh-my-posh" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            fzf)
                if [ -f "$HOME/.fzf/bin/fzf" ]; then
                    version=$("$HOME/.fzf/bin/fzf" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            bat)
                # bat is installed as batcat on Ubuntu
                if command -v batcat &>/dev/null; then
                    version=$(batcat --version 2>&1 | head -1 | cut -c1-50)
                    echo "$version"
                    return 0
                fi
                ;;
            fd)
                # fd is installed as fdfind on Ubuntu
                if command -v fdfind &>/dev/null; then
                    version=$(fdfind --version 2>&1 | head -1 | cut -c1-50)
                    echo "$version"
                    return 0
                fi
                ;;
            bun)
                if [ -f "$HOME/.bun/bin/bun" ]; then
                    version=$("$HOME/.bun/bin/bun" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            lazygit)
                # Installed via go install to ~/go/bin/
                if [ -f "$HOME/go/bin/lazygit" ]; then
                    version=$("$HOME/go/bin/lazygit" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            lazydocker)
                # Installed via go install to ~/go/bin/
                if [ -f "$HOME/go/bin/lazydocker" ]; then
                    version=$("$HOME/go/bin/lazydocker" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            atuin)
                # Installed to ~/.atuin/bin/
                if [ -f "$HOME/.atuin/bin/atuin" ]; then
                    version=$("$HOME/.atuin/bin/atuin" --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
            claude)
                # Source nvm first, then check command
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null
                if command -v claude &>/dev/null; then
                    version=$(claude --version 2>&1 | head -1 | cut -c1-50)
                    [ -n "$version" ] && echo "$version" && return 0
                fi
                ;;
        esac

        return 1
    }

    # Check essential commands
    print_info "Checking installed commands..."
    local cmds=("zsh" "git" "python3" "node" "npm" "go" "cargo" "oh-my-posh" "fzf" "eza" "bat" "fd" "rg" "zoxide" "btop" "lazygit" "lazydocker" "atuin" "claude")
    for cmd in "${cmds[@]}"; do
        local version=$(check_cmd_version "$cmd")
        if [ -n "$version" ]; then
            print_success "$cmd: $version"
            passed=$((passed + 1))
        else
            print_error "$cmd: NOT FOUND"
            failed=$((failed + 1))
        fi
    done

    # Check optional commands (warning only)
    print_info "Checking optional commands..."
    local opt_cmds=("docker" "kubectl" "helm" "bun" "pwsh")
    for cmd in "${opt_cmds[@]}"; do
        local version=$(check_cmd_version "$cmd")
        if [ -n "$version" ]; then
            print_success "$cmd: $version"
            passed=$((passed + 1))
        else
            print_warning "$cmd: not installed (optional)"
            warnings=$((warnings + 1))
        fi
    done

    # Check config files
    print_info "Checking configuration files..."
    local configs=(
        "$HOME/.zshrc:Zsh configuration"
        "$HOME/.config/ohmyposh/catppuccin_mocha.omp.json:Oh My Posh theme"
        "$HOME/.tmux.conf:Tmux configuration"
        "$HOME/.gitconfig:Git configuration"
        "$HOME/.ssh/config:SSH configuration"
    )
    for cfg_entry in "${configs[@]}"; do
        local cfg_path="${cfg_entry%%:*}"
        local cfg_name="${cfg_entry#*:}"
        if [ -f "$cfg_path" ]; then
            print_success "$cfg_name: $cfg_path"
            passed=$((passed + 1))
        else
            print_error "$cfg_name: NOT FOUND at $cfg_path"
            failed=$((failed + 1))
        fi
    done

    # Check directories
    print_info "Checking directories..."
    local dirs=(
        "$HOME/projects:Projects directory"
        "$HOME/.zsh:Zsh plugins"
        "$HOME/.fzf:fzf installation"
        "$HOME/.nvm:NVM installation"
        "$HOME/.pyenv:Pyenv installation"
    )
    for dir_entry in "${dirs[@]}"; do
        local dir_path="${dir_entry%%:*}"
        local dir_name="${dir_entry#*:}"
        if [ -d "$dir_path" ]; then
            print_success "$dir_name: $dir_path"
            passed=$((passed + 1))
        else
            print_warning "$dir_name: NOT FOUND at $dir_path"
            warnings=$((warnings + 1))
        fi
    done

    # Summary
    echo ""
    print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_msg "$CYAN" "  VERIFICATION SUMMARY"
    print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Passed: $passed"
    [ $warnings -gt 0 ] && print_warning "Warnings: $warnings (optional components)"
    [ $failed -gt 0 ] && print_error "Failed: $failed"

    if [ $failed -eq 0 ]; then
        print_success "All essential verifications passed!"
        return 0
    else
        print_error "Some verifications failed. Run the setup script to install missing components."
        return 1
    fi
}

################################################################################
# MAIN MENU
################################################################################

show_menu() {
    clear
    print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_msg "$CYAN" "  WSL Ubuntu - Developer Setup Script"
    print_msg "$CYAN" "  Version 1.1.0 | WSL2 Optimized"
    print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1)  Full installation (recommended)"
    echo "2)  Check WSL prerequisites only"
    echo "3)  Enable systemd (requires restart)"
    echo "4)  Interactive installation (by section)"
    echo "5)  Resume interrupted installation"
    echo "6)  Windows integration guide"
    echo "7)  View installation log"
    echo "8)  Reset checkpoints"
    echo "q)  Quit"
    echo ""
    read -p "Choice: " choice

    case $choice in
        1) full_install ;;
        2) check_wsl_environment ;;
        3) enable_systemd ;;
        4) interactive_install ;;
        5) resume_install ;;
        6) show_windows_integration_guide ;;
        7) show_log ;;
        8) reset_checkpoints ;;
        q|Q) exit 0 ;;
        *) print_error "Invalid choice"; sleep 2; show_menu ;;
    esac
}

full_install() {
    print_header "Full WSL Installation"

    # Ask for sudo password upfront
    ask_sudo_password

    check_wsl_environment
    enable_systemd
    create_backup
    update_system
    configure_apt_repos
    install_packages
    install_fzf
    configure_shell
    configure_zsh_files
    optimize_system
    configure_nftables
    configure_sshd
    install_tailscale
    install_python_env
    install_nodejs_env
    install_go_env
    install_powershell
    configure_containers
    install_k8s_tools
    install_claude_code
    install_modern_cli_tools
    install_tmux_config
    ssh_validate
    configure_ssh_gpg
    clone_repos
    final_setup
    show_windows_integration_guide

    # Verify installation
    echo ""
    verify_installation

    show_completion_message
}

interactive_install() {
    print_header "Interactive Installation"

    check_wsl_environment
    ask_yes_no "Enable systemd?" y && enable_systemd
    create_backup

    ask_yes_no "Update system?" y && update_system
    ask_yes_no "Configure APT repositories?" y && configure_apt_repos
    ask_yes_no "Install packages?" y && install_packages
    ask_yes_no "Install fzf (from GitHub)?" y && install_fzf
    ask_yes_no "Configure shell (Zsh/Oh My Posh)?" y && configure_shell
    ask_yes_no "Configure Zsh files?" y && configure_zsh_files
    ask_yes_no "Optimize system?" y && optimize_system
    ask_yes_no "Configure nftables firewall?" y && configure_nftables
    ask_yes_no "Configure SSH server?" y && configure_sshd
    ask_yes_no "Install Tailscale VPN?" y && install_tailscale
    ask_yes_no "Install Python environment?" y && install_python_env
    ask_yes_no "Install Node.js environment?" y && install_nodejs_env
    ask_yes_no "Install Go environment?" y && install_go_env
    ask_yes_no "Install PowerShell 7?" y && install_powershell
    ask_yes_no "Configure containers (Docker/Podman)?" y && configure_containers
    ask_yes_no "Install Kubernetes tools?" && install_k8s_tools
    ask_yes_no "Install Claude Code CLI?" && install_claude_code
    ask_yes_no "Configure tmux?" y && install_tmux_config
    ask_yes_no "Validate SSH keys?" y && ssh_validate
    ask_yes_no "Configure SSH/GPG?" y && configure_ssh_gpg
    ask_yes_no "Final configuration?" y && final_setup
    ask_yes_no "Show Windows integration guide?" y && show_windows_integration_guide

    # Verify installation
    echo ""
    verify_installation

    show_completion_message
}

resume_install() {
    print_info "Resuming installation from last checkpoint"
    full_install
}

################################################################################
# ORCHESTRATED INSTALL (PowerShell Launcher Entry Point)
################################################################################

orchestrated_install() {
    # Set orchestrated mode flag (skips interactive prompts)
    export ORCHESTRATED_MODE=1

    print_header "Orchestrated Installation (PowerShell mode)"

    # Ask for sudo password upfront
    ask_sudo_password

    # Phase 1: System Prerequisites
    check_wsl_environment
    enable_systemd
    create_backup

    # Phase 2: SSH/GPG Configuration + SSH Validation
    configure_ssh_gpg
    if [ "$SKIP_SSH_VALIDATE" != "1" ]; then
        ssh_validate
    else
        print_info "SSH validation skipped (SKIP_SSH_VALIDATE=1)"
        mark_completed "ssh_validate"
    fi

    # Phase 3: Clone Repositories
    clone_repos

    # Phase 4: Main Environment Setup
    update_system
    configure_apt_repos
    install_packages
    install_fzf
    configure_shell
    configure_zsh_files
    optimize_system
    configure_nftables
    configure_sshd
    install_tailscale
    install_python_env
    install_nodejs_env
    install_go_env
    install_powershell
    configure_containers
    install_k8s_tools
    install_claude_code
    install_modern_cli_tools
    install_tmux_config

    # Phase 5: Final Setup
    final_setup
    show_windows_integration_guide

    # Verify installation
    echo ""
    verify_installation

    show_completion_message
}

show_log() {
    if [ -f "$LOG_FILE" ]; then
        less "$LOG_FILE"
    else
        print_error "No log available"
    fi
    read -p "Press Enter to continue..."
    show_menu
}

reset_checkpoints() {
    if ask_yes_no "Reset all checkpoints?" n; then
        rm -f "$CHECKPOINT_FILE"
        print_success "Checkpoints reset"
    fi
    sleep 2
    show_menu
}

show_completion_message() {
    print_header "Installation Complete"

    print_success "WSL configuration complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Restart WSL session: exit then relaunch"
    echo "  2. Install Windows Terminal (Microsoft Store) - if not already done"
    echo "  3. Install VS Code on Windows + Remote-WSL extension"
    echo "  4. Authenticate Git CLI: gh auth login && glab auth login"
    echo ""
    print_warning "REMINDER: Keep projects in ~/ (not /mnt/c/) for performance"
    print_info "Installation log: $LOG_FILE"
    echo ""

    # Display SSH key information at the end (Issue 8)
    show_ssh_key_info
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Create log directory
    mkdir -p "$LOG_DIR"

    # Start logging
    log "INFO" "Script started"
    log "INFO" "Configuration: USER=$USER_FULLNAME, EMAIL=$USER_EMAIL"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_error "Do not run as root. Use sudo when necessary."
        exit 1
    fi

    # Show menu if no arguments
    if [ $# -eq 0 ]; then
        show_menu
    else
        case "$1" in
            --full)
                full_install
                ;;
            --orchestrated)
                orchestrated_install
                ;;
            --check)
                check_wsl_environment
                ;;
            --verify)
                verify_installation
                ;;
            --help)
                echo "Usage: $0 [--full|--orchestrated|--check|--verify|--help]"
                echo "  --full         Full non-interactive installation (menu-based)"
                echo "  --orchestrated Orchestrated installation (PowerShell launcher)"
                echo "  --check        Check WSL prerequisites only"
                echo "  --verify       Verify installation health (check all tools/configs)"
                echo "  --help         Show this help"
                echo ""
                echo "Environment Variables:"
                echo "  SUDO_PASSWORD      Sudo password (non-interactive)"
                echo "  REPO_LIST          Repositories to clone (format: name:url:path,name2:url2:path2)"
                echo "  SKIP_SSH_VALIDATE  Skip SSH validation (default: 0)"
                echo "  SKIP_GPG_SETUP     Skip GPG setup (default: 0)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for help"
                exit 1
                ;;
        esac
    fi
}

# Execute main
main "$@"

# Explicit success exit
log "INFO" "Script completed successfully"
exit 0
