#!/bin/bash
set -e

# -----------------------------
# Configuration
# -----------------------------
GITHUB_USER="travusgonzalez"             # GitHub username
REPO_NAME="linux-administration"         # Repository name
BRANCH="main"                             # Branch name
FOLDER="debian"                           # Folder containing scripts
DEST_DIR="$(pwd)/scripts"                 # Local folder to save scripts

# URL to the manifest file in GitHub repo
MANIFEST_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/refs/heads/$BRANCH/$FOLDER/manifest.txt"

# -----------------------------
# Prepare destination folder
# -----------------------------
mkdir -p "$DEST_DIR"

# -----------------------------
# Fetch manifest
# -----------------------------
echo "Fetching manifest from GitHub..."
FILES=$(curl -fsSL "$MANIFEST_URL")

if [ -z "$FILES" ]; then
    echo "❌ Failed to fetch manifest or manifest is empty."
    exit 1
fi

# -----------------------------
# Download each script
# -----------------------------
for file in $FILES; do
    file=$(echo "$file" | xargs)  # trim spaces
    if [ -z "$file" ]; then continue; fi

    URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/refs/heads/$BRANCH/$FOLDER/$file"
    DEST_FILE="$DEST_DIR/$file"

    echo "Downloading $file ..."
    curl -fsSL "$URL" -o "$DEST_FILE"
    chmod +x "$DEST_FILE"
done

echo "✅ All scripts downloaded to $DEST_DIR"
