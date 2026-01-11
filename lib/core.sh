#!/bin/bash
# lib/core.sh - Core utility functions for WSL Ubuntu Setup
# Sourced by wsl_ubuntu_setup.sh

################################################################################
# LOGGING AND OUTPUT
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

################################################################################
# CHECKPOINT MANAGEMENT
################################################################################

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

################################################################################
# USER INTERACTION
################################################################################

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

################################################################################
# INPUT VALIDATION
################################################################################

# Validate repository entry (prevent command injection)
validate_repo_entry() {
    local entry="$1"

    # Reject empty entries
    if [ -z "$entry" ]; then
        print_error "Empty repository entry"
        return 1
    fi

    # Reject entries containing shell metacharacters (command injection)
    if [[ "$entry" =~ [\$\`\|\;\&\>\<\(\)\{\}] ]]; then
        print_error "Invalid repo entry (contains shell metacharacters): $entry"
        log "SECURITY" "Blocked repo entry with shell metacharacters: $entry"
        return 1
    fi

    # Reject path traversal attempts
    if [[ "$entry" == *".."* ]]; then
        print_error "Invalid repo entry (path traversal detected): $entry"
        log "SECURITY" "Blocked repo entry with path traversal: $entry"
        return 1
    fi

    # Reject entries with newlines or null bytes
    if [[ "$entry" == *$'\n'* ]] || [[ "$entry" == *$'\0'* ]]; then
        print_error "Invalid repo entry (contains control characters)"
        log "SECURITY" "Blocked repo entry with control characters"
        return 1
    fi

    return 0
}

# Validate user input (prevent injection in git config and GPG)
validate_user_input() {
    local var_name="$1"
    local var_value="$2"

    # Reject empty values for required fields
    if [ -z "$var_value" ]; then
        print_error "$var_name cannot be empty"
        return 1
    fi

    # Reject shell metacharacters (command injection prevention)
    # Use glob patterns instead of regex for reliable metacharacter detection
    if [[ "$var_value" == *'$'* ]] || [[ "$var_value" == *'`'* ]] || \
       [[ "$var_value" == *'|'* ]] || [[ "$var_value" == *';'* ]] || \
       [[ "$var_value" == *'&'* ]] || [[ "$var_value" == *'>'* ]] || \
       [[ "$var_value" == *'<'* ]] || [[ "$var_value" == *'('* ]] || \
       [[ "$var_value" == *')'* ]] || [[ "$var_value" == *'['* ]] || \
       [[ "$var_value" == *']'* ]] || [[ "$var_value" == *'{'* ]] || \
       [[ "$var_value" == *'}'* ]] || [[ "$var_value" == *'\'* ]]; then
        print_error "$var_name contains invalid characters (shell metacharacters not allowed)"
        log "SECURITY" "Blocked $var_name with shell metacharacters"
        return 1
    fi

    # Email validation for EMAIL fields
    if [[ "$var_name" == *"EMAIL"* ]]; then
        # Basic email format check (RFC 5322 simplified)
        if [[ ! "$var_value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            print_error "$var_name is not a valid email address: $var_value"
            return 1
        fi
    fi

    # Length limits (prevent buffer issues)
    if [ ${#var_value} -gt 256 ]; then
        print_error "$var_name exceeds maximum length (256 characters)"
        return 1
    fi

    return 0
}

################################################################################
# DOWNLOAD UTILITIES
################################################################################

# Verify downloaded script is safe to execute
verify_download_script() {
    local script_path="$1"
    local source_url="$2"

    # Check file exists and is readable
    if [ ! -f "$script_path" ] || [ ! -r "$script_path" ]; then
        print_error "Downloaded script not found or not readable: $script_path"
        return 1
    fi

    # Check file is not empty
    if [ ! -s "$script_path" ]; then
        print_error "Downloaded script is empty: $source_url"
        return 1
    fi

    # Check for valid shebang (basic sanity check)
    local first_line
    first_line=$(head -1 "$script_path")
    if [[ ! "$first_line" =~ ^#! ]]; then
        print_warning "Downloaded script has no shebang - may not be a valid script: $source_url"
    fi

    # Log checksum for audit trail
    local checksum
    checksum=$(sha256sum "$script_path" 2>/dev/null | cut -d' ' -f1)
    log "AUDIT" "Script checksum for $source_url: SHA256=$checksum"

    return 0
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

# Retry fetch with exponential backoff (returns content to stdout)
retry_fetch() {
    local url="$1"
    local max_retries="${2:-3}"
    local timeout="${3:-30}"
    local retry=0

    while [ $retry -lt $max_retries ]; do
        local result
        result=$(curl -s --max-time "$timeout" "$url" 2>/dev/null)
        if [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            local wait_time=$((2 ** retry))
            log "WARN" "Fetch failed for $url, retry $retry/$max_retries in ${wait_time}s..."
            sleep $wait_time
        fi
    done

    log "ERROR" "Fetch failed after $max_retries attempts: $url"
    return 1
}

# Copy dotfile from local repo or download from GitHub
# Usage: copy_or_download_dotfile "source_name" "dest_path" [--force] [--chmod MODE]
# Example: copy_or_download_dotfile "tmux.conf" "$HOME/.tmux.conf" --chmod 644
copy_or_download_dotfile() {
    local src_name="$1"
    local dst_path="$2"
    shift 2

    # Parse optional flags
    local force=false
    local chmod_mode=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --chmod) chmod_mode="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local dotfiles_dir="$SCRIPT_DIR/dotfiles"
    local github_base="https://raw.githubusercontent.com/nmarxer/wsl-ubuntu-setup/main/dotfiles"
    local local_src="$dotfiles_dir/$src_name"
    local github_url="$github_base/$src_name"

    # Skip if destination exists (unless --force)
    if [ -f "$dst_path" ] && [ "$force" = false ]; then
        print_info "$dst_path already exists, skipping"
        return 0
    fi

    # Ensure destination directory exists
    local dst_dir
    dst_dir=$(dirname "$dst_path")
    [ -d "$dst_dir" ] || mkdir -p "$dst_dir"

    # Try local file first, then GitHub
    if [ -f "$local_src" ]; then
        cp "$local_src" "$dst_path"
        [ -n "$chmod_mode" ] && chmod "$chmod_mode" "$dst_path"
        print_success "$(basename "$dst_path") installed from repo"
        return 0
    elif curl -fsSL "$github_url" -o "$dst_path" 2>/dev/null; then
        [ -n "$chmod_mode" ] && chmod "$chmod_mode" "$dst_path"
        print_success "$(basename "$dst_path") downloaded from GitHub"
        return 0
    else
        print_error "Could not install $(basename "$dst_path") (local not found, download failed)"
        return 1
    fi
}

################################################################################
# SUDO UTILITIES
################################################################################

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
