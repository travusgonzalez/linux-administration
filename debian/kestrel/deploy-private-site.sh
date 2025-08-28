#!/bin/bash

# ==============================================================================
# Bash Script to Deploy or Redeploy a .NET Site from GitHub (Public or Private)
# ==============================================================================
set -euo pipefail

# --- Args ---
if [ $# -lt 2 ]; then
  echo "Usage: $0 domain.com git_repo_url [--force] [--token GITHUB_TOKEN]"
  exit 1
fi

DOMAIN=$1
REPO_URL=$2
FORCE=false
GITHUB_TOKEN=""

shift 2
while (( "$#" )); do
  case "$1" in
    --force) FORCE=true ;;
    --token) shift; GITHUB_TOKEN=$1 ;;
  esac
  shift
done

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

clone_or_update_repo() {
  if [ "$FORCE" = true ]; then
    log "Force flag enabled: recloning repo..."
    rm -rf "$SITE_DIR/src"
    mkdir -p "$SITE_DIR"
  fi

  # Use token for private repos (HTTPS)
  if [[ "$REPO_URL" =~ ^https://github.com/ ]]; then
    if [ -n "$GITHUB_TOKEN" ]; then
      REPO_URL_AUTH=$(echo "$REPO_URL" | sed "s#https://github.com/#https://$GITHUB_TOKEN@github.com/#")
    else
      REPO_URL_AUTH=$REPO_URL
    fi
  else
    REPO_URL_AUTH=$REPO_URL
  fi

  if [ -d "$SITE_DIR/src/.git" ]; then
    log "Existing repo found, pulling latest changes..."
    cd "$SITE_DIR/src"
    git fetch --all
    git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
    git pull
  else
    log "Cloning repo..."
    git clone "$REPO_URL_AUTH" "$SITE_DIR/src"
  fi
}

publish_app() {
  log "Publishing .NET app..."
  PROJECT_FILE=$(find "$SITE_DIR/src" -name "*.csproj" | head -n 1)
  if [ -z "$PROJECT_FILE" ]; then
    echo "ERROR: No .csproj found in repo."
    exit 1
  fi

  rm -rf "$SITE_DIR/app"
  mkdir -p "$SITE_DIR/app"

  $DOTNET_BIN publish "$PROJECT_FILE" -c Release -o "$SITE_DIR/app"

  chown -R "$WEB_USER:$WEB_GROUP" "$SITE_DIR"
  chmod -R 775 "$SITE_DIR"
}

create_or_update_systemd_service() {
  log "Configuring systemd service..."
  local SERVICE_FILE="/etc/systemd/system/kestrel-$DOMAIN.service"

  if [ "$FORCE" = true ] || [ ! -f "$SERVICE_FILE" ]; then
    PORT=$(find_next_port)
  else
    PORT=$(grep -oP 'http://localhost:\K[0-9]+' "$SERVICE_FILE")
  fi

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=.NET Web App for $DOMAIN
After=network.target

[Service]
WorkingDirectory=$SITE_DIR/app
ExecStart=$DOTNET_BIN $SITE_DIR/app/$(basename "$PROJECT_FILE" .csproj).dll --urls "http://localhost:$PORT"
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
  systemctl restart "kestrel-$DOMAIN.service"
  log "Systemd service kestrel-$DOMAIN.service (port $PORT) ready."
}

create_or_update_nginx_config() {
  log "Configuring Nginx..."
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
  log "Nginx reverse proxy active for $DOMAIN."
}

# --- Main ---
check_root
log "=== Deploying or Updating site: $DOMAIN ==="
clone_or_update_repo
publish_app
create_or_update_systemd_service
create_or_update_nginx_config

log "=== Site $DOMAIN successfully deployed! ==="
echo
echo "Kestrel service: kestrel-$DOMAIN.service"
echo "Port: $PORT"
echo "Repo: $REPO_URL"
echo "Force deploy: $FORCE"
echo "Test locally with:"
echo "  curl -H \"Host: $DOMAIN\" http://<server_ip>"
