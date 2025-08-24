#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 domain.com <github_repo_url>"
  exit 1
fi

SITE=$1
REPO_URL=$2
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"

# Ensure site directory exists
mkdir -p "$SITE_DIR"

# Backup existing .env if it exists
ENV_FILE="$SITE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env..."
    cp "$ENV_FILE" "$ENV_FILE.bak"
fi

# Clone or update repository
if [ -d "$SITE_DIR/.git" ]; then
    echo "Repository already exists. Pulling latest changes..."
    git -C "$SITE_DIR" pull
else
    echo "Cloning repository into $SITE_DIR..."
    git clone "$REPO_URL" "$SITE_DIR"
fi

# Restore .env
if [ -f "$ENV_FILE.bak" ]; then
    echo "Restoring .env..."
    mv "$ENV_FILE.bak" "$ENV_FILE"
fi

# Optional: build or restart your .NET app
# Example: using systemd service
SERVICE_NAME="${SITE}.service"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Restarting existing service $SERVICE_NAME..."
    sudo systemctl restart "$SERVICE_NAME"
else
    echo "Service $SERVICE_NAME does not exist yet. Please create systemd service to run your app."
fi

echo "✅ Deployment complete for $SITE."
