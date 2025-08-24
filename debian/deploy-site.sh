#!/bin/bash
# A script to deploy or update a .NET web application from a GitHub repository.
# version: 1.10
# Usage: ./deploy-site.sh domain.com
# Ensure you have SSH access to the repository.

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 domain.com"
  exit 1
fi

SITE=$1
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"
REPO_URL="git@github.com:travusgonzalez/darkwinter.xyz.git"

# Ensure site directory exists
mkdir -p "$SITE_DIR"

# Backup existing .env if it exists
ENV_FILE="$SITE_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env..."
    cp "$ENV_FILE" "$ENV_FILE.bak"
fi

# Initialize or update repository
if [ ! -d "$SITE_DIR/.git" ]; then
    echo "Initializing repository in $SITE_DIR..."
    git init "$SITE_DIR"
    git -C "$SITE_DIR" remote add origin "$REPO_URL"
    git -C "$SITE_DIR" fetch
    # Try main first, then master
    if git -C "$SITE_DIR" rev-parse --verify origin/main >/dev/null 2>&1; then
        git -C "$SITE_DIR" checkout -t origin/main
    else
        git -C "$SITE_DIR" checkout -t origin/master
    fi
else
    echo "Repository already exists. Resetting to latest from remote..."
    git -C "$SITE_DIR" fetch --all
    git -C "$SITE_DIR" reset --hard origin/main || git -C "$SITE_DIR" reset --hard origin/master
    git -C "$SITE_DIR" clean -fd
fi

# Restore .env
if [ -f "$ENV_FILE.bak" ]; then
    echo "Restoring .env..."
    mv "$ENV_FILE.bak" "$ENV_FILE"
fi

# Optional: build or restart your .NET app
SERVICE_NAME="${SITE}.service"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Restarting existing service $SERVICE_NAME..."
    sudo systemctl restart "$SERVICE_NAME"
else
    echo "Service $SERVICE_NAME does not exist yet. Please create systemd service to run your app."
fi

echo "✅ Deployment complete for $SITE."
