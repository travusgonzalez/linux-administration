#!/bin/bash

# download script: curl -O https://raw.githubusercontent.com/travusgonzalez/linux-administration/refs/heads/main/debian/enable-ssh.sh
# make executable: chmod +x enable-ssh.sh
# run script: ./enable-ssh.sh

# Exit immediately if a command exits with a non-zero status
set -e

echo "Updating package list..."
sudo apt update

echo "Upgrading packages..."
sudo apt upgrade -y

echo "Installing OpenSSH server..."
sudo apt install -y openssh-server

echo "Starting SSH service..."
sudo systemctl start ssh

echo "Enabling SSH to start on boot..."
sudo systemctl enable ssh

# Optional: configure firewall if UFW is installed
if command -v ufw >/dev/null 2>&1; then
    echo "🛡️ Allowing SSH through UFW firewall..."
    sudo ufw allow ssh
fi

echo "SSH setup complete. You can now connect using: ssh username@your_ip"