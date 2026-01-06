#!/bin/bash
set -e

echo "Updating package list..."
apt update

echo "Installing openssh-server..."
apt install -y openssh-server

echo "Configuring SSH on port 222..."
tee /etc/ssh/sshd_config.d/99-wsl-secure.conf > /dev/null << 'EOF'
Port 222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
MaxAuthTries 3
EOF

echo "Restarting SSH service..."
systemctl enable ssh
systemctl restart ssh

echo ""
echo "=== SSH configured on port 222 ==="
ss -tlnp | grep 222 || true
echo ""
WSL_IP=$(hostname -I | awk '{print $1}')
echo "Connect with: ssh -p 222 ${SUDO_USER}@${WSL_IP}"
