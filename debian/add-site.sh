#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 domain.com"
  exit 1
fi

SITE=$1
WEB_ROOT="/var/www"
SITE_DIR="$WEB_ROOT/$SITE"
PORT_FILE="$WEB_ROOT/ports.txt"

# Determine next available port
START_PORT=5000
if [ -f "$PORT_FILE" ]; then
  LAST_PORT=$(tail -n 1 "$PORT_FILE")
  PORT=$((LAST_PORT+1))
else
  PORT=$START_PORT
fi
echo $PORT >> "$PORT_FILE"

# Create site directory
mkdir -p "$SITE_DIR"

# Create .env with port assignment
echo "DOTNET_URLS=http://0.0.0.0:$PORT" | tee "$SITE_DIR/.env" > /dev/null

# Create Nginx config
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

# Enable Nginx site
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/$SITE.conf
sudo nginx -t
sudo systemctl reload nginx

# Setup SSL with Certbot
sudo certbot --nginx -d $SITE --non-interactive --agree-tos -m admin@$SITE --redirect || true

echo "✅ Site $SITE created on port $PORT"
echo "To deploy: ./deploy-site.sh $SITE <github_repo_url>"
