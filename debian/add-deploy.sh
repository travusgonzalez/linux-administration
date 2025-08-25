#!/bin/bash
# Deploy or update a .NET site with systemd (framework-dependent or self-contained)
# version: 6.8
# Usage: ./deploy-site.sh domain.com git_repo_url

set -euo pipefail

# Terminal colors
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

# ------------------------------
# Input validation
# ------------------------------
if [ $# -lt 2 ]; then
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
DOTNET_HOME="$SITE_DIR/.dotnet_home"

# ------------------------------
# 1️⃣ Determine next available port
# ------------------------------
START_PORT=5000
PORT=$START_PORT
if [ -f "$PORT_FILE" ]; then
    USED_PORTS=$(cat "$PORT_FILE")
    while [[ $USED_PORTS =~ $PORT ]]; do
        PORT=$((PORT+1))
    done
fi
echo $PORT | sudo tee -a "$PORT_FILE" > /dev/null

# ------------------------------
# 2️⃣ Prepare site directory
# ------------------------------
echo -e "${YELLOW}🔧 Creating site directory and setting permissions...${RESET}"
sudo mkdir -p "$SITE_DIR"
sudo chown -R $USER:www-data "$SITE_DIR"
sudo chmod -R 755 "$SITE_DIR"

# ------------------------------
# 3️⃣ Create .env file & DOTNET_CLI_HOME
# ------------------------------
echo -e "${BLUE}📝 Setting up .env and DOTNET_CLI_HOME for $SITE...${RESET}"
sudo mkdir -p "$DOTNET_HOME"
sudo chown -R www-data:www-data "$DOTNET_HOME"
sudo chmod -R 700 "$DOTNET_HOME"

sudo tee "$ENV_FILE" > /dev/null <<EOL
DOTNET_URLS=http://0.0.0.0:$PORT
ASPNETCORE_ENVIRONMENT=Production
DOTNET_CLI_HOME=$DOTNET_HOME
EOL
sudo chown www-data:www-data "$ENV_FILE"
sudo chmod 644 "$ENV_FILE"

# ------------------------------
# 4️⃣ Setup Nginx
# ------------------------------
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

# Optional SSL
sudo certbot --nginx -d $SITE --non-interactive --agree-tos -m admin@$SITE --redirect || true

# ------------------------------
# 5️⃣ Clone or update repository
# ------------------------------
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

# ------------------------------
# 6️⃣ Publish .NET app
# ------------------------------
echo -e "${BLUE}📦 Publishing .NET app...${RESET}"
rm -rf "$BUILD_DIR"

# Use self-contained single file for Linux x64
dotnet publish "$SITE_DIR" \
    -c Release \
    -r linux-x64 \
    -o "$BUILD_DIR" \
    --self-contained true \
    /p:PublishSingleFile=true \
    /p:PublishTrimmed=true \
    /p:AssemblyName="$SITE"

# This guarantees an executable named "$BUILD_DIR/$SITE"
EXECUTABLE="$BUILD_DIR/$SITE"
sudo chmod +x "$EXECUTABLE"
echo -e "${GREEN}Published main executable: $EXECUTABLE${RESET}"


# ------------------------------
# 7️⃣ Detect main executable or DLL (auto-detect self-contained)
# ------------------------------
BUILD_CONTENT=$(ls -A "$BUILD_DIR")
if [ -z "$BUILD_CONTENT" ]; then
    echo -e "${RED}❌ Build directory is empty!${RESET}"
    exit 1
fi

# Prefer a self-contained executable
EXEC_CMD=$(find "$BUILD_DIR" -maxdepth 1 -type f -executable -printf "%p\n" | head -n 1)

# Fallback: largest DLL (framework-dependent)
if [ -z "$EXEC_CMD" ]; then
    DLL_PATH=$(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.dll" \
        ! -name "*deps*" ! -name "*runtimeconfig*" ! -name "*ref*" \
        -printf "%s %p\n" | sort -nr | head -n1 | awk '{print $2}')
    if [ -z "$DLL_PATH" ]; then
        echo -e "${RED}❌ Could not detect main executable or DLL in $BUILD_DIR${RESET}"
        exit 1
    fi
    EXEC_CMD="/usr/bin/dotnet $DLL_PATH"
fi

echo -e "${GREEN}Detected main app: $EXEC_CMD${RESET}"
# Prefer a self-contained executable
EXEC_CMD=$(find "$BUILD_DIR" -maxdepth 1 -type f -executable -printf "%p\n" | head -n 1)

# Fallback: largest DLL (framework-dependent)
if [ -z "$EXEC_CMD" ]; then
    EXEC_CMD=$(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.dll" \
        ! -name "*deps*" ! -name "*runtimeconfig*" ! -name "*ref*" \
        -printf "%s %p\n" | sort -nr | head -n1 | awk '{print $2}')
    EXEC_CMD="/usr/bin/dotnet $EXEC_CMD"
fi

if [ -z "$EXEC_CMD" ] || [ ! -f "${EXEC_CMD##* }" ]; then
    echo -e "${RED}❌ Could not detect main executable or DLL in $BUILD_DIR${RESET}"
    exit 1
fi

echo -e "${GREEN}Detected main app: $EXEC_CMD${RESET}"

# ------------------------------
# 8️⃣ Stop service if running
# ------------------------------
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${YELLOW}🛑 Stopping service $SERVICE_NAME...${RESET}"
    sudo systemctl stop "$SERVICE_NAME"
fi

# ------------------------------
# 9️⃣ Deploy published app
# ------------------------------
echo -e "${BLUE}🚀 Deploying published app...${RESET}"
sudo find "$SITE_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.env' -exec rm -rf {} +
sudo cp -r "$BUILD_DIR"/. "$SITE_DIR/"
sudo find "$SITE_DIR" -mindepth 1 -maxdepth 1 ! -name ".git" ! -name ".env" -exec chown -R www-data:www-data {} +

# ------------------------------
# 🔟 Setup systemd service (auto correct for self-contained)
# ------------------------------
SERVICE_FILE="/etc/systemd/system/kestrel@.service"
sudo tee "$SERVICE_FILE" > /dev/null <<EOL
[Unit]
Description=Kestrel .NET Web App for %i
After=network.target

[Service]
WorkingDirectory=$SITE_DIR
ExecStart=$EXEC_CMD
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=kestrel-%i
User=www-data
Environment=DOTNET_URLS=http://0.0.0.0:$PORT
Environment=DOTNET_CLI_HOME=$DOTNET_HOME
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOL


# ------------------------------
# 1️⃣1️⃣ Enable + start service
# ------------------------------
echo -e "${BLUE}▶️ Starting service $SERVICE_NAME...${RESET}"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo -e "${GREEN}✅ $SITE successfully deployed!${RESET}"
echo -e "${YELLOW}Assigned port: $PORT${RESET}"
echo -e "${YELLOW}Check Nginx at http://$SITE or https://$SITE${RESET}"
echo -e "Check service status with: ${YELLOW}sudo systemctl status $SERVICE_NAME${RESET}"
echo -e "View logs with: ${YELLOW}sudo journalctl -fu $SERVICE_NAME${RESET}"
echo -e "To redeploy later, run: ${YELLOW}./deploy-site.sh $SITE $REPO_URL${RESET}"