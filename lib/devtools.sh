#!/bin/bash
# lib/devtools.sh - Development tools installation
# Sourced by wsl_ubuntu_setup.sh

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
        if ! curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/k6-archive-keyring.gpg 2>/dev/null; then
            print_warning "Could not add k6 GPG key (may already exist)"
            log "WARN" "k6 GPG key installation returned non-zero"
        fi
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

    # Official installer with verification
    local claude_script=$(mktemp)
    if curl -fsSL --max-time 60 https://claude.ai/install.sh -o "$claude_script"; then
        if verify_download_script "$claude_script" "https://claude.ai/install.sh"; then
            bash "$claude_script"
            print_success "Claude Code installed"
        else
            print_error "Claude Code installer verification failed"
        fi
    else
        print_error "Failed to download Claude Code installer"
    fi
    rm -f "$claude_script"

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

    # Install tmux.conf using helper (handles local/GitHub fallback)
    copy_or_download_dotfile "tmux.conf" "$HOME/.tmux.conf" --force --chmod 644 || return 1

    print_success "tmux configured with Windows clipboard integration"
    print_info "Install plugins: start tmux then press Ctrl+B followed by I"

    mark_completed "tmux"
}
