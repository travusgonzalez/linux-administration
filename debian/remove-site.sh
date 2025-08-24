#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 domain.com"
  exit 1
fi

SITE=$1
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"
PORT_FILE="$WEB_ROOT/ports.txt"
NGINX_CONF="/etc/nginx/sites-available/${SITE}.conf"

# Confirm with user
read -p "Are you sure you want to remove site $SITE? This cannot be undone! [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# Extract port from .env before deleting directory
PORT=""
if [ -f "$SITE_DIR/.env" ]; then
    PORT=$(grep -oP 'DOTNET_URLS=http://0.0.0.0:\K\d+' "$SITE_DIR/.env" || true)
fi

# Remove site directory
if [ -d "$SITE_DIR" ]; then
    echo "Removing site directory $SITE_DIR..."
    sudo rm -rf "$SITE_DIR"
fi

# Remove port from ports.txt (free for reuse)
if [ ! -z "$PORT" ] && [ -f "$PORT_FILE" ]; then
    echo "Freeing port $PORT in $PORT_FILE..."
    sudo sed -i "/^$PORT$/d" "$PORT_FILE"
fi

# Remove Nginx configuration
if [ -f "$NGINX_CONF" ]; then
    echo "Removing Nginx configuration..."
    sudo rm -f "$NGINX_CONF"
    sudo rm -f "/etc/nginx/sites-enabled/${SITE}.conf"
    sudo nginx -t
    sudo systemctl reload nginx
fi

# Revoke SSL certificate with Certbot
echo "Revoking SSL certificate for $SITE..."
sudo certbot delete --cert-name $SITE || true

echo "✅ Site $SITE removed successfully. Port $PORT is now free for reuse."
