#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 domain.com https://github.com/user/repo.git"
  exit 1
fi

SITE=$1
REPO=$2
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"

if [ ! -d "$SITE_DIR" ]; then
  echo "❌ Site $SITE does not exist. Run add-site.sh first."
  exit 1
fi

# -----------------------------
# 1. Get repo (clone or update)
# -----------------------------
if [ ! -d "$SITE_DIR/.git" ]; then
  git clone "$REPO" "$SITE_DIR"
else
  cd "$SITE_DIR"
  git pull
fi

# -----------------------------
# 2. Detect DLL name from .csproj
# -----------------------------
cd "$SITE_DIR"
CSPROJ=$(find . -maxdepth 1 -name "*.csproj" | head -n 1)

if [ -z "$CSPROJ" ]; then
  echo "❌ No .csproj found in $SITE_DIR"
  exit 1
fi

DLL_NAME=$(grep -oPm1 "(?<=<AssemblyName>)[^<]+" "$CSPROJ")

# If <AssemblyName> not set, fall back to project file name
if [ -z "$DLL_NAME" ]; then
  DLL_NAME=$(basename "$CSPROJ" .csproj)
fi

# -----------------------------
# 3. Publish project
# -----------------------------
dotnet publish "$CSPROJ" -c Release -o "$SITE_DIR"

DLL="$SITE_DIR/$DLL_NAME.dll"
if [ ! -f "$DLL" ]; then
  echo "❌ Expected output DLL $DLL not found"
  exit 1
fi

# -----------------------------
# 4. Create symlink so systemd uses domain name
# -----------------------------
ln -sf "$DLL_NAME.dll" "$SITE_DIR/$SITE.dll"

# -----------------------------
# 5. Enable + restart systemd
# -----------------------------
sudo systemctl enable kestrel@$SITE
sudo systemctl restart kestrel@$SITE

echo "✅ Deployment complete for $SITE from $REPO"
echo "   Running: $DLL"
