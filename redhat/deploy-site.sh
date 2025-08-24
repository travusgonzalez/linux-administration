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
  echo "❌ Site $SITE does not exist. Run add_site.sh first."
  exit 1
fi

# Clone repo if not already
if [ ! -d "$SITE_DIR/.git" ]; then
  git clone "$REPO" "$SITE_DIR"
else
  cd "$SITE_DIR"
  git pull
fi

# Publish the app into the same folder
cd "$SITE_DIR"
dotnet publish -c Release -o "$SITE_DIR"

# Ensure DLL name matches site (e.g. darkerwinter.com.dll)
DLL="$SITE_DIR/$SITE.dll"
if [ ! -f "$DLL" ]; then
  echo "⚠️ WARNING: Expected $SITE.dll not found in $SITE_DIR"
  echo "Ensure your .csproj outputs a DLL named $SITE.dll"
fi

# Enable + restart Kestrel service
sudo systemctl enable kestrel@$SITE
sudo systemctl restart kestrel@$SITE

echo "✅ Deployment complete for $SITE from $REPO"
