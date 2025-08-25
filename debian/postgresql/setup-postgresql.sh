#!/bin/bash

# This script automates the setup of a PostgreSQL server on a Debian-based system.
# It includes:
# 1. Updating the system packages.
# 2. Installing PostgreSQL and its contrib package.
# 3. Installing and configuring UFW (Uncomplicated Firewall).
# 4. Creating a PostgreSQL user and database.
# 5. Creating a sample table with data for testing.
# 6. Configuring PostgreSQL to allow remote connections.
# 7. Restarting PostgreSQL to apply changes.

# --- Script Configuration ---
# It's good practice to set variables for usernames, passwords, and database names.
# This makes the script easier to read and modify.
# IMPORTANT: Replace 'YourStrongPassword' with a secure password.
DB_NAME="example_db"
DB_USER="example_user"
DB_PASSWORD="YourStrongPassword"
TABLE_NAME="widgets"

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. System Update ---
echo "Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y
echo "System update complete."
echo "----------------------------------------"

# --- 2. Install PostgreSQL ---
echo "Installing PostgreSQL..."
sudo apt-get install -y postgresql postgresql-contrib
echo "PostgreSQL installation complete."
echo "----------------------------------------"

# --- 3. Configure Firewall (UFW) ---
echo "Configuring Uncomplicated Firewall (UFW)..."
# Install UFW if it's not already present
if ! [ -x "$(command -v ufw)" ]; then
  echo "UFW not found, installing..."
  sudo apt-get install -y ufw
fi

# Reset UFW to a default state to avoid conflicting rules.
sudo ufw --force reset

# Set default policies: deny incoming, allow outgoing.
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH connections. 'OpenSSH' is a predefined application profile.
sudo ufw allow OpenSSH
# You could also specify the port directly: sudo ufw allow 22/tcp

# Allow PostgreSQL connections. The default port is 5432.
sudo ufw allow 5432/tcp

# Enable UFW. The '-y' flag is not standard for ufw enable,
# so we use 'yes' to pipe confirmation.
echo "y" | sudo ufw enable

echo "UFW enabled. Current status:"
sudo ufw status verbose
echo "----------------------------------------"

# --- 4. Create PostgreSQL Database and User ---
echo "Creating PostgreSQL database and user..."
# Using sudo -u postgres to execute commands as the 'postgres' user.
# The psql command is used to interact with the PostgreSQL server.
sudo -u postgres psql <<EOF
CREATE DATABASE ${DB_NAME};
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
EOF
echo "Database '${DB_NAME}' and user '${DB_USER}' created."
echo "----------------------------------------"

# --- 5. Create Sample Table and Insert Data ---
echo "Creating sample table and inserting data..."
sudo -u postgres psql -d ${DB_NAME} <<EOF
CREATE TABLE ${TABLE_NAME} (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    quantity INT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO ${TABLE_NAME} (name, quantity) VALUES ('Gadget', 10);
INSERT INTO ${TABLE_NAME} (name, quantity) VALUES ('Gizmo', 25);
INSERT INTO ${TABLE_NAME} (name, quantity) VALUES ('Thingamajig', 5);

GRANT ALL PRIVILEGES ON TABLE ${TABLE_NAME} TO ${DB_USER};
GRANT USAGE, SELECT ON SEQUENCE ${TABLE_NAME}_id_seq TO ${DB_USER};
EOF
echo "Sample table '${TABLE_NAME}' created and populated in '${DB_NAME}'."
echo "----------------------------------------"

# --- 6. Configure PostgreSQL for Remote Connections ---
# We need to edit two configuration files:
# a) postgresql.conf: To listen on all network interfaces.
# b) pg_hba.conf: To specify which clients can connect.

echo "Configuring PostgreSQL for remote connections..."

# Find the path to postgresql.conf
PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;')
# Find the path to pg_hba.conf
PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;')

echo "postgresql.conf path: ${PG_CONF}"
echo "pg_hba.conf path: ${PG_HBA}"

# a) Modify postgresql.conf to listen on all addresses
# This changes 'localhost' to '*' which means it will accept connections from any IP.
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "${PG_CONF}"
# If the line is not commented out, this will also work.
sudo sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "${PG_CONF}"

# b) Modify pg_hba.conf to allow the new user to connect from any IP using md5 password authentication.
# This adds a new line to the end of the file.
# The format is: TYPE DATABASE USER ADDRESS METHOD
echo "host    ${DB_NAME}    ${DB_USER}    0.0.0.0/0    md5" | sudo tee -a "${PG_HBA}"

echo "PostgreSQL configuration updated."
echo "----------------------------------------"

# --- 7. Restart PostgreSQL ---
echo "Restarting PostgreSQL service to apply changes..."
sudo systemctl restart postgresql
echo "PostgreSQL service restarted."
echo "----------------------------------------"

echo "Setup Complete!"
echo "You can now connect to the PostgreSQL server using:"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Password: ${DB_PASSWORD}"
echo "Host: Your server's IP address"
echo "Port: 5432"
echo "----------------------------------------"