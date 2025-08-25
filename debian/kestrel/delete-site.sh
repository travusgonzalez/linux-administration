#!/bin/bash

# ==============================================================================
# Bash Script to Remove a .NET Site from Debian Web Server
#
# Author: Travus Gonzalez
# Date: 2025-08-25
#
# Description:
# This script removes a site (domain) created by setup-webserver.sh:
# - Stops and disables the systemd Kestrel service
# - Removes systemd unit file
# - Removes Nginx config (sites-available + sites-enabled)
# - Deletes the site directory from /var/www
# - Reloads systemd and Nginx
# ==============================================================================

set -euo pipefail

readonly WEB_ROOT="/var/www"

# --- Helper Functions ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_message "ERROR: This script must be run as root or with sudo."
        exit 1
    fi
}

usage() {
    echo "Usage: $0 <domain>"
    echo "Example: $0 api.lan"
    exit 1
}

# --- Main Removal ---
main() {
    check_root

    if [[ $# -ne 1 ]]; then
        usage
    fi

    local DOMAIN="$1"
    local SITE_DIR="$WEB_ROOT/$DOMAIN"
    local SERVICE_FILE="/etc/systemd/system/kestrel-$DOMAIN.service"
    local NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
    local NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"

    log_message "===== Removing Site: $DOMAIN ====="

    # Stop and disable systemd service if it exists
    if systemctl list-unit-files | grep -q "kestrel-$DOMAIN.service"; then
        log_message "Stopping and disabling systemd service..."
        systemctl stop "kestrel-$DOMAIN.service" || true
        systemctl disable "kestrel-$DOMAIN.service" || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    else
        log_message "No systemd service found for $DOMAIN"
    fi

    # Remove Nginx config
    log_message "Removing Nginx configuration..."
    rm -f "$NGINX_AVAILABLE" "$NGINX_ENABLED"

    # Reload Nginx if configs are valid
    if nginx -t; then
        systemctl reload nginx
        log_message "Nginx reloaded successfully."
    else
        log_message "WARNING: Nginx config test failed after removal. Please check manually."
    fi

    # Remove site directory
    if [[ -d "$SITE_DIR" ]]; then
        log_message "Deleting site directory: $SITE_DIR"
        rm -rf "$SITE_DIR"
    else
        log_message "No site directory found at $SITE_DIR"
    fi

    log_message "===== Site $DOMAIN removed successfully ====="
}

main "$@"
