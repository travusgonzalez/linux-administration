#!/bin/bash
# Deploy .NET app with safe stop → copy → start, correct DLL path, and colored output
# version: 1.71

set -e

# Color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
RESET="\e[0m"

if [ -z "$1" ]; then
  echo -e "${RED}Usage: $0 domain.com${RESET}"
  exit 1
fi

SITE=$1
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"
REPO_URL="git@github.com:travusgonzalez/darkwinter.xyz.git"
BUILD_DIR="$SITE_DIR/build"

# Ensure site directory exists
sudo mkdir -p "$SITE_DIR"

# Backup existing .env
ENV_FILE="$SITE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Backing up existing .env...${RESET}"
    sudo cp "$ENV_FILE" "$ENV_FILE.bak"
fi

# Pull latest code (run as current user)
if [ ! -d "$SITE_DIR/.git" ]; then
    echo -e "${BLUE}Initializing repository in $SITE_DIR...${RESET}"
    git init "$SITE_DIR"
    git -C "$SITE_DIR" remote add origin "$REPO_URL"
    git -C "$SITE_DIR" fetch
    git -C "$SITE_DIR" checkout -t origin/main || git -C "$SITE_DIR" checkout -t origin/master
else
    echo -e "${BLUE}Repository exists. Resetting to latest...${RESET}"
    git -C "$SITE_DIR" fetch --all
    git -C "$SITE_DIR" reset --hard origin/main || git -C "$SITE_DIR" reset --hard origin/master
    git -C "$SITE_DIR" clean -fd
fi

# Restore .env
if [ -f "$ENV_FILE.bak" ]; then
    echo -e "${YELLOW}Restoring .env...${RESET}"
    sudo mv "$ENV_FILE.bak" "$ENV_FILE"
fi

# Build the app
echo -e "${BLUE}📦 Publishing .NET app...${RESET}"
dotnet publish "$SITE_DIR" -c Release -o "$BUILD_DIR"

# Detect the main DLL
DLL_PATH=$(find "$BUILD_DIR" -maxdepth 1 -name "*.dll" | head -n 1)
DLL_NAME=$(basename "$DLL_PATH")

if [ -z "$DLL_NAME" ]; then
    echo -e "${RED}❌ No DLL found in build folder. Aborting.${RESET}"
    exit 1
fi
echo -e "${GREEN}Detected main DLL: $DLL_NAME${RESET}"

# Stop service
SERVICE_NAME="kestrel@${SITE}"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${YELLOW}🛑 Stopping service $SERVICE_NAME...${RESET}"
    sudo systemctl stop "$SERVICE_NAME"
fi

# Deploy published app
echo -e "${BLUE}🚀 Deploying published app...${RESET}"
sudo find "$SITE_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.env' ! -name 'build' -exec rm -rf {} +
sudo cp -r "$BUILD_DIR"/* "$SITE_DIR/"
sudo rm -rf "$BUILD_DIR"

# Update systemd service to point to correct DLL
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

# Enable + start service
echo -e "${BLUE}▶️ Starting service $SERVICE_NAME...${RESET}"
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo -e "${GREEN}✅ Deployment complete for $SITE.${RESET}"


sudo systemctl status $SERVICE_NAME"