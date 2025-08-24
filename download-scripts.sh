#!/bin/bash
set -e

# -----------------------------
# Configuration
# -----------------------------
GITHUB_USER="travusgonzalez"        # <-- Replace with your GitHub username
REPO_NAME="repo"              # <-- Replace with your repository name
BRANCH="main"                 # <-- Branch name
FOLDER="debian"               # <-- Folder in the repo containing scripts

# Create a scripts folder relative to where user runs this script
DEST_DIR="$(pwd)/scripts"
mkdir -p "$DEST_DIR"

# -----------------------------
# Fetch file list from GitHub API
# -----------------------------
echo "Fetching file list from GitHub API..."
FILES=$(curl -s "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/contents/$FOLDER?ref=$BRANCH" \
  | grep -oP '"name": "\K[^"]+')

# -----------------------------
# Download or update each file
# -----------------------------
for file in $FILES; do
    URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH/$FOLDER/$file"
    DEST_FILE="$DEST_DIR/$file"

    echo "Processing $file ..."

    # Download temp file first
    TMP_FILE=$(mktemp)
    curl -fsSL "$URL" -o "$TMP_FILE"

    # If file exists, compare; update only if changed
    if [ -f "$DEST_FILE" ]; then
        if cmp -s "$TMP_FILE" "$DEST_FILE"; then
            echo "  No changes detected, skipping."
            rm "$TMP_FILE"
            continue
        else
            echo "  Update detected, overwriting $DEST_FILE"
        fi
    else
        echo "  New file, saving to $DEST_FILE"
    fi

    mv "$TMP_FILE" "$DEST_FILE"
    chmod +x "$DEST_FILE"
done

echo "✅ All scripts downloaded/updated in $DEST_DIR"
