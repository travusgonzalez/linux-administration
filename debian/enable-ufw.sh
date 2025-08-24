#!/bin/bash
# UFW setup for Pi-hole on Debian
# UFW (Uncomplicated Firewall) is a user-friendly front-end for managing Linux firewall rules to control network traffic.
# SSH and web admin restricted to local subnet, DNS open

# download script: curl -O https://raw.githubusercontent.com/travusgonzalez/linux-administration/refs/heads/main/debian/enable-ufw.sh
# make executable: chmod +x enable-ssh.sh
# run script: ./enable-ssh.sh


# Exit immediately if a command exits with a non-zero status
set -e

# Update package list
sudo apt update

# Install UFW if not already installed
sudo apt install -y ufw

# Reset any existing rules
sudo ufw reset

# Default deny all incoming, allow all outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Detect local subnet automatically
LOCAL_NET=$(ip -4 route show default | awk '{print $3}' | awk -F. '{print $1 "." $2 "." $3 ".0/24"}')

echo "Detected local subnet: $LOCAL_NET"

# Allow DNS (accessible from anywhere)
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Allow Pi-hole web admin interface only from local subnet
sudo ufw allow from $LOCAL_NET to any port 80 proto tcp
sudo ufw allow from $LOCAL_NET to any port 443 proto tcp

# Allow SSH only from local subnet
sudo ufw allow from $LOCAL_NET to any port 22 proto tcp

# Enable UFW
sudo ufw --force enable

# Ensure UFW starts on boot
sudo systemctl enable ufw

# Show status
sudo ufw status verbose