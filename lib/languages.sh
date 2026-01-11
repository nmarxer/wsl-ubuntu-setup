#!/bin/bash
# lib/languages.sh - Programming language environment installation
# Sourced by wsl_ubuntu_setup.sh

################################################################################
# PYTHON ENVIRONMENT
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
        print_success "pyenv installed"
    else
        print_info "pyenv already installed"
    fi

    # Always set up pyenv for current session (even if already installed)
    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # Install Python 3.12 (-s skips if already installed)
    LATEST_312=$(pyenv install --list | grep "^\s*3\.12" | grep -v "[a-zA-Z]" | tail -1 | xargs)
    if [ -n "$LATEST_312" ]; then
        if pyenv install -s "$LATEST_312"; then
            pyenv global "$LATEST_312"
            print_success "Python $LATEST_312 installed"
        else
            print_error "Failed to install Python $LATEST_312"
            print_error "Check build dependencies with: pyenv doctor"
            print_error "Build log: $LOG_FILE"
            print_info "Common fix: sudo apt install build-essential libssl-dev libffi-dev python3-dev"
            return 1
        fi
    else
        print_warning "Could not determine latest Python 3.12 version"
    fi

    # Install Poetry
    if ! command_exists poetry; then
        curl -sSL --max-time 60 https://install.python-poetry.org | python3 -

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

################################################################################
# NODE.JS ENVIRONMENT
################################################################################

install_nodejs_env() {
    if is_completed "nodejs_env"; then
        print_info "Node.js environment already installed, skipping"
        return 0
    fi

    print_header "Installing Node.js environment"

    # Install NVM (secure download with retry)
    if [ ! -d ~/.nvm ]; then
        local nvm_api_response
        nvm_api_response=$(retry_fetch "https://api.github.com/repos/nvm-sh/nvm/releases/latest" 3 30)
        if [ -z "$nvm_api_response" ]; then
            print_error "Failed to fetch NVM version from GitHub API"
            return 1
        fi
        NVM_VERSION=$(echo "$nvm_api_response" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        # Validate NVM version format (must be vX.Y.Z)
        if [[ ! "$NVM_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            print_error "Invalid NVM version format: '$NVM_VERSION'"
            return 1
        fi
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
        local bun_script=$(mktemp)
        if curl -fsSL --max-time 60 https://bun.sh/install -o "$bun_script"; then
            if verify_download_script "$bun_script" "https://bun.sh/install"; then
                bash "$bun_script"
            else
                print_error "Bun installer verification failed"
            fi
        else
            print_error "Failed to download Bun installer"
        fi
        rm -f "$bun_script"

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

################################################################################
# GO ENVIRONMENT
################################################################################

install_go_env() {
    if is_completed "go_env"; then
        print_info "Go environment already installed, skipping"
        return 0
    fi

    print_header "Installing Go environment"

    # Detect latest Go version (with retry)
    GO_VERSION=$(retry_fetch "https://go.dev/VERSION?m=text" 3 30 | head -1)
    ARCH=$(dpkg --print-architecture)

    # Validate Go version format (must be go1.x.x)
    if [[ ! "$GO_VERSION" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        print_error "Invalid Go version format: '$GO_VERSION' - network error or API change"
        print_info "Retry manually: curl https://go.dev/VERSION?m=text"
        return 1
    fi

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
