#!/bin/bash

# ==============================================================================
# Bash Script to Enable HTTPS on a Local Nginx Site using Self-Signed Certificates
#
# Author: Travus Gonzalez
# Date: 2025-08-25
#
# Usage:
#   sudo ./enable-https.sh domain
#
# Description:
#   Generates a self-signed SSL certificate for a local site,
#   configures Nginx to use it, and reloads Nginx.
# ==============================================================================

set -euo pipefail

# --- Args ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 domain"
  exit 1
fi

DOMAIN=$1
SSL_DIR="/etc/ssl/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

# --- Functions ---
log() { echo -e "[\e[32mINFO\e[0m] $*"; }

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Must run as root (use sudo)."
    exit 1
  fi
}

generate_self_signed_cert() {
  log "Generating self-signed certificate for $DOMAIN..."
  mkdir -p "$SSL_DIR"
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$SSL_DIR/$DOMAIN.key" \
    -out "$SSL_DIR/$DOMAIN.crt" \
    -subj "/CN=$DOMAIN"
}

configure_nginx_https() {
  if [ ! -f "$NGINX_CONF" ]; then
    echo "ERROR: Nginx config not found for $DOMAIN at $NGINX_CONF"
    exit 1
  fi

  log "Updating Nginx config for HTTPS..."
  
  # Backup original
  cp "$NGINX_CONF" "${NGINX_CONF}.bak"

  # Add HTTPS server block if it doesn't exist
  if ! grep -q "listen 443 ssl;" "$NGINX_CONF"; then
    cat >> "$NGINX_CONF" <<EOF

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_DIR/$DOMAIN.crt;
    ssl_certificate_key $SSL_DIR/$DOMAIN.key;

    location / {
        proxy_pass http://localhost:\$(grep -oP 'http://localhost:\K[0-9]+' "$NGINX_CONF");
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  else
    log "HTTPS server block already exists in Nginx config."
  fi

  log "Testing Nginx configuration..."
  nginx -t
  log "Reloading Nginx..."
  systemctl reload nginx
}

# --- Main ---
check_root
generate_self_signed_cert
configure_nginx_https

log "=== HTTPS enabled for $DOMAIN! ==="
echo "Certificate: $SSL_DIR/$DOMAIN.crt"
echo "Key: $SSL_DIR/$DOMAIN.key"
echo "You may need to trust the certificate in your browser to avoid warnings."
echo "Access your site at: https://$DOMAIN"