#!/bin/bash
set -e

# Configuration
GITHUB_USER="travusgonzalez"
REPO_NAME="linux-administration"
BRANCH="main"
FOLDER="debian"

# Destination folder relative to current directory
DEST_DIR="$(pwd)/scripts"
mkdir -p "$DEST_DIR"

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    apt update && apt install -y jq
fi

# Fetch file list using GitHub API
echo "Fetching file list from GitHub..."
FILES=$(curl -s "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/contents/$FOLDER?ref=$BRANCH" \
    | jq -r '.[].name')

# Download each file
for file in $FILES; do
    URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH/$FOLDER/$file"
    DEST_FILE="$DEST_DIR/$file"

    echo "Downloading $file ..."
    curl -fsSL "$URL" -o "$DEST_FILE"
    chmod +x "$DEST_FILE"
done

echo "✅ All scripts downloaded to $DEST_DIR"