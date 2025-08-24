#!/bin/bash
set -e

# Configuration
GITHUB_USER="travusgonzalez"
REPO_NAME="linux-administration"
BRANCH="main"
FOLDER="debian"
DEST_DIR="$(pwd)/scripts"

mkdir -p "$DEST_DIR"

# GitHub folder URL
GITHUB_URL="https://github.com/$GITHUB_USER/$REPO_NAME/tree/$BRANCH/$FOLDER"

echo "Fetching file list from GitHub folder: $GITHUB_URL"

# Scrape the folder page for file names ending with .sh
FILES=$(curl -fsSL "$GITHUB_URL" \
    | grep -oP 'js-navigation-open[^>]+>([^<]+\.sh)<\/a>' \
    | sed -E 's/.*>([^<]+)<\/a>/\1/')

if [ -z "$FILES" ]; then
    echo "❌ No scripts found in folder. Check URL or branch."
    exit 1
fi

# Download each script from raw.githubusercontent.com
for file in $FILES; do
    file=$(echo "$file" | xargs)  # trim spaces
    URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH/$FOLDER/$file"
    DEST_FILE="$DEST_DIR/$file"

    echo "Downloading $file ..."
    curl -fsSL "$URL" -o "$DEST_FILE"
    chmod +x "$DEST_FILE"
done

echo "✅ All scripts downloaded to $DEST_DIR"
