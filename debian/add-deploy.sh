#!/bin/bash
# Add and deploy a .NET site with automatic port assignment, Nginx + systemd
# version: 3.1

set -e

# Color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo -e "${RED}Usage: $0 domain.com git_repo_url${RESET}"
  exit 1
fi

SITE=$1
REPO_URL=$2
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"
PORT_FILE="$WEB_ROOT/ports.txt"
BUILD_DIR="$SITE_DIR/build"
SERVICE_NAME="kestrel@${SITE}"
ENV_FILE="$SITE_DIR/.env"

# 1️⃣ Determine next available port (check existing)
START_PORT=5000
PORT=$START_PORT
if [ -f "$PORT_FILE" ]; then
    # Read all used ports
    USED_PORTS=$(cat "$PORT_FILE")
    while [[ $USED_PORTS =~ $PORT ]]; do
        PORT=$((PORT+1))
    done
fi
echo $PORT | sudo tee -a "$PORT_FILE" > /dev/null

# 2️⃣ Create site directory and fix permissions
echo -e "${YELLOW}🔧 Creating site directory and setting permissions...${RESET}"
sudo mkdir -p "$SITE_DIR"
sudo chown -R $USER:www-data "$SITE_DIR"
sudo chmod -R 755 "$SITE_DIR"

# 3️⃣ Create .env
echo -e "${BLUE}📝 Creating .env for $SITE...${RESET}"
sudo tee "$ENV_FILE" > /dev/null <<EOL
DOTNET_URLS=http://0.0.0.0:$PORT
ASPNETCORE_ENVIRONMENT=Production
EOL
sudo chown www-data:www-data "$ENV_FILE"
sudo chmod 644 "$ENV_FILE"

# 4️⃣ Set up Nginx
echo -e "${BLUE}⚙️ Setting up Nginx...${RESET}"
NGINX_CONF="/etc/nginx/sites-available/${SITE}.conf"
sudo tee "$NGINX_CONF" > /dev/null <<EOL
server {
    listen 80;
    server_name ${SITE};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/$SITE.conf
sudo nginx -t
sudo systemctl reload nginx

# Setup SSL
sudo certbot --nginx -d $SITE --non-interactive --agree-tos -m admin@$SITE --redirect || true

# 5️⃣ Pull or clone repository
echo -e "${BLUE}📥 Cloning/updating repository...${RESET}"
if [ ! -d "$SITE_DIR/.git" ]; then
    git init "$SITE_DIR"
    git -C "$SITE_DIR" remote add origin "$REPO_URL"
    git -C "$SITE_DIR" fetch
    git -C "$SITE_DIR" checkout -t origin/main || git -C "$SITE_DIR" checkout -t origin/master
else
    git -C "$SITE_DIR" fetch --all
    git -C "$SITE_DIR" reset --hard origin/main || git -C "$SITE_DIR" reset --hard origin/master
    git -C "$SITE_DIR" clean -fd
fi

# 6️⃣ Build the app
echo -e "${BLUE}📦 Publishing .NET app...${RESET}"
dotnet publish "$SITE_DIR" -c Release -o "$BUILD_DIR"

# 7️⃣ Detect main DLL
DLL_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.dll" | grep -v "ref\|deps\|runtimeconfig" | head -n 1)
DLL_NAME=$(basename "$DLL_PATH")
if [ -z "$DLL_NAME" ] || [ ! -f "$DLL_PATH" ]; then
    echo -e "${RED}❌ Could not find main DLL in $BUILD_DIR${RESET}"
    exit 1
fi
echo -e "${GREEN}Detected main DLL: $DLL_NAME${RESET}"

# 8️⃣ Stop service if running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${YELLOW}🛑 Stopping service $SERVICE_NAME...${RESET}"
    sudo systemctl stop "$SERVICE_NAME"
fi

# 9️⃣ Deploy published app
echo -e "${BLUE}🚀 Deploying published app...${RESET}"
sudo find "$SITE_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.env' ! -name 'build' -exec rm -rf {} +
sudo cp -r "$BUILD_DIR"/* "$SITE_DIR/"
sudo rm -rf "$BUILD_DIR"

# 🔟 Update systemd service
echo -e "${BLUE}⚡ Creating/updating systemd service...${RESET}"
SERVICE_FILE="/etc/systemd/system/kestrel@.service"
sudo tee "$SERVICE_FILE" > /dev/null <<EOL
[Unit]
Description=Kestrel .NET Web App for %i
After=network.target

[Service]
WorkingDirectory=/var/www/%i
ExecStart=/usr/bin/dotnet /var/www/%i/$DLL_NAME
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=kestrel-%i
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
EnvironmentFile=/var/www/%i/.env

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload

# 1️⃣1️⃣ Enable + start service
echo -e "${BLUE}▶️ Starting service $SERVICE_NAME...${RESET}"
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo -e "${GREEN}✅ $SITE successfully added and deployed!${RESET}"
echo -e "${YELLOW}Nginx configured on port 80 with SSL, service running under systemd.${RESET}"
echo -e "${YELLOW}Assigned port: $PORT${RESET}"
