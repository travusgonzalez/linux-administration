#!/bin/bash

# ==============================================================================
# Bash Script for Minimal Debian Web Server Setup with Multi-Site .NET Support
#
# Author: Travus Gonzalez
# Date: 2025-08-25
#
# Description:
# This script automates the installation and configuration of a web server stack
# on a fresh Debian 12 (or later) system. It sets up .NET 8/9, Nginx as a
# reverse proxy, UFW firewall, and placeholders for multi-site Kestrel apps
# running as systemd services.
# 
# To install this script, execute the following commands on your Debian server:
# sudo apt-get update && sudo apt-get install -y wget && wget https://raw.githubusercontent.com/travusgonzalez/linux-administration/refs/heads/main/debian/setup-webserver.sh && chmod +x setup-webserver.sh
# ==============================================================================

# --- Script Configuration ---

# Exit immediately if a command exits with a non-zero status.
set -e

# Treat unset variables as an error when substituting.
set -u

# Define an associative array for the sites to be configured.
# SYNTAX: [domain]="port"
# NOTE: Use local-only domains (e.g., .local, .lan) or names you can resolve
# via your hosts file or a local DNS server.
declare -A SITES_CONFIG
SITES_CONFIG=(
    ["site1.local"]="5001"
    ["site2.local"]="5002"
    ["api.local"]="5003"
)

# User and group to run the web applications. 'www-data' is standard for Nginx.
readonly WEB_USER="www-data"
readonly WEB_GROUP="www-data"

# Base directory for all web content.
readonly WEB_ROOT="/var/www"

# Log file for this script's execution.
readonly LOG_FILE="/var/log/setup_webserver.log"

# --- Helper Functions ---

# Function to log messages to both console and log file.
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if the script is run as root.
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_message "ERROR: This script must be run as root or with sudo."
        exit 1
    fi
}

# --- Main Setup Functions ---

# 1. Initial System Update and Prerequisite Installation
initial_setup() {
    log_message "Starting initial system setup..."
    apt-get update -y
    apt-get install -y apt-transport-https curl wget gnupg2 software-properties-common lsb-release
    log_message "Initial setup complete."
}

# 2. Install and Configure .NET SDKs and Runtimes
install_dotnet() {
    log_message "Installing .NET SDKs and Runtimes..."

    # Add Microsoft package signing key and feed
    # This process is idempotent; running it again won't cause issues.
    if [ ! -f /etc/apt/trusted.gpg.d/microsoft.gpg ]; then
        log_message "Adding Microsoft package repository..."
        wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
        dpkg -i packages-microsoft-prod.deb
        rm packages-microsoft-prod.deb
        apt-get update -y
    else
        log_message "Microsoft package repository already configured."
    fi

    # Install SDKs. Runtimes are included with the SDKs.
    log_message "Installing .NET 8 and .NET 9 SDKs..."
    apt-get install -y dotnet-sdk-8.0 dotnet-sdk-9.0

    # Verify installation
    log_message "Verifying .NET installations..."
    if command -v dotnet &> /dev/null; then
        dotnet --list-sdks | tee -a "$LOG_FILE"
        log_message ".NET installation successful."
    else
        log_message "ERROR: 'dotnet' command not found after installation."
        exit 1
    fi
}

# 3. Install SSH Server
install_ssh() {
    log_message "Ensuring OpenSSH Server is installed and running..."
    if ! dpkg -l | grep -q openssh-server; then
        apt-get install -y openssh-server
    fi
    systemctl enable ssh
    systemctl start ssh
    log_message "OpenSSH Server is configured and running."
}

# 4. Install and Configure UFW (Firewall)
setup_firewall() {
    log_message "Setting up UFW firewall..."
    apt-get install -y ufw

    # Deny all incoming by default
    ufw default deny incoming
    ufw default allow outgoing

    # Allow required ports
    ufw allow ssh       # Port 22
    ufw allow http      # Port 80
    ufw allow https     # Port 443

    # Enable UFW without prompt
    ufw enable

    log_message "UFW firewall enabled and configured."
    ufw status | tee -a "$LOG_FILE"
}

# 5. Install and Configure Nginx
install_nginx() {
    log_message "Installing Nginx..."
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    log_message "Nginx installed and started."
}

# 6. Install Certbot (for Let's Encrypt)
install_certbot() {
    log_message "Installing Certbot and Nginx plugin..."
    apt-get install -y certbot python3-certbot-nginx
    log_message "Certbot installation complete."
    log_message "NOTE: Certbot requires a public domain and DNS records pointing to this server's public IP. It will not work for '.local' domains without special setup."
}

