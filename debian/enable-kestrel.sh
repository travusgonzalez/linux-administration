#!/bin/bash
set -e

WEB_ROOT="/var/www"

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install dependencies
sudo apt install -y wget apt-transport-https software-properties-common lsb-release gnupg git ufw

# 3. Add Microsoft package signing key & repo
wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update

# 4. Install .NET 9 SDK + runtime
sudo apt install -y dotnet-sdk-9.0 aspnetcore-runtime-9.0

# 5. Install Nginx + Certbot
sudo apt install -y nginx certbot python3-certbot-nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# 6. Configure UFW firewall
sudo ufw allow OpenSSH
sudo ufw allow "Nginx Full"
echo "y" | sudo ufw enable

# 7. Create base web root
sudo mkdir -p "$WEB_ROOT"
sudo chown -R $USER:$USER "$WEB_ROOT"

# 8. Create systemd service template
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

echo "✅ Server setup complete."
echo "Now run: ./add-site.sh domain.com"
