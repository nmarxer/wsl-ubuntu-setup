#!/bin/bash
# lib/containers.sh - Container engine configuration
# Sourced by wsl_ubuntu_setup.sh

################################################################################
# CONTAINER ENGINES (Docker)
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
        local helm_api_response
        helm_api_response=$(retry_fetch "https://api.github.com/repos/helm/helm/releases/latest" 3 30)
        if [ -z "$helm_api_response" ]; then
            print_error "Failed to fetch Helm version from GitHub API"
            rm -rf "$helm_tmp"
            return 1
        fi
        local helm_version=$(echo "$helm_api_response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$helm_version" ]; then
            print_error "Could not parse Helm version from API response"
            rm -rf "$helm_tmp"
            return 1
        fi
        # Use same architecture as kubectl (K8S_ARCH is already set above)
        curl -sL --max-time 120 "https://get.helm.sh/helm-${helm_version}-linux-${K8S_ARCH}.tar.gz" | tar xzf - -C "$helm_tmp"
        do_sudo install -m 755 "$helm_tmp/linux-${K8S_ARCH}/helm" /usr/local/bin/helm
        rm -rf "$helm_tmp"
    fi
    if ! helm repo add bitnami https://charts.bitnami.com/bitnami > /dev/null 2>&1; then
        print_warning "Could not add Bitnami Helm repo (may already exist or network issue)"
        log "WARN" "Helm repo add bitnami failed"
    fi
    if ! helm repo update > /dev/null 2>&1; then
        print_warning "Could not update Helm repos (can retry later with: helm repo update)"
        log "WARN" "Helm repo update failed"
    fi
    print_success "Helm installed"

    mark_completed "k8s_tools"
}
