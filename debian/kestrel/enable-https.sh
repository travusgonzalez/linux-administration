#!/bin/bash

# ==============================================================================
# Bash Script to Enable HTTPS on a Local Nginx Site using Self-Signed Certificates
# with optional HTTP → HTTPS redirect
#
# Author: Travus Gonzalez
# Date: 2025-08-25
#
# Usage:
#   sudo ./enable-https.sh domain_or_ip [--redirect]
#
# Description:
#   Generates a self-signed SSL certificate for a local site,
#   configures Nginx to use it, and reloads Nginx.
#   --redirect will add HTTP → HTTPS redirection.
# ==============================================================================

set -euo pipefail

# --- Args ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 domain_or_ip [--redirect]"
  exit 1
fi

DOMAIN=$1
REDIRECT=false
if [ "${2:-}" == "--redirect" ]; then
  REDIRECT=true
fi

SSL_DIR="/etc/ssl/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
BACKUP_CONF="${NGINX_CONF}.bak"

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

detect_http_port() {
  if [ ! -f "$NGINX_CONF" ]; then
    echo "ERROR: Nginx config not found at $NGINX_CONF"
    exit 1
  fi
  PORT=$(grep -oP 'proxy_pass http://localhost:\K[0-9]+' "$NGINX_CONF" | head -n1)
  if [ -z "$PORT" ]; then
    echo "ERROR: Could not detect port in $NGINX_CONF"
    exit 1
  fi
  log "Detected HTTP port: $PORT"
}

backup_nginx_conf() {
  if [ ! -f "$BACKUP_CONF" ]; then
    log "Backing up Nginx config to $BACKUP_CONF"
    cp "$NGINX_CONF" "$BACKUP_CONF"
  fi
}

configure_nginx_https() {
  log "Adding HTTPS server block..."
  
  cat >> "$NGINX_CONF" <<EOF

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_DIR/$DOMAIN.crt;
    ssl_certificate_key $SSL_DIR/$DOMAIN.key;

    location / {
        proxy_pass http://localhost:$PORT;
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

  if [ "$REDIRECT" = true ]; then
    log "Adding HTTP → HTTPS redirect..."
    # Wrap original HTTP block in redirect if needed
    sed -i '/server_name '"$DOMAIN"'/,/}/ s/listen 80;/listen 80;\n    return 301 https:\/\/$host$request_uri;/' "$NGINX_CONF"
  fi

  log "Testing Nginx configuration..."
  nginx -t
  log "Reloading Nginx..."
  systemctl reload nginx
}

# --- Main ---
check_root
generate_self_signed_cert
detect_http_port
backup_nginx_conf
configure_nginx_https

log "=== HTTPS enabled for $DOMAIN ==="
echo "Certificate: $SSL_DIR/$DOMAIN.crt"
echo "Key: $SSL_DIR/$DOMAIN.key"
if [ "$REDIRECT" = true ]; then
  echo "HTTP → HTTPS redirect enabled"
fi
echo "You may need to trust the certificate in your browser to avoid warnings."
echo "Done."
