#!/bin/bash

# ==============================================================================
# Bash Script to Add a New Site to Multi-Site .NET Server
#
# Author: Travus Gonzalez
# Date: 2025-08-25
#
# Usage:
#   sudo ./add-site.sh domain.com
#
# Description:
#   Adds a new .NET web app site (with Nginx reverse proxy + systemd Kestrel).
#   Automatically assigns next available port >= 5000.
#   By default, does NOT create a sample app unless explicitly requested.
# ==============================================================================

set -euo pipefail

# --- Args ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 domain.com [--with-sample]"
  exit 1
fi

DOMAIN=$1
WITH_SAMPLE=false
if [ "${2:-}" == "--with-sample" ]; then
  WITH_SAMPLE=true
fi

# --- Config ---
WEB_USER="www-data"
WEB_GROUP="www-data"
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$DOMAIN"
DOTNET_BIN="/usr/bin/dotnet"
PORT_START=5000

# --- Functions ---
log() { echo -e "[\e[32mINFO\e[0m] $*"; }

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Must run as root (use sudo)."
    exit 1
  fi
}

find_next_port() {
  local used_ports
  used_ports=$(grep -rhoP 'http://localhost:\K[0-9]+' /etc/systemd/system/kestrel-*.service 2>/dev/null | sort -n | uniq)
  local port=$PORT_START

  while echo "$used_ports" | grep -q "^$port$"; do
    port=$((port + 1))
  done

  echo $port
}

create_site_dir() {
  log "Creating site directory at $SITE_DIR..."
  mkdir -p "$SITE_DIR"
  chown -R "$WEB_USER:$WEB_GROUP" "$SITE_DIR"
  chmod -R 775 "$SITE_DIR"
}

create_dotnet_app() {
  if $WITH_SAMPLE; then
    log "Generating sample .NET app for $DOMAIN..."
    $DOTNET_BIN new web -n "$DOMAIN" -o "$SITE_DIR/src" --framework net8.0 --force
    $DOTNET_BIN publish "$SITE_DIR/src/$DOMAIN.csproj" -c Release -o "$SITE_DIR/publish"
    mv "$SITE_DIR/publish/"* "$SITE_DIR/"
    rm -rf "$SITE_DIR/src" "$SITE_DIR/publish"
    chown -R "$WEB_USER:$WEB_GROUP" "$SITE_DIR"
  else
    log "Skipping sample app creation (use --with-sample to enable)."
  fi
}

create_systemd_service() {
  log "Creating systemd service for Kestrel..."
  cat > "/etc/systemd/system/kestrel-$DOMAIN.service" <<EOF
[Unit]
Description=.NET Web App for $DOMAIN
After=network.target

[Service]
WorkingDirectory=$SITE_DIR
ExecStart=$DOTNET_BIN $SITE_DIR/$DOMAIN.dll --urls "http://localhost:$PORT"
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=dotnet-$DOMAIN
User=$WEB_USER
Group=$WEB_GROUP
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "kestrel-$DOMAIN.service"
  systemctl restart "kestrel-$DOMAIN.service" || true
  log "Systemd service kestrel-$DOMAIN.service created."
}

create_nginx_config() {
  log "Creating Nginx config for $DOMAIN..."
  local CONF_FILE="/etc/nginx/sites-available/$DOMAIN"

  cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

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

  ln -sf "$CONF_FILE" "/etc/nginx/sites-enabled/"
  nginx -t && systemctl reload nginx
  log "Nginx reverse proxy enabled for $DOMAIN."
}

# --- Main ---
check_root
PORT=$(find_next_port)

log "=== Adding site: $DOMAIN on port $PORT ==="
create_site_dir
create_dotnet_app
create_systemd_service
create_nginx_config

log "=== Site $DOMAIN successfully added! ==="
echo
echo "Kestrel service: kestrel-$DOMAIN.service"
echo "Port: $PORT"
echo "Test locally with:"
echo "  curl -H \"Host: $DOMAIN\" http://<server_ip>"
