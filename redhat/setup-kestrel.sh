#!/bin/bash
set -e

WEB_ROOT="/var/www"

# 1. Update system
sudo dnf update -y

# 2. Install .NET 9 SDK + runtime
sudo dnf install -y dotnet-sdk-9.0 aspnetcore-runtime-9.0 git

# 3. Install Nginx + Certbot
sudo dnf install -y nginx certbot python3-certbot-nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# 4. Create base web root
sudo mkdir -p "$WEB_ROOT"
sudo chown -R $USER:$USER "$WEB_ROOT"

# 5. Create systemd service template
SERVICE_TEMPLATE="/etc/systemd/system/kestrel@.service"
sudo tee "$SERVICE_TEMPLATE" > /dev/null <<'EOL'
[Unit]
Description=Kestrel .NET Web App for %i
After=network.target

[Service]
WorkingDirectory=/var/www/%i
ExecStart=/usr/bin/dotnet /var/www/%i/%i.dll
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

echo "Server setup complete. Use add_site.sh to create a new website."