# 7. Create Web Directory Structure and Sample Apps
setup_web_apps() {
    log_message "Setting up web directory structure and sample applications..."

    # Ensure the web user/group exists
    if ! getent group "$WEB_GROUP" >/dev/null; then
        groupadd "$WEB_GROUP"
    fi
    if ! id "$WEB_USER" >/dev/null 2>&1; then
        useradd -r -g "$WEB_GROUP" -s /usr/sbin/nologin -d "$WEB_ROOT" "$WEB_USER"
    fi

    # Counter to alternate .NET versions for samples
    local dotnet_version_counter=8

    for DOMAIN in "${!SITES_CONFIG[@]}"; do
        local SITE_DIR="$WEB_ROOT/$DOMAIN"
        local PORT="${SITES_CONFIG[$DOMAIN]}"
        local DOTNET_VERSION="net${dotnet_version_counter}.0"

        log_message "Processing site: $DOMAIN on port $PORT using $DOTNET_VERSION"

        # Create site directory
        mkdir -p "$SITE_DIR"

        # Create a minimal .NET web app if it doesn't exist
        if [ ! -f "$SITE_DIR/$DOMAIN.dll" ]; then
            log_message "Creating sample .NET app for $DOMAIN..."
            # Using --force to be idempotent in case directory exists but is empty
            dotnet new web -n "$DOMAIN" -o "$SITE_DIR/src" --framework "$DOTNET_VERSION" --force
            dotnet publish "$SITE_DIR/src/$DOMAIN.csproj" -c Release -o "$SITE_DIR/publish"
            mv "$SITE_DIR/publish/"* "$SITE_DIR/"
            rm -rf "$SITE_DIR/src" "$SITE_DIR/publish"
        else
            log_message "Sample app for $DOMAIN already exists."
        fi

        # Set ownership
        chown -R "$WEB_USER":"$WEB_GROUP" "$SITE_DIR"
        chmod -R 775 "$SITE_DIR"

        # Create systemd service file for Kestrel
        log_message "Creating systemd service for $DOMAIN..."
        cat > "/etc/systemd/system/kestrel-$DOMAIN.service" <<EOF
[Unit]
Description=.NET Web App for $DOMAIN
After=network.target

[Service]
WorkingDirectory=$SITE_DIR
ExecStart=/usr/bin/dotnet $SITE_DIR/$DOMAIN.dll --urls "http://localhost:$PORT"
Restart=always
# Restart service after 10 seconds if it crashes
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=dotnet-$DOMAIN
User=$WEB_USER
Group=$WEB_GROUP
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
EOF

        # Reload systemd, enable and start the service
        systemctl daemon-reload
        systemctl enable "kestrel-$DOMAIN.service"
        systemctl restart "kestrel-$DOMAIN.service"
        log_message "Service kestrel-$DOMAIN.service configured and started."

        # Alternate .NET version for the next app
        if [ "$dotnet_version_counter" -eq 8 ]; then
            dotnet_version_counter=9
        else
            dotnet_version_counter=8
        fi
    done
}

# 8. Configure Nginx Reverse Proxy Virtual Hosts
configure_nginx_proxy() {
    log_message "Configuring Nginx reverse proxy..."

    for DOMAIN in "${!SITES_CONFIG[@]}"; do
        local PORT="${SITES_CONFIG[$DOMAIN]}"
        local CONF_FILE="/etc/nginx/sites-available/$DOMAIN"

        log_message "Creating Nginx config for $DOMAIN..."

        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Optional: Redirect www to non-www
    # if (\$host = www.$DOMAIN) {
    #     return 301 https://\$host\$request_uri;
    # }

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

        # Enable the site by creating a symlink
        # -f flag makes it idempotent (replaces existing link)
        ln -sf "$CONF_FILE" "/etc/nginx/sites-enabled/"
    done

    # Test Nginx configuration and reload
    if nginx -t; then
        log_message "Nginx configuration is valid. Reloading..."
        systemctl reload nginx
    else
        log_message "ERROR: Nginx configuration test failed. Please check the files in /etc/nginx/sites-available/."
        exit 1
    fi
}

# --- Main Execution ---

main() {
    # Clear log file for new run
    > "$LOG_FILE"

    check_root
    log_message "===== Starting Web Server Setup Script ====="

    initial_setup
    install_ssh
    setup_firewall
    install_dotnet
    install_nginx
    install_certbot
    setup_web_apps
    configure_nginx_proxy

    log_message "===== Script Finished Successfully ====="
    echo
    echo "--------------------------------------------------"
    echo "  Minimal Debian Web Server Setup Complete!"
    echo "--------------------------------------------------"
    echo "  Log file available at: $LOG_FILE"
    echo
    echo "  Configured Sites:"
    for DOMAIN in "${!SITES_CONFIG[@]}"; do
        PORT="${SITES_CONFIG[$DOMAIN]}"
        echo "  - http://$DOMAIN (proxied to Kestrel on port $PORT)"
        systemctl status "kestrel-$DOMAIN.service" --no-pager | grep "Active:"
    done
    echo
    echo "  Next Steps:"
    echo "  1. On your local machine (not the server), edit your 'hosts' file to map"
    echo "     the server's IP address to the domains:"
    echo "     <server_ip>  site1.local site2.local api.local"
    echo "  2. Test the sites in your browser or with 'curl'."
    echo "     Example: curl -H \"Host: site1.local\" http://<server_ip>"
    echo "  3. To enable HTTPS with a REAL domain, run:"
    echo "     sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com"
    echo "--------------------------------------------------"
}

# Run the main function
main