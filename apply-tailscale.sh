#!/bin/bash
set -e

echo "=== Installing Tailscale on WSL ==="

# Add Tailscale repository
echo "Adding Tailscale repository..."
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | \
    sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | \
    sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

# Install Tailscale
echo "Installing Tailscale..."
sudo apt update
sudo apt install -y tailscale

# Start daemon
echo "Starting Tailscale daemon..."
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Verify
echo ""
echo "=== Tailscale installed ==="
tailscale version
echo ""
echo "Run 'sudo tailscale up' to authenticate"
