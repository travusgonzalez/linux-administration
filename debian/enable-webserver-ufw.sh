#!/bin/bash
# UFW setup for a Debian web server hosting multiple .NET websites
# SSH restricted to local subnet
# HTTP/HTTPS open to all
# Blocks everything else by default

set -e

# Update package list
apt update

# Install UFW if not installed
apt install -y ufw

# Reset existing rules
ufw --force reset

# Default policy: deny all incoming, allow all outgoing
ufw default deny incoming
ufw default allow outgoing

# Detect local subnet automatically (e.g., 192.168.1.0/24)
LOCAL_NET=$(ip -4 route show default | awk '{print $3}' | awk -F. '{print $1 "." $2 "." $3 ".0/24"}')
echo "Detected local subnet: $LOCAL_NET"

# -----------------------------
# Allow traffic
# -----------------------------

# SSH: allow only from local subnet
ufw allow from $LOCAL_NET to any port 22 proto tcp

# HTTP and HTTPS: open to all
ufw allow 80/tcp
ufw allow 443/tcp

# Optional: Cloudflared or other internal app ports (if needed)
# ufw allow 5000:5100/tcp

# Enable UFW
ufw --force enable

# Ensure UFW starts on boot
systemctl enable ufw

# Show status
ufw status verbose

echo "✅ UFW setup complete: SSH restricted to local subnet, web ports open."
