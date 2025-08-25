#!/bin/bash
# Enable HTTPS for a local Nginx site using self-signed certificates
# Author: Travus Gonzalez
# Date: 2025-08-25

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

log() { echo -e "[\e[32mINFO\e[0m] $*"; }

check_root() {
  [[ "$EUID" -ne 0 ]] && { echo "ERROR: Must run as root"; exit 1; }
}

generate_cert() {
  log "Generating self-signed certificate..."
  mkdir -p "$SSL_DIR"
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$SSL_DIR/$DOMAIN.key" \
    -out "$SSL_DIR/$DOMAIN.crt" \
    -subj "/CN=$DOMAIN"
}

detect_port() {
  [ ! -f "$NGINX_CONF" ] && { echo "ERROR: Nginx config not found at $NGINX_CONF"; exit 1; }
  PORT=$(grep -oP 'proxy_pass\s+http://localhost:\K[0-9]+' "$NGINX_CONF" | head -n1)
  [ -z "$PORT" ] && { echo "ERROR: Could not detect port in $NGINX_CONF"; exit 1; }
  log "Detected HTTP port: $PORT"
}

backup_conf() {
  [ ! -f "$BACKUP_CONF" ] && { log "Backing up Nginx config"; cp "$NGINX_CONF" "$BACKUP_CONF"; }
}

configure_nginx_https() {
  log "Creating HTTPS server block..."
  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
EOF

  if [ "$REDIRECT" = true ]; then
    cat >> "$NGINX_CONF" <<EOF
    return 301 https://\$host\$request_uri;
}
EOF
  else
    cat >> "$NGINX_CONF" <<EOF
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
  fi

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

  log "Testing Nginx configuration..."
  nginx -t
  log "Reloading Nginx..."
  systemctl reload nginx
}

# --- Main ---
check_root
generate_cert
detect_port
backup_conf
configure_nginx_https

log "=== HTTPS enabled for $DOMAIN ==="
echo "Cert: $SSL_DIR/$DOMAIN.crt"
echo "Key: $SSL_DIR/$DOMAIN.key"
[ "$REDIRECT" = true ] && echo "HTTP → HTTPS redirect enabled"
echo "You may need to add a security exception in your browser for the self-signed certificate."
echo "To revert changes, restore from backup: mv $BACKUP_CONF $NGINX_CONF && systemctl reload nginx"
echo "=================================="